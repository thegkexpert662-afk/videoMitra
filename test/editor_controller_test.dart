import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:videomitra/controllers/editor_controller.dart';
import 'package:videomitra/models/editor_models.dart';

void main() {
  EditorController controllerWithProject() {
    final c = EditorController();
    c.initialize([File('/tmp/a.mp4'), File('/tmp/b.mp4')]);
    c.project.clips[0].sourceDuration = const Duration(seconds: 10);
    c.project.clips[0].start = Duration.zero;
    c.project.clips[0].end = const Duration(seconds: 10);
    c.project.clips[1].sourceDuration = const Duration(seconds: 8);
    c.project.clips[1].start = Duration.zero;
    c.project.clips[1].end = const Duration(seconds: 8);
    return c;
  }

  test('split creates independent clips and undo restores state', () {
    final c = controllerWithProject();
    c.selectClip(0);
    c.setPlayhead(const Duration(seconds: 4));
    c.splitAtPlayhead();
    expect(c.project.clips.length, 3);
    expect(c.project.clips[0].duration, const Duration(seconds: 4));
    expect(c.project.clips[1].duration, const Duration(seconds: 6));
    expect(c.project.clips[0].id, isNot(c.project.clips[1].id));
    expect(c.undo(), isTrue);
    expect(c.project.clips.length, 2);
  });

  test('canvas filter and transition are stored', () {
    final c = controllerWithProject();
    c.setCanvas(CanvasRatio.r9x16);
    c.setFilter(FilterPreset.cinematic, .8);
    c.setTransition(0, TransitionType.zoom, const Duration(milliseconds: 500));
    expect(c.project.ratio, CanvasRatio.r9x16);
    expect(c.project.filter, FilterPreset.cinematic);
    expect(c.project.filterIntensity, .8);
    expect(c.project.clips[0].transitionAfter, TransitionType.zoom);
    expect(c.project.clips[0].transitionDuration, const Duration(milliseconds: 500));
  });

  test('keyframes interpolate position and scale', () {
    final c = controllerWithProject();
    c.addText('Hello');
    c.addKeyframe();
    c.setPlayhead(const Duration(seconds: 2));
    c.updateSelectedElement(x: .8, y: .7, scale: 2);
    c.addKeyframe();
    final element = c.project.elements.single;
    final middle = c.interpolatedKeyframe(element, const Duration(seconds: 1));
    expect(middle, isNotNull);
    expect(middle!.x, closeTo(.65, .001));
    expect(middle.scale, closeTo(1.5, .001));
  });
}
