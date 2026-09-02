import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../controllers/editor_controller.dart';
import '../../models/editor_models.dart';
import '../../services/export/export_service.dart';

class EditorScreen extends StatefulWidget {
  final List<File> mediaFiles;
  final ProjectModel? project;
  const EditorScreen({super.key, required this.mediaFiles, this.project});
  @override State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController editor;
  final picker = ImagePicker();
  VideoPlayerController? player;
  Timer? autosave;
  bool loading = true;
  bool exporting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    editor = EditorController();
    if (widget.project != null) {
      editor.project = widget.project!;
    } else {
      editor.initialize(widget.mediaFiles);
    }
    editor.addListener(_changed);
    _openClip(0);
    autosave = Timer.periodic(const Duration(seconds: 12), (_) { if (editor.dirty) editor.save(); });
  }

  void _changed() {
    if (mounted) setState(() {});
    final i = editor.clipAt(editor.playhead);
    if (i >= 0 && i != editor.selectedClip) _openClip(i, autoSeek: true);
  }

  Future<void> _openClip(int index, {bool autoSeek = false}) async {
    if (index < 0 || index >= editor.project.clips.length) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final clip = editor.project.clips[index];
    await player?.dispose();
    player = null;
    if (mounted) setState(() { loading = true; error = null; });
    if (clip.kind == MediaKind.image) {
      editor.selectedClip = index;
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      final p = VideoPlayerController.file(clip.file);
      player = p;
      await p.initialize();
      if (clip.sourceDuration == Duration.zero) editor.updateClipDuration(index, p.value.duration);
      await p.setPlaybackSpeed(clip.speed);
      p.addListener(_playerTick);
      editor.selectedClip = index;
      if (autoSeek) {
        final local = editor.playhead - editor.clipStart(index);
        final source = clip.start + Duration(milliseconds: (local.inMilliseconds * clip.speed).round());
        await p.seekTo(source < clip.start ? clip.start : source);
      } else {
        await p.seekTo(clip.start);
      }
      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Video load failed: $e'; });
    }
  }

  void _playerTick() {
    final p = player;
    if (p == null || !p.value.isInitialized || !mounted || editor.project.clips.isEmpty) return;
    final clip = editor.project.clips[editor.selectedClip];
    final source = p.value.position;
    final localMs = ((source - clip.start).inMilliseconds / clip.speed).round().clamp(0, clip.duration.inMilliseconds).toInt();
    editor.setPlayhead(editor.clipStart(editor.selectedClip) + Duration(milliseconds: localMs));
    if (source >= clip.end && p.value.isPlaying) {
      if (editor.selectedClip + 1 < editor.project.clips.length) {
        _openClip(editor.selectedClip + 1);
        Future.microtask(() => player?.play());
      } else {
        p.pause();
      }
    }
  }

  @override
  void dispose() {
    autosave?.cancel();
    editor.removeListener(_changed);
    editor.save();
    player?.dispose();
    editor.dispose();
    super.dispose();
  }

  String _time(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  double get _ratio {
    switch (editor.project.ratio) {
      case CanvasRatio.r9x16: return 9 / 16;
      case CanvasRatio.r16x9: return 16 / 9;
      case CanvasRatio.r1x1: return 1;
      case CanvasRatio.r4x3: return 4 / 3;
      case CanvasRatio.r4x5: return 4 / 5;
      case CanvasRatio.original: return player?.value.isInitialized == true ? player!.value.aspectRatio : 16 / 9;
    }
  }

  Color? _color(String? v) {
    if (v == null) return null;
    final h = v.replaceAll('#', '');
    if (h.length != 6) return null;
    return Color(int.parse('FF$h', radix: 16));
  }

  Widget _preview() {
    final clip = editor.project.clips.isEmpty ? null : editor.project.clips[editor.selectedClip];
    Widget media;
    if (clip == null) {
      media = const Center(child: Text('Import media to start'));
    } else if (clip.kind == MediaKind.image) {
      media = Image.file(clip.file, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('Image load failed')));
    } else if (loading) {
      media = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      media = Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(error!, textAlign: TextAlign.center)));
    } else if (player?.value.isInitialized == true) {
      media = FittedBox(fit: BoxFit.contain, child: SizedBox(width: player!.value.size.width, height: player!.value.size.height, child: VideoPlayer(player!)));
    } else {
      media = const Center(child: CircularProgressIndicator());
    }
    media = _previewFilter(media);
    final active = editor.project.elements.where((e) => editor.playhead >= e.start && editor.playhead <= e.end).toList()..sort((a, b) => a.layer.compareTo(b.layer));
    for (final e in active.where((e) => e.kind == ElementKind.vfx)) {
      switch (e.text.toLowerCase()) {
        case 'blur': media = BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 8 * e.intensity, sigmaY: 8 * e.intensity), child: media); break;
        case 'flash': media = Stack(children: [media, Container(color: Colors.white.withOpacity(.35 * e.intensity))]); break;
        case 'zoom': media = Transform.scale(scale: 1 + .12 * e.intensity, child: media); break;
      }
    }
    return Center(child: AspectRatio(aspectRatio: _ratio, child: ClipRect(child: Stack(fit: StackFit.expand, children: [
      Container(color: _color(editor.project.backgroundColor) ?? Colors.black), media,
      for (final e in active.where((e) => e.kind != ElementKind.vfx)) _element(e),
      if (exporting) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
    ]))));
  }

  Widget _previewFilter(Widget child) {
    if (editor.project.filter == FilterPreset.blackWhite) {
      return ColorFiltered(colorFilter: const ColorFilter.matrix([.2126,.7152,.0722,0,0,.2126,.7152,.0722,0,0,.2126,.7152,.0722,0,0,0,0,0,1,0]), child: child);
    }
    final a = editor.project.adjustments;
    final b = (a['brightness'] ?? 0) / 100;
    final c = 1 + (a['contrast'] ?? 0) / 100;
    final s = 1 + (a['saturation'] ?? 0) / 100;
    if (editor.project.filter == FilterPreset.bright || b != 0 || c != 1 || s != 1) {
      return ColorFiltered(colorFilter: ColorFilter.matrix([c,0,0,0,b*255,0,c,0,0,b*255,0,0,c,0,b*255,0,0,0,1,0]), child: child);
    }
    return child;
  }

  Widget _element(EditorElement e) {
    Widget child;
    if (e.kind == ElementKind.text) {
      child = Text(e.text, textAlign: TextAlign.center, style: TextStyle(color: _color(e.color) ?? Colors.white, fontSize: e.fontSize * e.scale, fontWeight: e.bold ? FontWeight.bold : FontWeight.normal, fontStyle: e.italic ? FontStyle.italic : FontStyle.normal, shadows: e.shadow ? const [Shadow(blurRadius: 5, offset: Offset(2,2))] : null));
    } else if (e.kind == ElementKind.image && e.assetPath != null) {
      child = Image.file(File(e.assetPath!), fit: BoxFit.contain);
    } else {
      child = Text(e.text.isEmpty ? '✨' : e.text, style: TextStyle(fontSize: 48 * e.scale));
    }
    return Positioned(left: e.x * MediaQuery.sizeOf(context).width * .8 - 50, top: e.y * MediaQuery.sizeOf(context).height * .45 - 30, child: Opacity(opacity: e.opacity.clamp(0, 1), child: Transform.rotate(angle: e.rotation, child: child)));
  }

  Future<void> _canvas() async {
    final r = await showModalBottomSheet<CanvasRatio>(context: context, backgroundColor: const Color(0xFF111118), builder: (_) => _ChoiceSheet(title: 'Canvas / Ratio', items: const [_Choice('Original',CanvasRatio.original),_Choice('9:16',CanvasRatio.r9x16),_Choice('16:9',CanvasRatio.r16x9),_Choice('1:1',CanvasRatio.r1x1),_Choice('4:3',CanvasRatio.r4x3),_Choice('4:5',CanvasRatio.r4x5)], current: editor.project.ratio));
    if (r != null) editor.setCanvas(r);
  }

  Future<void> _trim() async {
    if (editor.project.clips.isEmpty) return;
    final c = editor.project.clips[editor.selectedClip];
    if (c.kind == MediaKind.image) { _snack('Image clips use a 5 second default duration.'); return; }
    var s = c.start.inMilliseconds.toDouble(), e = c.end.inMilliseconds.toDouble();
    final r = await showModalBottomSheet<RangeValues>(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF111118), builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Trim Video',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:12),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('Start ${_time(Duration(milliseconds:s.round()))}'),Text('End ${_time(Duration(milliseconds:e.round()))}')]),RangeSlider(min:0,max:c.sourceDuration.inMilliseconds.toDouble(),values:RangeValues(s,e),onChanged:(v){set((){s=v.start;e=v.end;});player?.seekTo(Duration(milliseconds:v.start.round()));}),Text('Selected ${_time(Duration(milliseconds:(e-s).round()))}'),const SizedBox(height:10),FilledButton(onPressed:()=>Navigator.pop(ctx,RangeValues(s,e)),child:const Text('Apply'))]))));
    if (r != null) { editor.trimSelected(Duration(milliseconds:r.start.round()), Duration(milliseconds:r.end.round())); await _openClip(editor.selectedClip); _snack('Trim applied'); }
  }

  void _split() { editor.splitAtPlayhead(); _snack('Split at playhead'); }
  void _delete() { editor.deleteSelectedClip(); _openClip(editor.selectedClip); _snack('Selected clip deleted'); }

  Future<void> _audio() async { final f=await FilePicker.platform.pickFiles(type:FileType.audio); if(f?.files.single.path==null)return; editor.addAudio(AudioTrack(id:'audio_${DateTime.now().millisecondsSinceEpoch}',file:File(f!.files.single.path!),start:Duration.zero,end:const Duration(minutes:30))); _snack('Audio track added'); }
  Future<void> _text() async { final c=TextEditingController(text:'Your text'); final t=await showDialog<String>(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF17171F),title:const Text('Add Text'),content:TextField(controller:c,autofocus:true,maxLines:3),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,c.text),child:const Text('Add'))])); c.dispose(); if(t!=null&&t.trim().isNotEmpty)editor.addText(t); }
  Future<void> _filters() async { final f=await showModalBottomSheet<FilterPreset>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>_ChoiceSheet(title:'Filters',items:const[_Choice('Normal',FilterPreset.normal),_Choice('Bright',FilterPreset.bright),_Choice('Contrast',FilterPreset.contrast),_Choice('Warm',FilterPreset.warm),_Choice('Cool',FilterPreset.cool),_Choice('Vintage',FilterPreset.vintage),_Choice('B&W',FilterPreset.blackWhite),_Choice('Cinematic',FilterPreset.cinematic),_Choice('Dramatic',FilterPreset.dramatic)],current:editor.project.filter)); if(f!=null)editor.setFilter(f,1); }
  Future<void> _adjust() async { final keys=['brightness','contrast','saturation','exposure','temperature','tint','highlights','shadows','sharpness','fade','vignette']; await showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:const Color(0xFF111118),builder:(_)=>StatefulBuilder(builder:(ctx,set)=>Padding(padding:const EdgeInsets.fromLTRB(18,18,18,28),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Adjust',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),for(final k in keys)Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(k),Text('${(editor.project.adjustments[k]??0).round()}')]),Slider(min:-100,max:100,value:(editor.project.adjustments[k]??0).clamp(-100,100),onChanged:(v){editor.setAdjustment(k,v);set((){});})])]))))); }
  Future<void> _speed() async { const values=[.25,.5,.75,1,1.25,1.5,2]; final s=await showModalBottomSheet<double>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>Wrap(children:[for(final x in values)SizedBox(width:MediaQuery.sizeOf(context).width/3,child:ListTile(title:Text('${x}x',textAlign:TextAlign.center),onTap:()=>Navigator.pop(context,x)))])); if(s!=null){editor.setSpeed(s);await player?.setPlaybackSpeed(s);} }
  Future<void> _overlay() async { final f=await picker.pickImage(source:ImageSource.gallery); if(f==null)return; editor.addElement(EditorElement(id:'overlay_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.image,assetPath:f.path,start:editor.playhead,end:editor.playhead+const Duration(seconds:5))); }
  Future<void> _stickers() async { final s=await showModalBottomSheet<String>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>Wrap(children:[for(final x in ['😀','🔥','⭐','❤️','🎉','⚡','✨','🎬'])SizedBox(width:MediaQuery.sizeOf(context).width/4,child:ListTile(title:Text(x,style:const TextStyle(fontSize:30),textAlign:TextAlign.center),onTap:()=>Navigator.pop(context,x)))])); if(s!=null)editor.addElement(EditorElement(id:'sticker_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.sticker,text:s,start:editor.playhead,end:editor.playhead+const Duration(seconds:4))); }
  Future<void> _effects() async { final s=await showModalBottomSheet<String>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>Wrap(children:[for(final x in ['Blur','Glow','Shake','Flash','Zoom','Motion','Chromatic','Glitch','Fade'])ListTile(leading:const Icon(Icons.auto_awesome),title:Text(x),onTap:()=>Navigator.pop(context,x))])); if(s!=null)editor.addElement(EditorElement(id:'fx_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.vfx,text:s,start:editor.playhead,end:editor.playhead+const Duration(seconds:3),intensity:.7)); }
  Future<void> _vfx() async { final s=await showModalBottomSheet<String>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>Wrap(children:[for(final x in ['Smoke','Fire','Sparks','Lightning','Explosion','Dust','Fog','Glow','Energy'])ListTile(leading:const Icon(Icons.auto_awesome),title:Text(x),onTap:()=>Navigator.pop(context,x))])); if(s!=null)editor.addElement(EditorElement(id:'vfx_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.vfx,text:s,start:editor.playhead,end:editor.playhead+const Duration(seconds:3),intensity:.7)); }
  void _keyframe(){editor.addKeyframe();_snack('Keyframe added');}
  void _chroma(){editor.addElement(EditorElement(id:'chroma_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.vfx,text:'Chroma',start:Duration.zero,end:editor.project.duration,intensity:.45));_snack('Green-screen key added. Export uses green chroma key.');}

  Future<void> _export() async { final o=await showModalBottomSheet<ExportOptions>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>const _ExportSheet()); if(o==null)return; setState(()=>exporting=true); try{final file=await ExportService().export(editor.project,o);if(!mounted)return;setState(()=>exporting=false);await showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF17171F),title:const Text('Export complete'),content:const Text('Video exported successfully.'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close')),FilledButton(onPressed:()async{await Share.shareXFiles([XFile(file.path)],text:'Created with VideoMitra');if(mounted)Navigator.pop(context);},child:const Text('Share'))]));}catch(e){if(mounted){setState(()=>exporting=false);_snack('Export failed: $e');}} }
  void _snack(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context){
    final total=editor.project.duration; final max=total.inMilliseconds.toDouble();
    return Scaffold(backgroundColor:const Color(0xFF050509),appBar:AppBar(backgroundColor:const Color(0xFF09090F),leading:IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>Navigator.pop(context)),title:const Text('VideoMitra',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:editor.undo,icon:const Icon(Icons.undo)),IconButton(onPressed:editor.redo,icon:const Icon(Icons.redo)),TextButton(onPressed:_canvas,child:const Text('Canvas')),TextButton(onPressed:_export,child:const Text('Export'))]),body:SafeArea(child:Column(children:[Expanded(flex:6,child:Padding(padding:const EdgeInsets.all(10),child:_preview())),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Padding(padding:const EdgeInsets.only(left:12),child:Text(_time(editor.playhead))),IconButton(icon:Icon(player?.value.isPlaying==true?Icons.pause_circle_filled:Icons.play_circle_fill,size:40),onPressed:(){final p=player;if(p==null)return;p.value.isPlaying?p.pause():p.play();}),Padding(padding:const EdgeInsets.only(right:12),child:Text(_time(total)))]),Expanded(flex:4,child:Column(children:[_timeline(max),SizedBox(height:92,child:ListView.separated(padding:const EdgeInsets.all(8),scrollDirection:Axis.horizontal,itemCount:editor.project.clips.length,separatorBuilder:(_,__)=>const SizedBox(width:6),itemBuilder:(_,i)=>_clip(i))),const Divider(height:1),SizedBox(height:94,child:ListView.separated(padding:const EdgeInsets.all(8),scrollDirection:Axis.horizontal,itemCount:_tools.length,separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(_,i){final t=_tools[i];return _Tool(icon:t.$1,label:t.$2,onTap:t.$3);}))]))]));
  }

  Widget _timeline(double max){final m=max<=0?1:max;final value=editor.playhead.inMilliseconds.clamp(0,m).toDouble();return Column(children:[Slider(min:0,max:m,value:value,onChanged:(v){editor.setPlayhead(Duration(milliseconds:v.round()));final i=editor.clipAt(editor.playhead);if(i>=0&&i!=editor.selectedClip)_openClip(i,autoSeek:true);else if(player!=null&&editor.project.clips.isNotEmpty){final c=editor.project.clips[editor.selectedClip];final local=editor.playhead-editor.clipStart(editor.selectedClip);player!.seekTo(c.start+Duration(milliseconds:(local.inMilliseconds*c.speed).round()));}}),_track('VIDEO',Colors.purple,editor.project.clips.length),_track('AUDIO',Colors.blueGrey,editor.project.audioTracks.length),_track('TEXT',Colors.pink,editor.project.elements.where((e)=>e.kind==ElementKind.text).length),_track('OVERLAY',Colors.amber,editor.project.elements.where((e)=>e.kind==ElementKind.image||e.kind==ElementKind.video).length),_track('VFX',Colors.deepPurple,editor.project.elements.where((e)=>e.kind==ElementKind.vfx||e.kind==ElementKind.sticker).length)]);}
  Widget _track(String n,Color c,int count)=>Padding(padding:const EdgeInsets.fromLTRB(10,2,10,0),child:Row(children:[SizedBox(width:55,child:Text(n,style:const TextStyle(fontSize:9,color:Colors.white54))),Expanded(child:Container(height:13,decoration:BoxDecoration(color:Colors.white.withOpacity(.04),borderRadius:BorderRadius.circular(4)),child:count==0?null:Align(alignment:Alignment.centerLeft,child:FractionallySizedBox(width:(count/4).clamp(.08,1).toDouble(),child:Container(decoration:BoxDecoration(color:c.withOpacity(.55),borderRadius:BorderRadius.circular(4)))))))]));
  List<(IconData,String,VoidCallback)> get _tools=>[(Icons.content_cut,'Trim',_trim),(Icons.call_split,'Split',_split),(Icons.delete_outline,'Delete',_delete),(Icons.music_note,'Audio',_audio),(Icons.text_fields,'Text',_text),(Icons.filter_alt,'Filters',_filters),(Icons.tune,'Adjust',_adjust),(Icons.auto_awesome,'Effects',_effects),(Icons.speed,'Speed',_speed),(Icons.layers,'Overlay',_overlay),(Icons.emoji_emotions,'Sticker',_stickers),(Icons.auto_awesome_outlined,'VFX',_vfx),(Icons.videocam_outlined,'Green Screen',_chroma),(Icons.key,'Keyframe',_keyframe),(Icons.crop,'Crop',_canvas),(Icons.volume_off,'Mute',(){editor.toggleMuteOriginal();})];
  Widget _clip(int i){final c=editor.project.clips[i],sel=i==editor.selectedClip;return GestureDetector(onTap:(){editor.selectClip(i);_openClip(i);},child:AnimatedContainer(duration:const Duration(milliseconds:150),width:150,padding:const EdgeInsets.all(7),decoration:BoxDecoration(color:sel?const Color(0xFF321525):const Color(0xFF171720),borderRadius:BorderRadius.circular(8),border:Border.all(color:sel?const Color(0xFFFF2D75):Colors.white10,width:sel?2:1)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:ClipThumbnail(file:c.file,isImage:c.kind==MediaKind.image)),const SizedBox(height:4),Text('${_time(c.duration)} • ${c.speed}x',style:const TextStyle(fontSize:10,color:Colors.white60))])));}
}

class ClipThumbnail extends StatefulWidget{final File file;final bool isImage;const ClipThumbnail({super.key,required this.file,required this.isImage});@override State<ClipThumbnail> createState()=>_ClipThumbnailState();}
class _ClipThumbnailState extends State<ClipThumbnail>{VideoPlayerController? p;@override void initState(){super.initState();if(!widget.isImage)_load();}Future<void> _load()async{try{final c=VideoPlayerController.file(widget.file);await c.initialize();await c.setVolume(0);await c.pause();if(mounted)setState(()=>p=c);else c.dispose();}catch(_){}}@override void dispose(){p?.dispose();super.dispose();}@override Widget build(BuildContext context){if(widget.isImage)return ClipRRect(borderRadius:BorderRadius.circular(5),child:Image.file(widget.file,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const ColoredBox(color:Colors.black,child:Icon(Icons.broken_image))));if(p?.value.isInitialized==true)return ClipRRect(borderRadius:BorderRadius.circular(5),child:FittedBox(fit:BoxFit.cover,child:SizedBox(width:p!.value.size.width,height:p!.value.size.height,child:VideoPlayer(p!))));return Container(decoration:BoxDecoration(color:const Color(0xFF252530),borderRadius:BorderRadius.circular(5)),child:const Center(child:Icon(Icons.play_arrow_rounded,color:Colors.white54)));}}

class _Tool extends StatelessWidget{final IconData icon;final String label;final VoidCallback onTap;const _Tool({required this.icon,required this.label,required this.onTap});@override Widget build(BuildContext context)=>InkWell(onTap:onTap,borderRadius:BorderRadius.circular(12),child:Container(width:76,padding:const EdgeInsets.symmetric(vertical:9),decoration:BoxDecoration(color:const Color(0xFF12121A),borderRadius:BorderRadius.circular(12),border:Border.all(color:Colors.white10)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:22,color:const Color(0xFFFF2D75)),const SizedBox(height:5),Text(label,style:const TextStyle(fontSize:9),overflow:TextOverflow.ellipsis)])));}
class _Choice<T>{final String title;final T value;const _Choice(this.title,this.value);}
class _ChoiceSheet<T> extends StatelessWidget{final String title;final List<_Choice<T>> items;final T current;const _ChoiceSheet({required this.title,required this.items,required this.current});@override Widget build(BuildContext context)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[for(final i in items)ChoiceChip(label:Text(i.title),selected:i.value==current,onSelected:(_)=>Navigator.pop(context,i.value))]),const SizedBox(height:12)])));}
class _ExportSheet extends StatefulWidget{const _ExportSheet();@override State<_ExportSheet> createState()=>_ExportSheetState();}
class _ExportSheetState extends State<_ExportSheet>{int resolution=1080;int fps=30;String quality='High';@override Widget build(BuildContext context)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Export',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:14),const Text('Resolution'),Wrap(children:[for(final r in [480,720,1080,1440,2160])ChoiceChip(label:Text(r==1440?'2K':'${r}p'),selected:resolution==r,onSelected:(_)=>setState(()=>resolution=r))]),const SizedBox(height:8),const Text('FPS'),Wrap(children:[for(final f in [24,25,30,60])ChoiceChip(label:Text('$f'),selected:fps==f,onSelected:(_)=>setState(()=>fps=f))]),const SizedBox(height:8),const Text('Quality'),Wrap(children:[for(final q in ['Low','Medium','High','Custom'])ChoiceChip(label:Text(q),selected:quality==q,onSelected:(_)=>setState(()=>quality=q))]),const SizedBox(height:14),SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>Navigator.pop(context,ExportOptions(resolution:resolution,fps:fps,quality:quality)),child:const Text('Start Export'))])));}
