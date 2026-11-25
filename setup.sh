#!/usr/bin/env bash
# Run once inside this folder, with Flutter installed (flutter doctor should be green).
set -e
cp -r lib /tmp/_lib && cp pubspec.yaml /tmp/_pubspec.yaml
flutter create . --org com.example --project-name offline_dm --platforms android
rm -rf lib && cp -r /tmp/_lib lib && cp /tmp/_pubspec.yaml pubspec.yaml
M=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' $M || sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <application#' $M
flutter pub get
echo "Done. Connect your Vivo (USB debugging on) and run: flutter run   |   or: flutter build apk --release"
