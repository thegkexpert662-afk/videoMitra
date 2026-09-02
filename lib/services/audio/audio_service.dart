import 'dart:io';
import '../../models/editor_models.dart';

class AudioService {
  AudioTrack createTrack(File file, {Duration? duration, Duration? position}) {
    final end = duration ?? const Duration(minutes: 30);
    return AudioTrack(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
      file: file,
      start: Duration.zero,
      end: end,
      position: position ?? Duration.zero,
    );
  }

  AudioTrack setFade(AudioTrack track, {Duration? fadeIn, Duration? fadeOut}) => AudioTrack(
        id: track.id,
        file: track.file,
        start: track.start,
        end: track.end,
        position: track.position,
        volume: track.volume,
        muted: track.muted,
        fadeIn: fadeIn ?? track.fadeIn,
        fadeOut: fadeOut ?? track.fadeOut,
      );
}
