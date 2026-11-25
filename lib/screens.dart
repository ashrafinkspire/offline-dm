import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'download_manager.dart';

final dm = DownloadManager.instance;

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

String category(String path) {
  final e = path.split('.').last.toLowerCase();
  if (['mp4', 'mkv', 'webm', 'mov', 'avi', '3gp'].contains(e)) return 'Videos';
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(e)) return 'Photos';
  if (['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt', 'pptx', 'epub'].contains(e)) return 'Documents';
  return 'Others';
}

class RootTabs extends StatelessWidget {
  const RootTabs({super.key});
  @override
  Widget build(BuildContext context) => CupertinoTabScaffold(
        tabBar: CupertinoTabBar(items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.arrow_down_circle_fill), label: 'Downloads'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.folder_fill), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.settings), label: 'Settings'),
        ]),
        tabBuilder: (c, i) => CupertinoTabView(
          builder: (_) => [const DownloadsPage(), const LibraryPage(), const SettingsPage()][i],
        ),
      );
}

// ---------------- Downloads ----------------
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  void _add(BuildContext context) {
    final ctrl = TextEditingController();
    String? err;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => CupertinoAlertDialog(
          title: const Text('Add download'),
          content: Column(children: [
            const SizedBox(height: 8),
            CupertinoTextField(controller: ctrl, placeholder: 'https://example.com/file.mp4', autofocus: true, maxLines: 2),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err!, style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 13))),
          ]),
          actions: [
            CupertinoDialogAction(
              child: const Text('Paste'),
              onPressed: () async {
                final d = await Clipboard.getData('text/plain');
                if (d?.text != null) ctrl.text = d!.text!;
              },
            ),
            CupertinoDialogAction(isDestructiveAction: true, child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Download'),
              onPressed: () {
                final e = dm.add(ctrl.text);
                if (e == null) {
                  Navigator.pop(ctx);
                } else {
                  setS(() => err = e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Downloads'),
          trailing: CupertinoButton(padding: EdgeInsets.zero, child: const Icon(CupertinoIcons.add), onPressed: () => _add(context)),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: dm,
            builder: (_, __) => dm.tasks.isEmpty
                ? const Center(child: Text('No downloads yet.\nTap + and paste a direct file link.', textAlign: TextAlign.center, style: TextStyle(color: CupertinoColors.systemGrey)))
                : ListView.separated(
                    itemCount: dm.tasks.length,
                    separatorBuilder: (_, __) => Container(height: 0.5, color: CupertinoColors.separator),
                    itemBuilder: (_, i) => TaskTile(task: dm.tasks[i]),
                  ),
          ),
        ),
      );
}

class TaskTile extends StatelessWidget {
  final DownloadTask task;
  const TaskTile({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final sub = switch (t.status) {
      Status.queued => 'Queued',
      Status.downloading => '${fmtBytes(t.received)} of ${t.total > 0 ? fmtBytes(t.total) : '?'} · ${fmtBytes(t.speed)}/s',
      Status.paused => 'Paused · ${fmtBytes(t.received)}',
      Status.done => 'Completed · ${fmtBytes(t.total > 0 ? t.total : t.received)}',
      Status.failed => 'Failed: ${t.error ?? ''}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name.isEmpty ? t.url : t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (t.status != Status.done)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 5,
                  color: CupertinoColors.systemFill,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: t.progress, child: Container(color: CupertinoColors.activeBlue)),
                ),
              ),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 12.5, color: t.status == Status.failed ? CupertinoColors.systemRed : CupertinoColors.systemGrey)),
          ]),
        ),
        if (t.status == Status.downloading)
          CupertinoButton(padding: const EdgeInsets.all(8), child: const Icon(CupertinoIcons.pause_circle, size: 28), onPressed: () => dm.pause(t)),
        if (t.status == Status.paused || t.status == Status.failed)
          CupertinoButton(padding: const EdgeInsets.all(8), child: const Icon(CupertinoIcons.play_circle, size: 28), onPressed: () => dm.resume(t)),
        CupertinoButton(padding: const EdgeInsets.all(8), child: const Icon(CupertinoIcons.trash, size: 22, color: CupertinoColors.systemRed), onPressed: () => dm.remove(t)),
      ]),
    );
  }
}

