import 'dart:io';
import '../../models/editor_models.dart';
import '../video/video_processor.dart';

class ExportOptions {
  final int resolution;
  final int fps;
  final String quality;
  const ExportOptions({this.resolution = 1080, this.fps = 30, this.quality = 'High'});

  int get width {
    switch (resolution) {
      case 480: return 854;
      case 720: return 1280;
      case 1080: return 1920;
      case 1440: return 2560;
      case 2160: return 3840;
      default: return 1920;
    }
  }

  int get height => width == 854 ? 480 : width == 1280 ? 720 : width == 1920 ? 1080 : width == 2560 ? 1440 : 2160;
}

class ExportService {
  final VideoProcessor processor;
  ExportService({VideoProcessor? processor}) : processor = processor ?? VideoProcessor();

  Future<File> export(ProjectModel project, ExportOptions options) async {
    var width = options.width;
    var height = options.height;
    switch (project.ratio) {
      case CanvasRatio.r9x16:
        final temp = width; width = height; height = temp; break;
      case CanvasRatio.r1x1:
        width = height = options.resolution == 480 ? 480 : options.resolution == 720 ? 720 : options.resolution == 1080 ? 1080 : options.resolution == 1440 ? 1440 : 2160;
        break;
      case CanvasRatio.r4x3:
        height = (width * 3 / 4).round(); break;
      case CanvasRatio.r4x5:
        height = (width * 5 / 4).round(); break;
      case CanvasRatio.r16x9:
      case CanvasRatio.original:
        break;
    }
    final result = await processor.render(project: project, width: width, height: height, fps: options.fps);
    if (!result.success || result.file == null) throw Exception(result.error ?? 'Export failed');
    return result.file!;
  }
}
