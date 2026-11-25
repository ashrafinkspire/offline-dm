# Offline DM (iPhone-style download manager for Android)

1. Install Flutter + Android Studio: https://docs.flutter.dev/get-started/install/windows/mobile
2. Open a terminal in this folder and run: ./setup.sh   (Windows: run the commands inside setup.sh by hand, or use Git Bash)
3. Phone: Settings > About phone > tap Build number 7 times > Developer options > USB debugging ON.
4. `flutter run` installs it on your Vivo. For a shareable file: `flutter build apk --release`
   -> build/app/outputs/flutter-apk/app-release.apk

Features: direct-link downloads, multi-connection (up to 8), pause/resume, queue, Wi-Fi-only,
offline library (Videos/Photos/Documents/Others) with built-in video and photo viewer.
Files are saved in the app's own Downloads folder (Settings tab shows the path).
Not included yet: background service/notifications when the app is closed.
