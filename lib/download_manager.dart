import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Status { queued, downloading, paused, done, failed }

class DownloadTask {
  final String id, url;
  String name;
  int total, received;
  bool ranges;
  Status status;
  String? error;
  double speed = 0;
  int _lastBytes = 0;

  DownloadTask({required this.id, required this.url, this.name = '', this.total = 0,
      this.received = 0, this.ranges = false, this.status = Status.queued, this.error});

  double get progress => total > 0 ? (received / total).clamp(0, 1).toDouble() : 0;

  Map<String, dynamic> toJson() => {
        'id': id, 'url': url, 'name': name, 'total': total, 'received': received,
        'ranges': ranges, 'status': status.index,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
        id: j['id'], url: j['url'], name: j['name'], total: j['total'],
        received: j['received'], ranges: j['ranges'], status: Status.values[j['status']],
      );
}

class DownloadManager extends ChangeNotifier {
  static final instance = DownloadManager._();
  DownloadManager._();

  final List<DownloadTask> tasks = [];
  int maxConcurrent = 2;
  int parts = 4;
  bool wifiOnly = false;
  late Directory dir;
  final Map<String, bool> _cancel = {};
  final Map<String, List<HttpClient>> _clients = {};
  SharedPreferences? _prefs;

  Future<void> init() async {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    dir = Directory('${base.path}/Downloads');
    await dir.create(recursive: true);
    _prefs = await SharedPreferences.getInstance();
    maxConcurrent = _prefs!.getInt('max') ?? 2;
    parts = _prefs!.getInt('parts') ?? 4;
    wifiOnly = _prefs!.getBool('wifi') ?? false;
    final raw = _prefs!.getString('tasks');
    if (raw != null) {
      for (final j in jsonDecode(raw)) {
        final t = DownloadTask.fromJson(j);
        if (t.status == Status.downloading || t.status == Status.queued) t.status = Status.paused;
        tasks.add(t);
      }
    }
    Timer.periodic(const Duration(seconds: 1), (_) {
      var changed = false;
      for (final t in tasks.where((t) => t.status == Status.downloading)) {
        t.speed = (t.received - t._lastBytes).toDouble();
        t._lastBytes = t.received;
        changed = true;
      }
      if (changed) notifyListeners();
    });
    notifyListeners();
  }

  void setSettings({int? max, int? p, bool? wifi}) {
    if (max != null) maxConcurrent = max;
    if (p != null) parts = p;
    if (wifi != null) wifiOnly = wifi;
    _prefs?.setInt('max', maxConcurrent);
    _prefs?.setInt('parts', parts);
    _prefs?.setBool('wifi', wifiOnly);
    notifyListeners();
    _pump();
  }

  void _save() => _prefs?.setString('tasks', jsonEncode(tasks.map((t) => t.toJson()).toList()));

