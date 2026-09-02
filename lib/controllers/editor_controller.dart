import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/editor_models.dart';
import '../services/storage/project_storage.dart';

class EditorController extends ChangeNotifier {
  final ProjectStorage storage;
  late ProjectModel project;
  int selectedClip = 0;
  String? selectedElementId;
  Duration playhead = Duration.zero;
  double timelineZoom = 1;
  bool dirty = false;
  final List<String> _undo = <String>[];
  final List<String> _redo = <String>[];

  EditorController({ProjectStorage? storage}) : storage = storage ?? ProjectStorage();

  void initialize(List<File> files) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final clips = files.asMap().entries.map((entry) {
      final file = entry.value;
      final isImage = RegExp(r'\.(jpg|jpeg|png|webp|heic)$', caseSensitive: false).hasMatch(file.path);
      final duration = isImage ? const Duration(seconds: 5) : Duration.zero;
      return EditorClip(
        id: 'clip_${now}_${entry.key}',
        file: file,
        kind: isImage ? MediaKind.image : MediaKind.video,
        sourceDuration: duration,
        start: Duration.zero,
        end: duration,
      );
    }).toList();
    project = ProjectModel(id: 'project_$now', name: 'Untitled Project', clips: clips);
    dirty = true;
  }

  void _snapshot() {
    if (!dirty && _undo.isEmpty) {}
    _undo.add(project.encode());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    dirty = true;
  }

  void selectClip(int index) {
    if (index < 0 || index >= project.clips.length) return;
    selectedClip = index;
    final clipStart = project.clips.take(index).fold(Duration.zero, (a, b) => a + b.duration);
    playhead = clipStart;
    notifyListeners();
  }

  void setPlayhead(Duration value) {
    final total = project.duration;
    playhead = value < Duration.zero ? Duration.zero : (value > total ? total : value);
    notifyListeners();
  }

  Duration clipStart(int index) => project.clips.take(index).fold(Duration.zero, (a, b) => a + b.duration);

  int clipAt(Duration position) {
    var cursor = Duration.zero;
    for (var i = 0; i < project.clips.length; i++) {
      cursor += project.clips[i].duration;
      if (position <= cursor) return i;
    }
    return project.clips.isEmpty ? -1 : project.clips.length - 1;
  }

  void updateClipDuration(int index, Duration duration) {
    if (index < 0 || index >= project.clips.length || duration <= Duration.zero) return;
    final old = project.clips[index];
    project.clips[index] = old.copyWith(start: Duration.zero, end: duration);
    dirty = true;
    notifyListeners();
  }

  void trimSelected(Duration start, Duration end) {
    if (selectedClip < 0 || selectedClip >= project.clips.length) return;
    final clip = project.clips[selectedClip];
    if (end <= start || start < Duration.zero || end > clip.sourceDuration) return;
    _snapshot();
    project.clips[selectedClip] = clip.copyWith(start: start, end: end);
    notifyListeners();
  }

  void splitAtPlayhead() {
    if (selectedClip < 0 || selectedClip >= project.clips.length) return;
    final clip = project.clips[selectedClip];
    final localMs = playhead.inMilliseconds - clipStart(selectedClip).inMilliseconds;
    final splitSourceMs = clip.start.inMilliseconds + (localMs / clip.speed).round();
    if (splitSourceMs <= clip.start.inMilliseconds || splitSourceMs >= clip.end.inMilliseconds) return;
    _snapshot();
    final left = clip.copyWith(end: Duration(milliseconds: splitSourceMs));
    final right = EditorClip(
      id: '${clip.id}_split_${DateTime.now().millisecondsSinceEpoch}',
      file: clip.file,
      kind: clip.kind,
      sourceDuration: clip.sourceDuration,
      start: Duration(milliseconds: splitSourceMs),
      end: clip.end,
      speed: clip.speed,
      muted: clip.muted,
      volume: clip.volume,
    );
    project.clips
      ..removeAt(selectedClip)
      ..insert(selectedClip, right)
      ..insert(selectedClip, left);
    selectedClip += 1;
    notifyListeners();
  }

  void deleteSelectedClip() {
    if (project.clips.isEmpty || selectedClip < 0 || selectedClip >= project.clips.length) return;
    _snapshot();
    project.clips.removeAt(selectedClip);
    if (project.clips.isNotEmpty) selectedClip = selectedClip.clamp(0, project.clips.length - 1);
    playhead = Duration.zero;
    notifyListeners();
  }

  void addText(String text) {
    if (text.trim().isEmpty) return;
    _snapshot();
    final end = project.duration > Duration.zero ? project.duration : const Duration(seconds: 5);
    final element = EditorElement(
      id: 'text_${DateTime.now().millisecondsSinceEpoch}',
      kind: ElementKind.text,
      text: text.trim(),
      start: playhead,
      end: playhead + const Duration(seconds: 4) < end ? playhead + const Duration(seconds: 4) : end,
      layer: project.elements.length,
    );
    project.elements = [...project.elements, element];
    selectedElementId = element.id;
    notifyListeners();
  }

  void updateSelectedElement({String? text, double? x, double? y, double? scale, double? rotation, double? opacity}) {
    final id = selectedElementId;
    if (id == null) return;
    final index = project.elements.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _snapshot();
    final e = project.elements[index];
    if (text != null) e.text = text;
    if (x != null) e.x = x;
    if (y != null) e.y = y;
    if (scale != null) e.scale = scale;
    if (rotation != null) e.rotation = rotation;
    if (opacity != null) e.opacity = opacity;
    notifyListeners();
  }

  void deleteSelectedElement() {
    final id = selectedElementId;
    if (id == null) return;
    final index = project.elements.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _snapshot();
    project.elements.removeAt(index);
    selectedElementId = null;
    notifyListeners();
  }

  void setFilter(FilterPreset filter, double intensity) {
    _snapshot();
    project.filter = filter;
    project.filterIntensity = intensity.clamp(0, 1);
    notifyListeners();
  }

  void setAdjustment(String key, double value) {
    if (!_undo.isNotEmpty || dirty) _snapshot();
    project.adjustments[key] = value;
    dirty = true;
    notifyListeners();
  }

  void setCanvas(CanvasRatio ratio) {
    _snapshot();
    project.ratio = ratio;
    notifyListeners();
  }

  void setSpeed(double speed) {
    if (selectedClip < 0 || selectedClip >= project.clips.length) return;
    _snapshot();
    project.clips[selectedClip] = project.clips[selectedClip].copyWith(speed: speed.clamp(.25, 4));
    notifyListeners();
  }

  void toggleMuteOriginal() {
    if (selectedClip < 0 || selectedClip >= project.clips.length) return;
    _snapshot();
    final clip = project.clips[selectedClip];
    project.clips[selectedClip] = clip.copyWith(muted: !clip.muted);
    notifyListeners();
  }

  void setVolume(double value) {
    if (selectedClip < 0 || selectedClip >= project.clips.length) return;
    _snapshot();
    project.clips[selectedClip] = project.clips[selectedClip].copyWith(volume: value.clamp(0, 2));
    notifyListeners();
  }

  void addAudio(AudioTrack track) {
    _snapshot();
    project.audioTracks = [...project.audioTracks, track];
    notifyListeners();
  }

  void deleteAudio(String id) {
    _snapshot();
    project.audioTracks.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void addElement(EditorElement element) {
    _snapshot();
    project.elements = [...project.elements, element];
    selectedElementId = element.id;
    notifyListeners();
  }

  void addKeyframe() {
    final id = selectedElementId;
    if (id == null) return;
    final index = project.elements.indexWhere((e) => e.id == id);
    if (index < 0) return;
    _snapshot();
    final e = project.elements[index];
    e.keyframes.add(Keyframe(time: playhead, x: e.x, y: e.y, scale: e.scale, rotation: e.rotation, opacity: e.opacity));
    e.keyframes.sort((a, b) => a.time.compareTo(b.time));
    notifyListeners();
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(project.encode());
    project = ProjectModel.fromJson(jsonDecode(_undo.removeLast()) as Map<String, dynamic>);
    selectedClip = selectedClip.clamp(0, project.clips.isEmpty ? 0 : project.clips.length - 1);
    dirty = true;
    notifyListeners();
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(project.encode());
    project = ProjectModel.fromJson(jsonDecode(_redo.removeLast()) as Map<String, dynamic>);
    selectedClip = selectedClip.clamp(0, project.clips.isEmpty ? 0 : project.clips.length - 1);
    dirty = true;
    notifyListeners();
    return true;
  }

  Future<void> save() async {
    await storage.save(project);
    dirty = false;
    notifyListeners();
  }

  Future<void> duplicate() async => storage.duplicate(project.id);
}