// ---------------- Library ----------------
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const cats = ['Videos', 'Photos', 'Documents', 'Others'];
  int sel = 0;
  List<File> files = [];

  @override
  void initState() {
    super.initState();
    dm.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dm.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final all = dm.dir.listSync().whereType<File>().where((f) => !f.uri.pathSegments.last.startsWith('.')).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (mounted) setState(() => files = all.where((f) => category(f.path) == cats[sel]).toList());
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Library')),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: sel,
                children: {for (var i = 0; i < cats.length; i++) i: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(cats[i], style: const TextStyle(fontSize: 13)))},
                onValueChanged: (v) {
                  sel = v ?? 0;
                  _load();
                },
              ),
            ),
            Expanded(
              child: files.isEmpty
                  ? const Center(child: Text('Nothing here yet', style: TextStyle(color: CupertinoColors.systemGrey)))
                  : ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (_, i) {
                        final f = files[i];
                        final name = f.uri.pathSegments.last;
                        return CupertinoListTile(
                          leading: Icon(sel == 0 ? CupertinoIcons.play_rectangle_fill : sel == 1 ? CupertinoIcons.photo_fill : CupertinoIcons.doc_fill, color: CupertinoColors.activeBlue),
                          title: Text(Uri.decodeComponent(name), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(fmtBytes(f.lengthSync())),
                          trailing: const CupertinoListTileChevron(),
                          onTap: () {
                            if (sel == 0 || sel == 1) {
                              Navigator.of(context, rootNavigator: true).push(CupertinoPageRoute(builder: (_) => ViewerPage(file: f, video: sel == 0)));
                            }
                          },
                        );
                      },
                    ),
            ),
          ]),
        ),
      );
}

class ViewerPage extends StatefulWidget {
  final File file;
  final bool video;
  const ViewerPage({super.key, required this.file, required this.video});
  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  VideoPlayerController? c;

  @override
  void initState() {
    super.initState();
    if (widget.video) {
      c = VideoPlayerController.file(widget.file)
        ..initialize().then((_) {
          setState(() {});
          c!.play();
        });
    }
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        navigationBar: const CupertinoNavigationBar(backgroundColor: Color(0xCC000000)),
        child: Center(
          child: widget.video
              ? (c != null && c!.value.isInitialized
                  ? GestureDetector(
                      onTap: () => setState(() => c!.value.isPlaying ? c!.pause() : c!.play()),
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        AspectRatio(aspectRatio: c!.value.aspectRatio, child: VideoPlayer(c!)),
                        VideoProgressIndicator(c!, allowScrubbing: true),
                      ]),
                    )
                  : const CupertinoActivityIndicator())
              : InteractiveViewer(child: Image.file(widget.file)),
        ),
      );
}

// ---------------- Settings ----------------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: dm,
            builder: (_, __) => ListView(children: [
              CupertinoListSection.insetGrouped(children: [
                CupertinoListTile(
                  title: const Text('Wi-Fi only'),
                  trailing: CupertinoSwitch(value: dm.wifiOnly, onChanged: (v) => dm.setSettings(wifi: v)),
                ),
                CupertinoListTile(
                  title: const Text('Simultaneous downloads'),
                  trailing: _Stepper(value: dm.maxConcurrent, min: 1, max: 5, onChanged: (v) => dm.setSettings(max: v)),
                ),
                CupertinoListTile(
                  title: const Text('Connections per file'),
                  trailing: _Stepper(value: dm.parts, min: 1, max: 8, onChanged: (v) => dm.setSettings(p: v)),
                ),
              ]),
              CupertinoListSection.insetGrouped(header: const Text('Download folder'), children: [
                CupertinoListTile(title: Text(dm.dir.path, style: const TextStyle(fontSize: 12))),
              ]),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('Only download files you own or have permission to save.', style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
              ),
            ]),
          ),
        ),
      );
}

class _Stepper extends StatelessWidget {
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        CupertinoButton(padding: EdgeInsets.zero, minSize: 30, child: const Icon(CupertinoIcons.minus_circle), onPressed: value > min ? () => onChanged(value - 1) : null),
        Text('$value', style: const TextStyle(fontSize: 17)),
        CupertinoButton(padding: EdgeInsets.zero, minSize: 30, child: const Icon(CupertinoIcons.plus_circle), onPressed: value < max ? () => onChanged(value + 1) : null),
      ]);
}
