import 'dart:convert';
import 'dart:io';

enum MediaKind { video, image }
enum TrackType { video, audio, text, overlay, vfx, sticker }
enum CanvasRatio { original, r9x16, r16x9, r1x1, r4x3, r4x5 }
enum ElementKind { text, image, video, sticker, vfx }
enum FilterPreset { normal, bright, contrast, warm, cool, vintage, blackWhite, cinematic, dramatic }
enum EffectType { blur, glow, shake, flash, zoom, motion, chromatic, glitch, fade }
enum TransitionType { fade, dissolve, slide, zoom, wipe, blur, push }

String enumName(Object value) => value.toString().split('.').last;

T enumFromName<T>(Iterable<T> values, String name, T fallback) {
  for (final value in values) {
    if (enumName(value as Object) == name) return value;
  }
  return fallback;
}

class Keyframe {
  final Duration time;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;

  const Keyframe({
    required this.time,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });

  Map<String, dynamic> toJson() => {
        'time': time.inMilliseconds,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
      };

  factory Keyframe.fromJson(Map<String, dynamic> json) => Keyframe(
        time: Duration(milliseconds: json['time'] as int? ?? 0),
        x: (json['x'] as num?)?.toDouble() ?? 0.5,
        y: (json['y'] as num?)?.toDouble() ?? 0.5,
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
      );
}

class EditorClip {
  final String id;
  final File file;
  final MediaKind kind;
  Duration sourceDuration;
  Duration start;
  Duration end;
  double speed;
  bool muted;
  double volume;

  EditorClip({
    required this.id,
    required this.file,
    required this.kind,
    required this.sourceDuration,
    Duration? start,
    Duration? end,
    this.speed = 1,
    this.muted = false,
    this.volume = 1,
  })  : start = start ?? Duration.zero,
        end = end ?? sourceDuration;

  Duration get duration => end - start;

  EditorClip copyWith({
    Duration? start,
    Duration? end,
    double? speed,
    bool? muted,
    double? volume,
  }) => EditorClip(
        id: id,
        file: file,
        kind: kind,
        sourceDuration: sourceDuration,
        start: start ?? this.start,
        end: end ?? this.end,
        speed: speed ?? this.speed,
        muted: muted ?? this.muted,
        volume: volume ?? this.volume,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': file.path,
        'kind': enumName(kind),
        'sourceDuration': sourceDuration.inMilliseconds,
        'start': start.inMilliseconds,
        'end': end.inMilliseconds,
        'speed': speed,
        'muted': muted,
        'volume': volume,
      };

  factory EditorClip.fromJson(Map<String, dynamic> json) {
    final duration = Duration(milliseconds: json['sourceDuration'] as int? ?? 0);
    return EditorClip(
      id: json['id'] as String,
      file: File(json['path'] as String),
      kind: enumFromName(MediaKind.values, json['kind'] as String? ?? 'video', MediaKind.video),
      sourceDuration: duration,
      start: Duration(milliseconds: json['start'] as int? ?? 0),
      end: Duration(milliseconds: json['end'] as int? ?? duration.inMilliseconds),
      speed: (json['speed'] as num?)?.toDouble() ?? 1,
      muted: json['muted'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
    );
  }
}

class EditorElement {
  final String id;
  final ElementKind kind;
  String text;
  String? assetPath;
  Duration start;
  Duration end;
  double x;
  double y;
  double scale;
  double rotation;
  double opacity;
  int layer;
  double intensity;
  String color;
  String fontFamily;
  double fontSize;
  bool bold;
  bool italic;
  bool outline;
  bool shadow;
  List<Keyframe> keyframes;

  EditorElement({
    required this.id,
    required this.kind,
    this.text = '',
    this.assetPath,
    this.start = Duration.zero,
    this.end = const Duration(seconds: 10),
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.layer = 0,
    this.intensity = 0.5,
    this.color = '#FFFFFF',
    this.fontFamily = 'sans',
    this.fontSize = 32,
    this.bold = false,
    this.italic = false,
    this.outline = false,
    this.shadow = false,
    List<Keyframe>? keyframes,
  }) : keyframes = keyframes ?? <Keyframe>[];

  EditorElement copy() => EditorElement(
        id: id,
        kind: kind,
        text: text,
        assetPath: assetPath,
        start: start,
        end: end,
        x: x,
        y: y,
        scale: scale,
        rotation: rotation,
        opacity: opacity,
        layer: layer,
        intensity: intensity,
        color: color,
        fontFamily: fontFamily,
        fontSize: fontSize,
        bold: bold,
        italic: italic,
        outline: outline,
        shadow: shadow,
        keyframes: List<Keyframe>.from(keyframes),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': enumName(kind),
        'text': text,
        'assetPath': assetPath,
        'start': start.inMilliseconds,
        'end': end.inMilliseconds,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
        'layer': layer,
        'intensity': intensity,
        'color': color,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'outline': outline,
        'shadow': shadow,
        'keyframes': keyframes.map((e) => e.toJson()).toList(),
      };

