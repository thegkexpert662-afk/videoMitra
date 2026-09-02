# VideoMitra

VideoMitra is a Flutter + Android video editor with its own UI and editing state architecture.

## Current implementation

- Multiple video/image import
- Responsive dark editor UI
- Video playback, seek and clip selection
- Timeline with video/audio/text/overlay/VFX tracks
- Trim and split without re-rendering the project state
- Delete + undo/redo
- Canvas ratios: Original, 9:16, 16:9, 1:1, 4:3, 4:5
- Audio import, original-audio mute and export mixing
- Text layers with timed FFmpeg drawtext rendering
- Filters and manual adjustments rendered by FFmpeg
- Timed blur/glow/flash/zoom/shake/chromatic/glitch/fade effects
- Basic green chroma-key export effect
- Image overlays and emoji stickers
- Speed presets
- Keyframe data model and keyframe insertion
- Draft autosave, project duplication and deletion
- Android share sheet after export
- 480p/720p/1080p/2K/4K export selection and 24/25/30/60 FPS
- Automated Flutter analyze/test/Android build workflow

## Architecture

```text
lib/
├── controllers/
├── models/
├── screens/
│   ├── editor/
│   ├── home/
│   ├── projects/
│   ├── settings/
│   └── splash/
├── services/
│   ├── audio/
│   ├── export/
│   ├── storage/
│   └── video/
└── utils/
```

The project keeps editing state in Dart models and only renders the final output with FFmpeg. This avoids re-encoding the source video for every timeline operation.

## Android platform

The repository currently keeps the Flutter/Dart source as the source of truth. The CI workflow regenerates Android platform files when `android/` is absent, then runs `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --release`.

For a local Android checkout, from the project root run:

```bash
flutter create --platforms=android --org com.videomitra .
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Open the project root in Android Studio after the Android platform files are generated.

## Important development rule

VideoMitra should not be treated as a UI-only demo. Editing operations are stored in the project state and export processing is handled by FFmpeg so that supported effects are present in the exported video. Advanced features should be enabled only after they are validated on a real Android device.
