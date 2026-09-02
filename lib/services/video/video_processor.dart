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
    final s=await FFmpegKit.execute('-y -ss ${clip.start.inMilliseconds/1000} -i ${_q(clip.file.path)} -t ${clip.duration.inMilliseconds/1000} -map 0 -c copy -avoid_negative_ts make_zero ${_q(out.path)}');
    return ReturnCode.isSuccess(await s.getReturnCode())&&await out.exists()?VideoProcessResult(true,file:out):const VideoProcessResult(false,error:'Video processing failed');
  }

  Future<VideoProcessResult> render({required ProjectModel project,required int width,required int height,required int fps,ExportProgress? onProgress}) async {
    if(project.clips.isEmpty)return const VideoProcessResult(false,error:'No clips in project');
    final out=File('${(await getTemporaryDirectory()).path}/vm_export_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final args=<String>['-y']; final filters=<String>[]; final labels=<String>[]; final durations=<double>[]; var input=0;
    for(var i=0;i<project.clips.length;i++){
      final c=project.clips[i];
      if(c.kind==MediaKind.image)args.addAll(['-loop','1','-t','${c.duration.inMilliseconds/1000}','-i',_q(c.file.path)]);else args.addAll(['-i',_q(c.file.path)]);
      var f='[$input:v]trim=start=${c.start.inMilliseconds/1000}:end=${c.end.inMilliseconds/1000},setpts=PTS-STARTPTS';
      if(c.speed!=1)f+=',setpts=${1/c.speed}*PTS';
      final t=c.transform;
      if(t.left>0||t.top>0||t.right<1||t.bottom<1)f+=',crop=w=iw*${(t.right-t.left).clamp(.05,1)}:h=ih*${(t.bottom-t.top).clamp(.05,1)}:x=iw*${t.left.clamp(0,.95)}:y=ih*${t.top.clamp(0,.95)}';
      if(t.zoom!=1)f+=',scale=iw*${t.zoom.clamp(.1,6)}:ih*${t.zoom.clamp(.1,6)}';
      if(t.rotation!=0)f+=',rotate=${t.rotation}:fillcolor=black';
      f+=',scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2+(iw-ow)/2*${t.panX.clamp(-1,1)}:(oh-ih)/2+(ih-oh)/2*${t.panY.clamp(-1,1)}:black,fps=$fps,setsar=1';
      f+=_videoFilter(project)+_effects(project,project.clips.take(i).fold(Duration.zero,(s,x)=>s+x.duration),c.duration,width,height);
      final label='[clip$i]';filters.add('$f$label');labels.add(label);durations.add(c.duration.inMilliseconds/1000);input++;
    }

    int? bgIndex;
    if(project.chromaBackgroundPath!=null&&project.chromaBackgroundPath!.isNotEmpty){bgIndex=input;final p=project.chromaBackgroundPath!;final image=RegExp(r'\.(png|jpe?g|webp)$',caseSensitive:false).hasMatch(p);if(image)args.addAll(['-loop','1','-i',_q(p)]);else args.addAll(['-stream_loop','-1','-i',_q(p)]);input++;filters.add('[$bgIndex:v]scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2:(oh-ih)/2:black,fps=$fps,setsar=1[bg]');}
    if(bgIndex!=null){for(var i=0;i<project.clips.length;i++){final c=project.clips[i];if(c.chromaSimilarity==null)continue;final color=(c.chromaColor??'#00ff00').replaceAll('#','');final key='[key$i]';final merged='[keybg$i]';filters.add('[clip$i]chromakey=0x$color:${(c.chromaSimilarity??.4).clamp(.01,1)}:${(c.chromaBlend??.08).clamp(0,1)}$key');filters.add('[bg]$key overlay=0:0:shortest=1$merged');labels[i]=merged;}}

    String current=labels.first;double currentDuration=durations.first;
    for(var i=1;i<labels.length;i++){final c=project.clips[i-1];var d=c.transitionDuration.inMilliseconds/1000;d=d.clamp(.05,durations[i-1]);d=d.clamp(.05,durations[i]);final next='[xf$i]';final offset=(currentDuration-d).clamp(0,999999);filters.add('$current${labels[i]}xfade=transition=${_transition(c.transitionAfter)}:duration=$d:offset=$offset$next');current=next;currentDuration=currentDuration+durations[i]-d;}

    for(final e in project.elements.where((e)=>e.kind==ElementKind.text)){final k=e.keyframes.isEmpty?null:e.keyframes.last;final x=((k?.x??e.x).clamp(0,1)*width).round(),y=((k?.y??e.y).clamp(0,1)*height).round(),size=((k?.scale??e.scale)*e.fontSize).round().clamp(8,300);final box=e.backgroundColor=='#00000000'?'':':box=1:boxcolor=${e.backgroundColor}';final outline=e.outline?':borderw=${e.outlineWidth.clamp(1,12)}:bordercolor=${e.outlineColor}':'';final shadow=e.shadow?':shadowx=2:shadowy=2:shadowcolor=black@0.7':'';final en="between(t,${e.start.inMilliseconds/1000},${e.end.inMilliseconds/1000})";final next='[txt_${e.id}]';filters.add("$current,drawtext=fontfile=${e.bold?'/system/fonts/Roboto-Bold.ttf':'/system/fonts/Roboto-Regular.ttf'}:text='${_escape(e.text)}':x=$x:y=$y:fontsize=$size:fontcolor=${e.color}$box$outline$shadow:enable='$en'$next");current=next;}

    for(var n=0;n<project.elements.length;n++){final e=project.elements[n];if((e.kind!=ElementKind.image&&e.kind!=ElementKind.video)||e.assetPath==null)continue;final p=e.assetPath!;final image=RegExp(r'\.(png|jpe?g|webp|heic)$',caseSensitive:false).hasMatch(p);if(image)args.addAll(['-loop','1','-i',_q(p)]);else args.addAll(['-i',_q(p)]);final idx=input++;final start=e.start.inMilliseconds/1000,end=e.end.inMilliseconds/1000;final w=(width*.45*e.scale.clamp(.05,3)).round(),h=(height*.45*e.scale.clamp(.05,3)).round();final x=(e.x.clamp(0,1)*width-w/2).round(),y=(e.y.clamp(0,1)*height-h/2).round();final layer='[ovsrc$n]',next='[ov$n]';filters.add('[$idx:v]setpts=PTS-STARTPTS,scale=$w:$h:force_original_aspect_ratio=decrease,format=rgba,colorchannelmixer=aa=${e.opacity.clamp(0,1)}$layer');filters.add("$current$layer overlay=x=$x:y=$y:enable='between(t,$start,$end)'$next");current=next;}

    filters.add('$current,format=yuv420p[vout]');args.addAll(['-filter_complex',filters.join(';'),'-map','[vout]']);
    if(project.audioTracks.isEmpty&&project.clips.length==1&&!project.clips.first.muted)args.addAll(['-map','0:a?']);
    if(project.audioTracks.isNotEmpty){final aud=<String>[];for(final a in project.audioTracks){args.addAll(['-i',_q(a.file.path)]);final idx=input++;final l='[aud${aud.length}]';var af='[$idx:a]atrim=start=${a.start.inMilliseconds/1000}:end=${a.end.inMilliseconds/1000},asetpts=PTS-STARTPTS,adelay=${a.position.inMilliseconds}|${a.position.inMilliseconds},volume=${a.muted?0:a.volume}';if(a.fadeIn>Duration.zero)af+=',afade=t=in:st=0:d=${a.fadeIn.inMilliseconds/1000}';if(a.fadeOut>Duration.zero)af+=',afade=t=out:st=${((a.end-a.start).inMilliseconds/1000-a.fadeOut.inMilliseconds/1000).clamp(0,99999)}:d=${a.fadeOut.inMilliseconds/1000}';filters.add('$af$l');aud.add(l);}if(aud.isNotEmpty){filters.add('${aud.join('')}amix=inputs=${aud.length}:duration=longest:dropout_transition=0[aout]');args[args.indexOf('-filter_complex')+1]=filters.join(';');args.addAll(['-map','[aout]']);}}
    args.addAll(['-c:v','mpeg4','-q:v','3','-pix_fmt','yuv420p','-movflags','+faststart','-c:a','aac','-b:a','192k',_q(out.path)]);
    onProgress?.call(0);final session=await FFmpegKit.executeWithArgumentsAsync(args,(s)async{},null,(stats){final total=project.duration.inMilliseconds.clamp(1,1<<31);onProgress?.call((stats.getTime()/total).clamp(0,1).toDouble());});final code=await session.getReturnCode();onProgress?.call(1);
    return ReturnCode.isSuccess(code)&&await out.exists()?VideoProcessResult(true,file:out):const VideoProcessResult(false,error:'Export failed. Check storage, media format, or lower resolution.');
  }

  String _transition(TransitionType t){switch(t){case TransitionType.fade:return'fade';case TransitionType.dissolve:return'dissolve';case TransitionType.slide:return'slideleft';case TransitionType.zoom:return'zoomin';case TransitionType.wipe:return'wipeleft';case TransitionType.blur:return'hblur';case TransitionType.push:return'slideright';}}
  String _effects(ProjectModel p,Duration clipStart,Duration clipDuration,int width,int height){final out=<String>[];for(final e in p.elements.where((e)=>e.kind==ElementKind.vfx)){final s=((e.start-clipStart).inMilliseconds/1000).clamp(0,clipDuration.inMilliseconds/1000).toDouble(),en=((e.end-clipStart).inMilliseconds/1000).clamp(0,clipDuration.inMilliseconds/1000).toDouble();if(en<=s)continue;final enb="enable='between(t,$s,$en)'";final n=(e.intensity.clamp(.1,1)*12).round();switch(e.text.toLowerCase()){case'blur':out.add(',boxblur=luma_radius=$n:luma_power=1:$enb');break;case'glow':out.add(',gblur=sigma=${2+n/2}:steps=1:$enb');break;case'flash':out.add(',eq=brightness=${.65*e.intensity}:$enb');break;case'zoom':out.add(',scale=iw*${1+.12*e.intensity}:ih*${1+.12*e.intensity},crop=$width:$height:(iw-$width)/2:(ih-$height)/2:$enb');break;case'chromatic':out.add(',chromashift=cbh=$n:crh=-$n:$enb');break;case'glitch':out.add(',noise=alls=${(n*2).clamp(1,30)}:allf=t:$enb');break;case'fade':out.add(',eq=brightness=-${.35*e.intensity}:$enb');break;case'shake':case'motion':out.add(',rotate=0.02*sin(80*t):fillcolor=black:$enb');break;}}return out.join();}
  String _videoFilter(ProjectModel p){final out=<String>[];final i=p.filterIntensity.clamp(0,1);switch(p.filter){case FilterPreset.normal:break;case FilterPreset.bright:out.add('eq=brightness=${.18*i}:contrast=1.05');break;case FilterPreset.contrast:out.add('eq=contrast=${1+.55*i}');break;case FilterPreset.warm:out.add('colorbalance=rs=${.18*i}:gs=${.05*i}:bs=${-.12*i}');break;case FilterPreset.cool:out.add('colorbalance=rs=${-.1*i}:gs=${.04*i}:bs=${.2*i}');break;case FilterPreset.vintage:out.add('curves=vintage');break;case FilterPreset.blackWhite:out.add('hue=s=0');break;case FilterPreset.cinematic:out.add('eq=contrast=${1+.25*i}:saturation=${1+.15*i},vignette=PI/5');break;case FilterPreset.dramatic:out.add('eq=contrast=${1+.7*i}:saturation=${1+.1*i},unsharp=5:5:${1.2*i}:5:5:0');break;}final a=p.adjustments;if(a.isNotEmpty)out.add('eq=brightness=${(a['brightness']??0)/100}:contrast=${1+(a['contrast']??0)/100}:saturation=${1+(a['saturation']??0)/100}');return out.isEmpty?'':',${out.join(',')}';}
  String _escape(String s)=>s.replaceAll('\\','\\\\').replaceAll(':','\\:').replaceAll("'","\\'").replaceAll('%','\\%');
  String _q(String p)=>'"${p.replaceAll('"','\\"')}"';
}
