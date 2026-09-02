import 'dart:io';
import '../../models/editor_models.dart';
import '../video/video_processor.dart';

typedef ExportProgressCallback = void Function(double progress);

class ExportOptions {
  final int resolution; final int fps; final String quality;
  const ExportOptions({this.resolution=1080,this.fps=30,this.quality='High'});
  int get width=>resolution==480?854:resolution==720?1280:resolution==1080?1920:resolution==1440?2560:3840;
  int get height=>resolution==480?480:resolution==720?720:resolution==1080?1080:resolution==1440?1440:2160;
  int get crf=>quality=='Low'?28:quality=='Medium'?24:quality=='High'?20:18;
}

class ExportService {
  final VideoProcessor processor;
  ExportService({VideoProcessor? processor}):processor=processor??VideoProcessor();
  Future<File> export(ProjectModel project,ExportOptions options,{ExportProgressCallback? onProgress}) async {
    var w=options.width,h=options.height;
    switch(project.ratio){case CanvasRatio.r9x16:final x=w;w=h;h=x;break;case CanvasRatio.r1x1:w=h=options.resolution==480?480:options.resolution==720?720:options.resolution==1080?1080:options.resolution==1440?1440:2160;break;case CanvasRatio.r4x3:h=(w*3/4).round();break;case CanvasRatio.r4x5:h=(w*5/4).round();break;case CanvasRatio.r16x9:case CanvasRatio.original:break;}
    final result=await processor.render(project:project,width:w,height:h,fps:options.fps,onProgress:onProgress);
    if(!result.success||result.file==null)throw Exception(result.error??'Export failed');
    return result.file!;
  }
}
