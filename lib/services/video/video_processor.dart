import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/editor_models.dart';

class VideoProcessResult {
  final bool success;
  final File? file;
  final String? error;
  const VideoProcessResult(this.success, {this.file, this.error});
}

class VideoProcessor {
  Future<VideoProcessResult> trim(EditorClip clip) async {
    if (!await clip.file.exists()) return const VideoProcessResult(false, error: 'Source file not found');
    if (clip.kind != MediaKind.video) return const VideoProcessResult(false, error: 'Only video clips can be trimmed');
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/vm_trim_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final start = clip.start.inMilliseconds / 1000.0;
    final duration = clip.duration.inMilliseconds / 1000.0;
    if (duration <= 0) return const VideoProcessResult(false, error: 'Invalid trim range');
    final command = '-y -ss $start -i ${_q(clip.file.path)} -t $duration -map 0 -c copy -avoid_negative_ts make_zero ${_q(out.path)}';
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    return ReturnCode.isSuccess(code) && await out.exists() ? VideoProcessResult(true, file: out) : const VideoProcessResult(false, error: 'Video processing failed');
  }

  Future<VideoProcessResult> render({required ProjectModel project, required int width, required int height, required int fps}) async {
    if (project.clips.isEmpty) return const VideoProcessResult(false, error: 'No video clips in project');
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/vm_export_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final args = <String>['-y'];
    final filters = <String>[];
    final labels = <String>[];
    var globalClipStart = Duration.zero;

    for (var i = 0; i < project.clips.length; i++) {
      final clip = project.clips[i];
      if (clip.kind == MediaKind.image) {
        args.addAll(['-loop', '1', '-t', '${clip.duration.inMilliseconds / 1000.0}', '-i', _q(clip.file.path)]);
      } else {
        args.addAll(['-i', _q(clip.file.path)]);
      }
      var chain = '[${i}:v]trim=start=${clip.start.inMilliseconds / 1000.0}:end=${clip.end.inMilliseconds / 1000.0},setpts=PTS-STARTPTS';
      if (clip.speed != 1) chain += ',setpts=${1 / clip.speed}*PTS';
      chain += ',scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black,fps=$fps,setsar=1';
      chain += _videoFilter(project);
      chain += _effectsForClip(project, globalClipStart, clip.duration);
      chain += '[v$i]';
      filters.add(chain);
      labels.add('[v$i]');
      globalClipStart += clip.duration;
    }

    if (project.elements.any((e) => e.kind == ElementKind.text)) {
      for (final element in project.elements.where((e) => e.kind == ElementKind.text)) {
        final safe = element.text.replaceAll('\\', '\\\\').replaceAll(':', '\\:').replaceAll("'", "\\'").replaceAll('%', '\\%');
        final start = element.start.inMilliseconds / 1000.0;
        final end = element.end.inMilliseconds / 1000.0;
        for (var i = 0; i < labels.length; i++) {
          final source = labels[i];
          final next = '[vt_${i}_${element.id}]';
          final x = (element.x.clamp(0, 1) * width).round();
          final y = (element.y.clamp(0, 1) * height).round();
          filters.add('$source,drawtext=text=\'$safe\':x=$x:y=$y:fontsize=${element.fontSize.round()}:fontcolor=${element.color}:borderw=${element.outline ? 3 : 0}:shadowx=${element.shadow ? 2 : 0}:shadowy=${element.shadow ? 2 : 0}:enable=\'between(t,$start,$end)\'$next');
          labels[i] = next;
        }
      }
    }

    final videoOut = '[vmv]';
    filters.add('${labels.join('')}concat=n=${project.clips.length}:v=1:a=0$videoOut');
    args.addAll(['-filter_complex', filters.join(';'), '-map', videoOut]);

    if (project.clips.length == 1 && project.audioTracks.isEmpty && !project.clips.first.muted) {
      args.addAll(['-map', '0:a?']);
    } else if (project.audioTracks.isNotEmpty) {
      for (final audio in project.audioTracks) args.addAll(['-i', _q(audio.file.path)]);
      final audioStartIndex = project.clips.length;
      final audioLabels = <String>[];
      for (var i = 0; i < project.audioTracks.length; i++) {
        final a = project.audioTracks[i];
        final label = '[a$i]';
        final fadeIn = a.fadeIn.inMilliseconds / 1000.0;
        final fadeOut = a.fadeOut.inMilliseconds / 1000.0;
        var af = '[${audioStartIndex + i}:a]atrim=start=${a.start.inMilliseconds / 1000.0}:end=${a.end.inMilliseconds / 1000.0},asetpts=PTS-STARTPTS,adelay=${a.position.inMilliseconds}|${a.position.inMilliseconds},volume=${a.muted ? 0 : a.volume}';
        if (fadeIn > 0) af += ',afade=t=in:st=0:d=$fadeIn';
        if (fadeOut > 0) af += ',afade=t=out:st=${((a.end - a.start).inMilliseconds / 1000.0 - fadeOut).clamp(0, 999999)}:d=$fadeOut';
        filters.add('$af$label');
        audioLabels.add(label);
      }
      filters.add('${audioLabels.join('')}amix=inputs=${audioLabels.length}:duration=longest:dropout_transition=0[vmAudio]');
      args[args.indexOf('-filter_complex') + 1] = filters.join(';');
      args.addAll(['-map', '[vmAudio]', '-shortest']);
    }

    args.addAll(['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', _q(out.path)]);
    final session = await FFmpegKit.execute(args.join(' '));
    final code = await session.getReturnCode();
    return ReturnCode.isSuccess(code) && await out.exists() ? VideoProcessResult(true, file: out) : const VideoProcessResult(false, error: 'Export failed. Try a lower resolution or shorter project.');
  }

