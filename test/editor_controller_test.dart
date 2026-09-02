import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:videomitra/controllers/editor_controller.dart';
import 'package:videomitra/models/editor_models.dart';

void main() {
  test('editor supports split and undo', () {
    final controller = EditorController();
    controller.initialize([File('/tmp/sample.mp4')]);
    controller.project.clips[0].sourceDuration = const Duration(seconds: 10);
    controller.project.clips[0].end = const Duration(seconds: 10);
    controller.setPlayhead(const Duration(seconds: 5));
    controller.splitAtPlayhead();
    expect(controller.project.clips.length, 2);
    expect(controller.undo(), isTrue);
    expect(controller.project.clips.length, 1);
  });

  test('canvas and filter are stored in project state', () {
    final controller = EditorController();
    controller.initialize([File('/tmp/sample.mp4')]);
    controller.setCanvas(CanvasRatio.r9x16);
    controller.setFilter(FilterPreset.cinematic, .8);
    expect(controller.project.ratio, CanvasRatio.r9x16);
    expect(controller.project.filter, FilterPreset.cinematic);
    expect(controller.project.filterIntensity, .8);
  });
}