  String? add(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
      return 'Enter a valid http(s) link';
    }
    tasks.insert(0, DownloadTask(id: DateTime.now().microsecondsSinceEpoch.toString(), url: u.toString()));
    _save();
    notifyListeners();
    _pump();
    return null;
  }

  void pause(DownloadTask t) {
    _cancel[t.id] = true;
    for (final c in _clients[t.id] ?? <HttpClient>[]) {
      c.close(force: true);
    }
    t.status = Status.paused;
    t.speed = 0;
    _save();
    notifyListeners();
    _pump();
  }

  void resume(DownloadTask t) {
    t.status = Status.queued;
    t.error = null;
    notifyListeners();
    _pump();
  }

  Future<void> remove(DownloadTask t) async {
    if (t.status == Status.downloading) pause(t);
    tasks.remove(t);
    final base = '${dir.path}/.${t.id}';
    for (var i = 0; i < 16; i++) {
      final f = File('$base.part$i');
      if (await f.exists()) await f.delete();
    }
    _save();
    notifyListeners();
  }

  void _pump() {
    var active = tasks.where((t) => t.status == Status.downloading).length;
    for (final t in tasks.reversed) {
      if (active >= maxConcurrent) break;
      if (t.status == Status.queued) {
        active++;
        _run(t);
      }
    }
  }

  Future<void> _run(DownloadTask t) async {
    t.status = Status.downloading;
    _cancel[t.id] = false;
    _clients[t.id] = [];
    notifyListeners();
    try {
      if (wifiOnly) {
        final c = await Connectivity().checkConnectivity();
        if (!c.contains(ConnectivityResult.wifi) && !c.contains(ConnectivityResult.ethernet)) {
          throw 'Waiting for Wi-Fi';
        }
      }
      if (t.name.isEmpty) await _probe(t);
      final n = (t.ranges && t.total > (1 << 20)) ? parts.clamp(1, 16) : 1;
      final base = '${dir.path}/.${t.id}';
      final counts = List<int>.filled(n, 0);
      final jobs = <Future>[];
      for (var i = 0; i < n; i++) {
        final s = t.total > 0 ? (t.total * i / n).floor() : 0;
        final e = t.total > 0 ? (i == n - 1 ? t.total - 1 : (t.total * (i + 1) / n).floor() - 1) : -1;
        jobs.add(_part(t, File('$base.part$i'), i, s, e, counts));
      }
      try {
        await Future.wait(jobs, eagerError: true);
      } catch (_) {
        for (final c in _clients[t.id]!) {
          c.close(force: true);
        }
        rethrow;
      }
      // merge
      final out = await _uniqueFile(t.name);
      final sink = out.openWrite();
      for (var i = 0; i < n; i++) {
        final f = File('$base.part$i');
        await sink.addStream(f.openRead());
        await f.delete();
      }
      await sink.close();
      t.received = t.total > 0 ? t.total : await out.length();
      t.status = Status.done;
      t.speed = 0;
    } catch (e) {
      if (_cancel[t.id] == true) return; // paused by user
      t.status = Status.failed;
      t.error = e.toString();
      t.speed = 0;
    } finally {
      _save();
      notifyListeners();
      _pump();
    }
  }

  Future<void> _part(DownloadTask t, File f, int i, int s, int e, List<int> counts) async {
    var have = await f.exists() ? await f.length() : 0;
    if (e >= 0 && have > e - s + 1) {
      await f.delete();
      have = 0;
    }
    if (!t.ranges && have > 0) {
      await f.delete();
      have = 0;
    }
    counts[i] = have;
    _updateReceived(t, counts);
    if (e >= 0 && have == e - s + 1) return;
    final client = HttpClient();
    _clients[t.id]!.add(client);
    final req = await client.getUrl(Uri.parse(t.url));
    if (t.ranges) req.headers.set('Range', 'bytes=${s + have}-${e >= 0 ? e : ''}');
    final res = await req.close();
    if (res.statusCode != 200 && res.statusCode != 206) throw 'HTTP ${res.statusCode}';
    if (t.ranges && res.statusCode != 206) throw 'Server ignored resume request';
    final sink = f.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        counts[i] += chunk.length;
        _updateReceived(t, counts);
      }
    } finally {
      await sink.close();
    }
  }

  void _updateReceived(DownloadTask t, List<int> counts) =>
      t.received = counts.fold(0, (a, b) => a + b);

  Future<void> _probe(DownloadTask t) async {
    final client = HttpClient();
    _clients[t.id]!.add(client);
    final req = await client.getUrl(Uri.parse(t.url));
    req.headers.set('Range', 'bytes=0-0');
    final res = await req.close();
    if (res.statusCode == 206) {
      final cr = res.headers.value('content-range') ?? '';
      t.total = int.tryParse(cr.split('/').last) ?? 0;
      t.ranges = t.total > 0;
    } else if (res.statusCode == 200) {
      t.total = res.contentLength > 0 ? res.contentLength : 0;
      t.ranges = false;
    } else {
      client.close(force: true);
      throw 'HTTP ${res.statusCode}';
    }
    final cd = res.headers.value('content-disposition') ?? '';
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    var name = m?.group(1) ?? '';
    if (name.isEmpty) {
      final segs = Uri.parse(t.url).pathSegments.where((s) => s.isNotEmpty);
      name = segs.isNotEmpty ? Uri.decodeComponent(segs.last) : '';
    }
    t.name = name.isEmpty ? 'file_${t.id}' : name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    client.close(force: true);
    notifyListeners();
  }

  Future<File> _uniqueFile(String name) async {
    var f = File('${dir.path}/$name');
    var n = 1;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    while (await f.exists()) {
      f = File('${dir.path}/$stem ($n)$ext');
      n++;
    }
    return f;
  }
}