  String _effectsForClip(ProjectModel project, Duration clipStart, Duration clipDuration) {
    final parts = <String>[];
    for (final e in project.elements.where((e) => e.kind == ElementKind.vfx)) {
      final localStart = (e.start - clipStart).inMilliseconds / 1000.0;
      final localEnd = (e.end - clipStart).inMilliseconds / 1000.0;
      final start = localStart.clamp(0, clipDuration.inMilliseconds / 1000.0);
      final end = localEnd.clamp(0, clipDuration.inMilliseconds / 1000.0);
      if (end <= start) continue;
      final enable = "enable='between(t,$start,$end)'";
      final strength = (e.intensity.clamp(.1, 1) * 12).round();
      switch (e.text.toLowerCase()) {
        case 'blur':
          parts.add(',boxblur=luma_radius=$strength:luma_power=1:$enable');
          break;
        case 'glow':
          parts.add(',gblur=sigma=${2 + strength / 2}:steps=1:$enable');
          break;
        case 'flash':
          parts.add(',eq=brightness=${.65 * e.intensity}:$enable');
          break;
        case 'zoom':
          parts.add(',scale=iw*${1 + .12 * e.intensity}:ih*${1 + .12 * e.intensity},crop=$width:$height:((iw-$width)/2):((ih-$height)/2):$enable');
          break;
        case 'chromatic':
          parts.add(',chromashift=cbh=$strength:crh=-$strength:$enable');
          break;
        case 'glitch':
          parts.add(',noise=alls=${(strength * 2).clamp(1, 30)}:allf=t:$enable');
          break;
        case 'fade':
          parts.add(',eq=brightness=-${.35 * e.intensity}:$enable');
          break;
        case 'shake':
        case 'motion':
          parts.add(',rotate=0.02*sin(80*t):fillcolor=black:$enable');
          break;
        default:
          break;
      }
    }
    return parts.join();
  }

  String _videoFilter(ProjectModel p) {
    final parts = <String>[];
    final intensity = p.filterIntensity.clamp(0, 1);
    switch (p.filter) {
      case FilterPreset.normal: break;
      case FilterPreset.bright: parts.add('eq=brightness=${0.18 * intensity}:contrast=1.05'); break;
      case FilterPreset.contrast: parts.add('eq=contrast=${1 + .55 * intensity}'); break;
      case FilterPreset.warm: parts.add('colorbalance=rs=${.18 * intensity}:gs=${.05 * intensity}:bs=${-.12 * intensity}'); break;
      case FilterPreset.cool: parts.add('colorbalance=rs=${-.10 * intensity}:gs=${.04 * intensity}:bs=${.20 * intensity}'); break;
      case FilterPreset.vintage: parts.add('curves=vintage'); break;
      case FilterPreset.blackWhite: parts.add('hue=s=0'); break;
      case FilterPreset.cinematic: parts.add('eq=contrast=${1 + .25 * intensity}:saturation=${1 + .15 * intensity},vignette=PI/5'); break;
      case FilterPreset.dramatic: parts.add('eq=contrast=${1 + .7 * intensity}:saturation=${1 + .1 * intensity},unsharp=5:5:${1.2 * intensity}:5:5:0'); break;
    }
    final a = p.adjustments;
    if (a.isNotEmpty) parts.add('eq=brightness=${(a['brightness'] ?? 0) / 100}:contrast=${1 + (a['contrast'] ?? 0) / 100}:saturation=${1 + (a['saturation'] ?? 0) / 100}');
    if ((a['vignette'] ?? 0) > 0) parts.add('vignette=PI/${5 + (1 - (a['vignette']! / 100).clamp(0, 1)) * 8}');
    if ((a['fade'] ?? 0) > 0) parts.add('eq=contrast=${1 - (a['fade']! / 100).clamp(0, .9)}');
    return parts.isEmpty ? '' : ',${parts.join(',')}';
  }

  String _q(String path) => '"${path.replaceAll('"', '\\"')}"';
}
