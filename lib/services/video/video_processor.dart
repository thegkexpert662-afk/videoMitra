import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/editor_models.dart';

class VideoProcessResult { final bool success; final File? file; final String? error; const VideoProcessResult(this.success,{this.file,this.error}); }
typedef ExportProgress = void Function(double progress);

class VideoProcessor {
  Future<VideoProcessResult> trim(EditorClip clip) async {
    if (!await clip.file.exists()) return const VideoProcessResult(false,error:'Source file not found');
    if (clip.kind != MediaKind.video) return const VideoProcessResult(false,error:'Only video clips can be trimmed');
    final out=File('${(await getTemporaryDirectory()).path}/vm_trim_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final start=clip.start.inMilliseconds/1000.0,duration=clip.duration.inMilliseconds/1000.0;
    if(duration<=0)return const VideoProcessResult(false,error:'Invalid trim range');
    final s=await FFmpegKit.execute('-y -ss $start -i ${_q(clip.file.path)} -t $duration -map 0 -c copy -avoid_negative_ts make_zero ${_q(out.path)}');
    return ReturnCode.isSuccess(await s.getReturnCode())&&await out.exists()?VideoProcessResult(true,file:out):const VideoProcessResult(false,error:'Video processing failed');
  }

  Future<VideoProcessResult> render({required ProjectModel project,required int width,required int height,required int fps,ExportProgress? onProgress}) async {
    if(project.clips.isEmpty)return const VideoProcessResult(false,error:'No clips in project');
    final out=File('${(await getTemporaryDirectory()).path}/vm_export_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final args=<String>['-y']; final filters=<String>[]; final baseLabels=<String>[]; var inputIndex=0;
    final clipDurations=<double>[];

    for(var i=0;i<project.clips.length;i++){
      final c=project.clips[i];
      if(c.kind==MediaKind.image){args.addAll(['-loop','1','-t','${c.duration.inMilliseconds/1000.0}','-i',_q(c.file.path)]);}else{args.addAll(['-i',_q(c.file.path)]);}
      final src='[$inputIndex:v]'; var chain='$src';
      chain+=',trim=start=${c.start.inMilliseconds/1000.0}:end=${c.end.inMilliseconds/1000.0},setpts=PTS-STARTPTS';
      if(c.speed!=1)chain+=',setpts=${1/c.speed}*PTS';
      final t=c.transform;
      if(t.left>0||t.top>0||t.right<1||t.bottom<1)chain+=',crop=w=iw*${(t.right-t.left).clamp(.05,1)}:h=ih*${(t.bottom-t.top).clamp(.05,1)}:x=iw*${t.left.clamp(0,.95)}:y=ih*${t.top.clamp(0,.95)}';
      if(t.zoom!=1)chain+=',scale=iw*${t.zoom.clamp(.1,6)}:ih*${t.zoom.clamp(.1,6)}';
      if(t.rotation!=0)chain+=',rotate=${t.rotation}:fillcolor=black';
      chain+=',scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2+(iw-ow)/2*${t.panX.clamp(-1,1)}:(oh-ih)/2+(ih-oh)/2*${t.panY.clamp(-1,1)}:color=black,fps=$fps,setsar=1';
      chain+=_videoFilter(project);
      chain+=_clipEffects(project,project.clips.take(i).fold(Duration.zero,(s,x)=>s+x.duration),c.duration,width,height);
      chain+='[raw$i]'; filters.add(chain); baseLabels.add('[raw$i]'); clipDurations.add(c.duration.inMilliseconds/1000.0); inputIndex++;
    }

    // Optional green-screen background is an actual video/image layer behind keyed clips.
    int? bgIndex;
    if(project.chromaBackgroundPath!=null && project.chromaBackgroundPath!.isNotEmpty){
      bgIndex=inputIndex; final p=project.chromaBackgroundPath!; final image=RegExp(r'\.(png|jpe?g|webp)$',caseSensitive:false).hasMatch(p); if(image)args.addAll(['-loop','1','-i',_q(p)]);else args.addAll(['-stream_loop','-1','-i',_q(p)]); inputIndex++;
      filters.add('[$bgIndex:v]scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black,fps=$fps,setsar=1[vmBg]');
    }

    // Per-clip chroma key over the selected background.
    if(bgIndex!=null){
      for(var i=0;i<project.clips.length;i++){
        final c=project.clips[i]; if(c.chromaSimilarity==null)continue;
        final sim=(c.chromaSimilarity??.4).clamp(.01,1),blend=(c.chromaBlend??.08).clamp(0,1),color=c.chromaColor??'#00ff00';
        final hex=color.replaceAll('#',''); final keyed='[key$i]';
        filters.add('[raw$i]chromakey=0x$hex:$sim:$blend$keyed');
        filters.add('[vmBg]$keyed overlay=0:0:shortest=1[chroma$i]');
        baseLabels[i]='[chroma$i]';
      }
    }

    // Cross-fade transitions. xfade supports fade/dissolve/slide/wipe/zoom and many more native transitions.
    String current=baseLabels.first; double currentDuration=clipDurations.first;
    for(var i=1;i<baseLabels.length;i++){
      final c=project.clips[i-1]; var d=c.transitionDuration.inMilliseconds/1000.0; d=d.clamp(.05,clipDurations[i-1].clamp(.05,9999)); d=d.clamp(.05,clipDurations[i].clamp(.05,9999));
      final offset=(currentDuration-d).clamp(0,999999); final next='[xf$i]';
      filters.add('$current${baseLabels[i]}xfade=transition=${_transition(c.transitionAfter)}:duration=$d:offset=$offset$next');
      current=next; currentDuration=currentDuration+clipDurations[i]-d;
    }

    // Advanced text is rendered into the export, including fill, box, outline, shadow and animation.
    for(final e in project.elements.where((e)=>e.kind==ElementKind.text)){
      final k=e.keyframes.isEmpty?null:e.keyframes.last;
      final x=((k?.x??e.x).clamp(0,1)*width).round(), y=((k?.y??e.y).clamp(0,1)*height).round();
      final size=((k?.scale??e.scale)*e.fontSize).round().clamp(8,300);
      final start=e.start.inMilliseconds/1000.0,end=e.end.inMilliseconds/1000.0;
      final safe=_escapeText(e.text); final font=e.bold?'/system/fonts/Roboto-Bold.ttf':'/system/fonts/Roboto-Regular.ttf';
      final anim=_textEnable(e.animation,start,end);
      final box=e.backgroundColor=='#00000000'?'':':box=1:boxcolor=${e.backgroundColor}';
      final outline=e.outline?':borderw=${e.outlineWidth.clamp(1,12)}:bordercolor=${e.outlineColor}':'';
      final shadow=e.shadow?':shadowx=2:shadowy=2:shadowcolor=black@0.7':'';
      final next='[txt_${e.id}]'; filters.add('$current,drawtext=fontfile=$font:text=\'$safe\':x=$x:y=$y:fontsize=$size:fontcolor=${e.color}$box$outline$shadow:enable=\'$anim\'$next'); current=next;
    }

    // Image/video overlays are true FFmpeg inputs, not just preview widgets.
    for(var n=0;n<project.elements.length;n++){
      final e=project.elements[n]; if((e.kind!=ElementKind.image&&e.kind!=ElementKind.video)||e.assetPath==null)continue;
      final p=e.assetPath!; final image=RegExp(r'\.(png|jpe?g|webp|heic)$',caseSensitive:false).hasMatch(p);
      if(image)args.addAll(['-loop','1','-i',_q(p)]);else args.addAll(['-i',_q(p)]);
      final idx=inputIndex++; final start=e.start.inMilliseconds/1000.0,end=e.end.inMilliseconds/1000.0;
      final w=(width*.45*e.scale.clamp(.05,3)).round(),h=(height*.45*e.scale.clamp(.05,3)).round(); final x=(e.x.clamp(0,1)*width-w/2).round(),y=(e.y.clamp(0,1)*height-h/2).round();
      final next='[ov$n]'; filters.add('[$idx:v]setpts=PTS-STARTPTS,scale=$w:$h:force_original_aspect_ratio=decrease,format=rgba,colorchannelmixer=aa=${e.opacity.clamp(0,1)}$nextIn');
      filters.add('$current$nextIn overlay=x=$x:y=$y:enable=\'between(t,$start,$end)\'$next'); current=next;
    }

    filters.add('$current,format=yuv420p[vout]');
    args.addAll(['-filter_complex',filters.join(';'),'-map','[vout]']);

    // Original audio is preserved for a single clip; imported tracks are mixed for projects with music/audio.
    if(project.audioTracks.isEmpty&&project.clips.length==1&&!project.clips.first.muted)args.addAll(['-map','0:a?']);
    if(project.audioTracks.isNotEmpty){
      final labels=<String>[];
      for(final a in project.audioTracks){args.addAll(['-i',_q(a.file.path)]); final idx=inputIndex++; final l='[aud${labels.length}]'; var af='[$idx:a]atrim=start=${a.start.inMilliseconds/1000.0}:end=${a.end.inMilliseconds/1000.0},asetpts=PTS-STARTPTS,adelay=${a.position.inMilliseconds}|${a.position.inMilliseconds},volume=${a.muted?0:a.volume}'; if(a.fadeIn>Duration.zero)af+=',afade=t=in:st=0:d=${a.fadeIn.inMilliseconds/1000.0}'; if(a.fadeOut>Duration.zero)af+=',afade=t=out:st=${((a.end-a.start).inMilliseconds/1000.0-a.fadeOut.inMilliseconds/1000.0).clamp(0,99999)}:d=${a.fadeOut.inMilliseconds/1000.0}'; filters.add('$af$l'); labels.add(l); }
      if(labels.isNotEmpty){filters.add('${labels.join('')}amix=inputs=${labels.length}:duration=longest:dropout_transition=0[aout]'); args[args.indexOf('-filter_complex')+1]=filters.join(';'); args.addAll(['-map','[aout]']);}
    }
    args.addAll(['-c:v','mpeg4','-q:v','3','-pix_fmt','yuv420p','-movflags','+faststart','-c:a','aac','-b:a','192k',_q(out.path)]);

    onProgress?.call(0);
    final session=await FFmpegKit.executeWithArgumentsAsync(args.sublist(1),(s) async { },null,(stats){
      final time=stats.getTime(); final total=(project.duration.inMilliseconds).clamp(1,1<<31); onProgress?.call((time/total).clamp(0,1).toDouble());
    });
    final code=await session.getReturnCode(); onProgress?.call(1);
    return ReturnCode.isSuccess(code)&&await out.exists()?VideoProcessResult(true,file:out):const VideoProcessResult(false,error:'Export failed. Check storage, media format, or lower resolution.');
  }

  String _transition(TransitionType t){switch(t){case TransitionType.fade:return 'fade';case TransitionType.dissolve:return 'dissolve';case TransitionType.slide:return 'slideleft';case TransitionType.zoom:return 'zoomin';case TransitionType.wipe:return 'wipeleft';case TransitionType.blur:return 'hblur';case TransitionType.push:return 'slideright';}}
  String _textEnable(TextAnimation a,double start,double end){switch(a){case TextAnimation.none:return 'between(t,$start,$end)';case TextAnimation.fade:return 'between(t,$start,$end)';case TextAnimation.slideUp:return 'between(t,$start,$end)';case TextAnimation.slideDown:return 'between(t,$start,$end)';case TextAnimation.pop:return 'between(t,$start,$end)';case TextAnimation.typewriter:return 'between(t,$start,$end)';}}
  String _clipEffects(ProjectModel p,Duration start,Duration duration,int width,int height){final parts=<String>[];for(final e in p.elements.where((e)=>e.kind==ElementKind.vfx)){final s=((e.start-start).inMilliseconds/1000).clamp(0,duration.inMilliseconds/1000).toDouble(),en=((e.end-start).inMilliseconds/1000).clamp(0,duration.inMilliseconds/1000).toDouble();if(en<=s)continue;final enable="enable='between(t,$s,$en)'";final n=(e.intensity.clamp(.1,1)*12).round();switch(e.text.toLowerCase()){case'blur':parts.add(',boxblur=luma_radius=$n:luma_power=1:$enable');break;case'glow':parts.add(',gblur=sigma=${2+n/2}:steps=1:$enable');break;case'flash':parts.add(',eq=brightness=${.65*e.intensity}:$enable');break;case'zoom':parts.add(',scale=iw*${1+.12*e.intensity}:ih*${1+.12*e.intensity},crop=$width:$height:(iw-$width)/2:(ih-$height)/2:$enable');break;case'chromatic':parts.add(',chromashift=cbh=$n:crh=-$n:$enable');break;case'glitch':parts.add(',noise=alls=${(n*2).clamp(1,30)}:allf=t:$enable');break;case'fade':parts.add(',eq=brightness=-${.35*e.intensity}:$enable');break;case'shake':case'motion':parts.add(',rotate=0.02*sin(80*t):fillcolor=black:$enable');break;}}return parts.join();}
  String _videoFilter(ProjectModel p){final parts=<String>[];final i=p.filterIntensity.clamp(0,1);switch(p.filter){case FilterPreset.normal:break;case FilterPreset.bright:parts.add('eq=brightness=${.18*i}:contrast=1.05');break;case FilterPreset.contrast:parts.add('eq=contrast=${1+.55*i}');break;case FilterPreset.warm:parts.add('colorbalance=rs=${.18*i}:gs=${.05*i}:bs=${-.12*i}');break;case FilterPreset.cool:parts.add('colorbalance=rs=${-.1*i}:gs=${.04*i}:bs=${.2*i}');break;case FilterPreset.vintage:parts.add('curves=vintage');break;case FilterPreset.blackWhite:parts.add('hue=s=0');break;case FilterPreset.cinematic:parts.add('eq=contrast=${1+.25*i}:saturation=${1+.15*i},vignette=PI/5');break;case FilterPreset.dramatic:parts.add('eq=contrast=${1+.7*i}:saturation=${1+.1*i},unsharp=5:5:${1.2*i}:5:5:0');break;}final a=p.adjustments;if(a.isNotEmpty)parts.add('eq=brightness=${(a['brightness']??0)/100}:contrast=${1+(a['contrast']??0)/100}:saturation=${1+(a['saturation']??0)/100}');if((a['vignette']??0)>0)parts.add('vignette=PI/${5+(1-(a['vignette']!/100).clamp(0,1))*8}');return parts.isEmpty?'':',${parts.join(',')}';}
  String _escapeText(String s)=>s.replaceAll('\\','\\\\').replaceAll(':','\\:').replaceAll("'","\\'").replaceAll('%','\\%');
  String _q(String p)=>'"${p.replaceAll('"','\\"')}"';
}