  factory EditorElement.fromJson(Map<String, dynamic> json) => EditorElement(
        id: json['id'] as String,
        kind: enumFromName(ElementKind.values, json['kind'] as String? ?? 'text', ElementKind.text),
        text: json['text'] as String? ?? '',
        assetPath: json['assetPath'] as String?,
        start: Duration(milliseconds: json['start'] as int? ?? 0),
        end: Duration(milliseconds: json['end'] as int? ?? 10000),
        x: (json['x'] as num?)?.toDouble() ?? .5,
        y: (json['y'] as num?)?.toDouble() ?? .5,
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
        layer: json['layer'] as int? ?? 0,
        intensity: (json['intensity'] as num?)?.toDouble() ?? .5,
        color: json['color'] as String? ?? '#FFFFFF',
        fontFamily: json['fontFamily'] as String? ?? 'sans',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 32,
        bold: json['bold'] as bool? ?? false,
        italic: json['italic'] as bool? ?? false,
        outline: json['outline'] as bool? ?? false,
        shadow: json['shadow'] as bool? ?? false,
        keyframes: (json['keyframes'] as List<dynamic>? ?? const [])
            .map((e) => Keyframe.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class AudioTrack {
  final String id;
  final File file;
  Duration start;
  Duration end;
  Duration position;
  double volume;
  bool muted;
  Duration fadeIn;
  Duration fadeOut;

  AudioTrack({
    required this.id,
    required this.file,
    required this.start,
    required this.end,
    this.position = Duration.zero,
    this.volume = 1,
    this.muted = false,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': file.path,
        'start': start.inMilliseconds,
        'end': end.inMilliseconds,
        'position': position.inMilliseconds,
        'volume': volume,
        'muted': muted,
        'fadeIn': fadeIn.inMilliseconds,
        'fadeOut': fadeOut.inMilliseconds,
      };

  factory AudioTrack.fromJson(Map<String, dynamic> json) => AudioTrack(
        id: json['id'] as String,
        file: File(json['path'] as String),
        start: Duration(milliseconds: json['start'] as int? ?? 0),
        end: Duration(milliseconds: json['end'] as int? ?? 0),
        position: Duration(milliseconds: json['position'] as int? ?? 0),
        volume: (json['volume'] as num?)?.toDouble() ?? 1,
        muted: json['muted'] as bool? ?? false,
        fadeIn: Duration(milliseconds: json['fadeIn'] as int? ?? 0),
        fadeOut: Duration(milliseconds: json['fadeOut'] as int? ?? 0),
      );
}

class ProjectModel {
  String id;
  String name;
  CanvasRatio ratio;
  List<EditorClip> clips;
  List<AudioTrack> audioTracks;
  List<EditorElement> elements;
  FilterPreset filter;
  double filterIntensity;
  Map<String, double> adjustments;
  String? backgroundColor;
  DateTime updatedAt;

  ProjectModel({
    required this.id,
    required this.name,
    required this.clips,
    this.audioTracks = const [],
    this.elements = const [],
    this.ratio = CanvasRatio.original,
    this.filter = FilterPreset.normal,
    this.filterIntensity = 1,
    Map<String, double>? adjustments,
    this.backgroundColor,
    DateTime? updatedAt,
  })  : adjustments = adjustments ?? <String, double>{},
        updatedAt = updatedAt ?? DateTime.now();

  Duration get duration => clips.fold(Duration.zero, (sum, clip) => sum + clip.duration);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ratio': enumName(ratio),
        'clips': clips.map((e) => e.toJson()).toList(),
        'audioTracks': audioTracks.map((e) => e.toJson()).toList(),
        'elements': elements.map((e) => e.toJson()).toList(),
        'filter': enumName(filter),
        'filterIntensity': filterIntensity,
        'adjustments': adjustments,
        'backgroundColor': backgroundColor,
        'updatedAt': updatedAt.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  factory ProjectModel.fromJson(Map<String, dynamic> json) => ProjectModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'VideoMitra Project',
        ratio: enumFromName(CanvasRatio.values, json['ratio'] as String? ?? 'original', CanvasRatio.original),
        clips: (json['clips'] as List<dynamic>? ?? const [])
            .map((e) => EditorClip.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        audioTracks: (json['audioTracks'] as List<dynamic>? ?? const [])
            .map((e) => AudioTrack.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        elements: (json['elements'] as List<dynamic>? ?? const [])
            .map((e) => EditorElement.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        filter: enumFromName(FilterPreset.values, json['filter'] as String? ?? 'normal', FilterPreset.normal),
        filterIntensity: (json['filterIntensity'] as num?)?.toDouble() ?? 1,
        adjustments: Map<String, double>.from(json['adjustments'] as Map? ?? const {}),
        backgroundColor: json['backgroundColor'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
