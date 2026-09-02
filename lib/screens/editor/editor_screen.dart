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
import '../../services/video/video_processor.dart';

class EditorScreen extends StatefulWidget {
  final List<File> mediaFiles;
  final ProjectModel? project;
  const EditorScreen({super.key, required this.mediaFiles, this.project});
  @override State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController editor;
  final _picker = ImagePicker();
  VideoPlayerController? _player;
  Timer? _autosave;
  bool loading = true;
  bool exporting = false;
  String? error;
  Duration localPosition = Duration.zero;
  final _processor = VideoProcessor();

  @override
  void initState() {
    super.initState();
    editor = EditorController();
    if (widget.project != null) {
      editor.project = widget.project!;
      editor.dirty = false;
    } else {
      editor.initialize(widget.mediaFiles);
    }
    editor.addListener(_editorChanged);
    _openClip(0);
    _autosave = Timer.periodic(const Duration(seconds: 12), (_) { if (editor.dirty) editor.save(); });
  }

  void _editorChanged() {
    if (mounted) setState(() {});
    final index = editor.clipAt(editor.playhead);
    if (index >= 0 && index != editor.selectedClip) _openClip(index, autoSeek: true);
  }

  Future<void> _openClip(int index, {bool autoSeek = false}) async {
    if (index < 0 || index >= editor.project.clips.length) { if (mounted) setState(() => loading = false); return; }
    final clip = editor.project.clips[index];
    await _player?.dispose();
    if (mounted) setState(() { loading = true; error = null; });
    try {
      if (clip.kind == MediaKind.image) {
        editor.selectedClip = index;
        if (mounted) setState(() => loading = false);
        return;
      }
      final p = VideoPlayerController.file(clip.file);
      _player = p;
      await p.initialize();
      if (clip.sourceDuration == Duration.zero) editor.updateClipDuration(index, p.value.duration);
      p.addListener(_playerTick);
      editor.selectedClip = index;
      if (autoSeek) {
        final globalStart = editor.clipStart(index);
        final local = editor.playhead - globalStart;
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
    final p = _player;
    if (p == null || !p.value.isInitialized || !mounted) return;
    final clip = editor.project.clips.isEmpty ? null : editor.project.clips[editor.selectedClip];
    if (clip == null) return;
    final sourcePos = p.value.position;
    final sourceEnd = clip.end;
    final localMs = ((sourcePos - clip.start).inMilliseconds / clip.speed).round().clamp(0, clip.duration.inMilliseconds);
    editor.setPlayhead(editor.clipStart(editor.selectedClip) + Duration(milliseconds: localMs));
    if (sourcePos >= sourceEnd && p.value.isPlaying) {
      if (editor.selectedClip + 1 < editor.project.clips.length) {
        _openClip(editor.selectedClip + 1);
        Future.microtask(() => _player?.play());
      } else {
        p.pause();
      }
    }
    if (mounted) setState(() { localPosition = sourcePos; });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    editor.removeListener(_editorChanged);
    editor.save();
    _player?.dispose();
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
      case CanvasRatio.original:
        final p = _player;
        return p != null && p.value.isInitialized ? p.value.aspectRatio : 16 / 9;
    }
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
    } else if (_player?.value.isInitialized == true) {
      media = FittedBox(fit: BoxFit.contain, child: SizedBox(width: _player!.value.size.width, height: _player!.value.size.height, child: VideoPlayer(_player!)));
    } else {
      media = const Center(child: CircularProgressIndicator());
    }

    media = _previewFilter(media);
    final active = editor.project.elements.where((e) => editor.playhead >= e.start && editor.playhead <= e.end).toList()..sort((a, b) => a.layer.compareTo(b.layer));
    return Center(child: AspectRatio(aspectRatio: _ratio, child: ClipRect(child: Stack(fit: StackFit.expand, children: [
      Container(color: _parseColor(editor.project.backgroundColor) ?? Colors.black),
      media,
      for (final e in active) _elementPreview(e),
      if (exporting) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
    ]))));
  }

  Widget _previewFilter(Widget child) {
    final f = editor.project.filter;
    final a = editor.project.adjustments;
    final b = (a['brightness'] ?? 0) / 100;
    final c = 1 + (a['contrast'] ?? 0) / 100;
    final s = 1 + (a['saturation'] ?? 0) / 100;
    if (f == FilterPreset.blackWhite) return ColorFiltered(colorFilter: const ColorFilter.matrix([.2126,.7152,.0722,0,0,.2126,.7152,.0722,0,0,.2126,.7152,.0722,0,0,0,0,0,1,0]), child: child);
    if (f == FilterPreset.bright || b != 0 || c != 1 || s != 1) return ColorFiltered(colorFilter: ColorFilter.matrix(_matrix(b, c, s)), child: child);
    return child;
  }

  List<double> _matrix(double brightness, double contrast, double saturation) {
    final t = (1 - contrast) * 128 + brightness * 255;
    final r = .213 + .787 * saturation, g = .715 - .715 * saturation, bl = .072 - .072 * saturation;
    final rg = -.213 * saturation, gg = .285 + .715 * saturation, bg = -.072 * saturation;
    return [contrast*r, contrast*g, contrast*bl,0,t, contrast*rg,contrast*gg,contrast*bl,0,t, contrast*rg,contrast*g,contrast*(.928*saturation+.072),0,t,0,0,0,1,0];
  }

  Widget _elementPreview(EditorElement e) {
    Widget child;
    if (e.kind == ElementKind.text) {
      child = Text(e.text, textAlign: TextAlign.center, style: TextStyle(color: _parseColor(e.color) ?? Colors.white, fontSize: e.fontSize * e.scale, fontWeight: e.bold ? FontWeight.bold : FontWeight.normal, fontStyle: e.italic ? FontStyle.italic : FontStyle.normal, shadows: e.shadow ? const [Shadow(blurRadius: 5, offset: Offset(2,2))] : null));
    } else if (e.assetPath != null) {
      child = Image.file(File(e.assetPath!), fit: BoxFit.contain);
    } else {
      child = Icon(e.kind == ElementKind.sticker ? Icons.emoji_emotions : Icons.auto_awesome, size: 70 * e.scale);
    }
    return Positioned(left: e.x * MediaQuery.sizeOf(context).width * .85 - 60, top: e.y * MediaQuery.sizeOf(context).height * .45 - 30, child: Opacity(opacity: e.opacity.clamp(0,1), child: Transform.rotate(angle: e.rotation, child: child)));
  }

  Color? _parseColor(String? value) {
    if (value == null) return null;
    final hex = value.replaceAll('#','');
    if (hex.length != 6) return null;
    return Color(int.parse('FF$hex', radix: 16));
  }

  Future<void> _showCanvas() async {
    final value = await showModalBottomSheet<CanvasRatio>(context: context, backgroundColor: const Color(0xFF111118), builder: (_) => _ChoiceSheet(title: 'Canvas / Ratio', items: const [
      _Choice('Original', CanvasRatio.original), _Choice('9:16', CanvasRatio.r9x16), _Choice('16:9', CanvasRatio.r16x9), _Choice('1:1', CanvasRatio.r1x1), _Choice('4:3', CanvasRatio.r4x3), _Choice('4:5', CanvasRatio.r4x5),
    ], current: editor.project.ratio));
    if (value != null) editor.setCanvas(value);
  }

  Future<void> _trim() async {
    if (editor.project.clips.isEmpty) return;
    final clip = editor.project.clips[editor.selectedClip];
    if (clip.kind == MediaKind.image) { _snack('Image duration is fixed at 5 seconds for now'); return; }
    var start = clip.start.inMilliseconds.toDouble(); var end = clip.end.inMilliseconds.toDouble();
    final result = await showModalBottomSheet<RangeValues>(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF111118), builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(padding: const EdgeInsets.fromLTRB(18,20,18,30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Trim', style: TextStyle(fontSize: 20,fontWeight: FontWeight.bold)), const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Start ${_time(Duration(milliseconds:start.round()))}'), Text('End ${_time(Duration(milliseconds:end.round()))}')]), RangeSlider(min:0,max:clip.sourceDuration.inMilliseconds.toDouble(),values:RangeValues(start,end),onChanged:(v){set((){start=v.start;end=v.end;});_player?.seekTo(Duration(milliseconds:v.start.round()));}), const SizedBox(height:8), Text('Selected ${_time(Duration(milliseconds:(end-start).round()))}'), const SizedBox(height:12), FilledButton(onPressed:()=>Navigator.pop(ctx,RangeValues(start,end)),child:const Text('Apply'))]))));
    if (result == null) return;
    editor.trimSelected(Duration(milliseconds: result.start.round()), Duration(milliseconds: result.end.round()));
    await _openClip(editor.selectedClip);
    _snack('Trim applied to timeline');
  }

  void _split() { editor.splitAtPlayhead(); _snack('Clip split at playhead'); }
  void _delete() { editor.deleteSelectedClip(); _openClip(editor.selectedClip); _snack('Selected clip deleted'); }

  Future<void> _addAudio() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (picked == null || picked.files.single.path == null) return;
    final file = File(picked.files.single.path!);
    editor.addAudio(AudioTrack(id:'audio_${DateTime.now().millisecondsSinceEpoch}',file:file,start:Duration.zero,end:const Duration(minutes:30)));
    _snack('Audio track added');
  }

  Future<void> _addText() async {
    final controller = TextEditingController(text: 'Your text');
    final text = await showDialog<String>(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xFF17171F), title: const Text('Add Text'), content: TextField(controller: controller, autofocus:true, maxLines:3, decoration: const InputDecoration(hintText:'Type your text')), actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,controller.text),child:const Text('Add'))]));
    controller.dispose();
    if (text != null) { editor.addText(text); _snack('Text layer added'); }
  }

  Future<void> _filters() async {
    final value = await showModalBottomSheet<FilterPreset>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>_ChoiceSheet(title:'Filters',items:const [
      _Choice('Normal',FilterPreset.normal),_Choice('Bright',FilterPreset.bright),_Choice('Contrast',FilterPreset.contrast),_Choice('Warm',FilterPreset.warm),_Choice('Cool',FilterPreset.cool),_Choice('Vintage',FilterPreset.vintage),_Choice('B&W',FilterPreset.blackWhite),_Choice('Cinematic',FilterPreset.cinematic),_Choice('Dramatic',FilterPreset.dramatic)
    ],current:editor.project.filter));
    if(value!=null) editor.setFilter(value, editor.project.filterIntensity);
  }

  Future<void> _adjust() async {
    final keys = ['brightness','contrast','saturation','exposure','temperature','tint','highlights','shadows','sharpness','fade','vignette'];
    await showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:const Color(0xFF111118),builder:(_)=>StatefulBuilder(builder:(ctx,set)=>Padding(padding:const EdgeInsets.fromLTRB(18,18,18,28),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Adjust',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),for(final k in keys) Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(k[0].toUpperCase()+k.substring(1)),Text('${(editor.project.adjustments[k]??0).round()}')]),Slider(min:-100,max:100,value:(editor.project.adjustments[k]??0).clamp(-100,100),onChanged:(v){editor.project.adjustments[k]=v;set((){});editor.notifyListeners();}),])])))));
  }

  Future<void> _speed() async {
    const values=[.25,.5,.75,1,1.25,1.5,2];
    final v=await showModalBottomSheet<double>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>Wrap(children:[for(final s in values) SizedBox(width:MediaQuery.sizeOf(context).width/3,child:ListTile(title:Text('${s}x',textAlign:TextAlign.center),onTap:()=>Navigator.pop(context,s))) ]));
    if(v!=null){editor.setSpeed(v);_snack('Speed ${v}x applied');}
  }

  Future<void> _overlay({bool sticker=false}) async {
    if(sticker){
      final choice=await showModalBottomSheet<String>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>Wrap(children:[for(final s in ['😀','🔥','⭐','❤️','🎉','⚡','✨','🎬']) SizedBox(width:MediaQuery.sizeOf(context).width/4,child:ListTile(title:Text(s,style:const TextStyle(fontSize:30),textAlign:TextAlign.center),onTap:()=>Navigator.pop(context,s)))]));
      if(choice!=null) editor.addElement(EditorElement(id:'sticker_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.sticker,text:choice,start:editor.playhead,end:editor.playhead+const Duration(seconds:4)));
      return;
    }
    final file=await _picker.pickImage(source:ImageSource.gallery);
    if(file==null)return;
    editor.addElement(EditorElement(id:'overlay_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.image,assetPath:file.path,start:editor.playhead,end:editor.playhead+const Duration(seconds:5)));
    _snack('Image overlay added');
  }

  Future<void> _vfx() async {
    final name=await showModalBottomSheet<String>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>Wrap(children:[for(final e in ['Smoke','Fire','Sparks','Lightning','Explosion','Dust','Fog','Glow','Energy']) ListTile(leading:const Icon(Icons.auto_awesome),title:Text(e),onTap:()=>Navigator.pop(context,e))]));
    if(name!=null) editor.addElement(EditorElement(id:'vfx_${DateTime.now().millisecondsSinceEpoch}',kind:ElementKind.vfx,text:name,start:editor.playhead,end:editor.playhead+const Duration(seconds:3),intensity:.7));
  }

  Future<void> _keyframe() async { editor.addKeyframe(); _snack('Keyframe added at ${_time(editor.playhead)}'); }

  Future<void> _export() async {
    if(editor.project.clips.isEmpty)return;
    final opts=await showModalBottomSheet<ExportOptions>(context:context,backgroundColor:const Color(0xFF111118),builder:(_)=>_ExportSheet());
    if(opts==null)return;
    setState(()=>exporting=true);
    try{
      final file=await ExportService().export(editor.project,opts);
      if(!mounted)return;
      setState(()=>exporting=false);
      await showDialog(context:context,builder:(_)=>AlertDialog(backgroundColor:const Color(0xFF17171F),title:const Text('Export complete'),content:const Text('Video exported successfully.'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close')),FilledButton(onPressed:()async{await Share.shareXFiles([XFile(file.path)],text:'Created with VideoMitra');if(mounted)Navigator.pop(context);},child:const Text('Share'))]));
    }catch(e){if(mounted){setState(()=>exporting=false);_snack('Export failed: $e');}}
  }

  void _snack(String text)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text),behavior:SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context){
    final total=editor.project.duration;
    final maxMs=total.inMilliseconds.toDouble();
    return Scaffold(backgroundColor:const Color(0xFF050509),appBar:AppBar(backgroundColor:const Color(0xFF09090F),title:const Text('VideoMitra',style:TextStyle(fontWeight:FontWeight.w800)),leading:IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>Navigator.pop(context)),actions:[IconButton(tooltip:'Undo',onPressed:editor.undo,icon:const Icon(Icons.undo)),IconButton(tooltip:'Redo',onPressed:editor.redo,icon:const Icon(Icons.redo)),TextButton(onPressed:_showCanvas,child:const Text('Canvas')),TextButton(onPressed:_export,child:const Text('Export'))]),body:SafeArea(child:Column(children:[Expanded(flex:6,child:Padding(padding:const EdgeInsets.all(10),child:_preview())),Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(_time(editor.playhead)),IconButton(onPressed:(){final p=_player;if(p==null)return;if(p.value.isPlaying){p.pause();}else{p.play();}},icon:Icon(_player?.value.isPlaying==true?Icons.pause_circle_filled:Icons.play_circle_fill,size:38)),Text(_time(total))])),
      Expanded(flex:4,child:Column(children:[_timeline(maxMs),const SizedBox(height:6),SizedBox(height:92,child:ListView.separated(padding:const EdgeInsets.symmetric(horizontal:10),scrollDirection:Axis.horizontal,itemCount:editor.project.clips.length,separatorBuilder:(_,__)=>const SizedBox(width:6),itemBuilder:(_,i)=>_clipTile(i))),const Divider(height:1),SizedBox(height:92,child:ListView.separated(padding:const EdgeInsets.fromLTRB(8,10,8,10),scrollDirection:Axis.horizontal,itemCount:_tools.length,separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(_,i){final t=_tools[i];return _Tool(icon:t.$1,label:t.$2,onTap:t.$3);}))]))])));
  }

  Widget _timeline(double maxMs){
    final value=maxMs<=0?0:editor.playhead.inMilliseconds.clamp(0,maxMs).toDouble();
    return Column(children:[Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Slider(min:0,max:maxMs<=0?1:maxMs,value:value,onChanged:(v){editor.setPlayhead(Duration(milliseconds:v.round()));final i=editor.clipAt(editor.playhead);if(i>=0&&i!=editor.selectedClip)_openClip(i,autoSeek:true);else{final c=editor.project.clips.isEmpty?null:editor.project.clips[editor.selectedClip];if(c!=null&&_player!=null)_player!.seekTo(c.start+Duration(milliseconds:((editor.playhead-editor.clipStart(editor.selectedClip)).inMilliseconds*c.speed).round()));}})),Row(children:[const SizedBox(width:12),Text('VIDEO',style:TextStyle(fontSize:10,color:Colors.white54)),const SizedBox(width:8),Expanded(child:Container(height:22,decoration:BoxDecoration(color:const Color(0xFF1D1D27),borderRadius:BorderRadius.circular(5)),child:Row(children:[for(final c in editor.project.clips)Expanded(child:Container(margin:const EdgeInsets.all(2),decoration:BoxDecoration(color:c.kind==MediaKind.image?const Color(0xFF2B7A78):const Color(0xFF6D2F75),borderRadius:BorderRadius.circular(4)),child:const SizedBox()))])))]),
      _trackRow('AUDIO',Colors.blueGrey,editor.project.audioTracks.length),_trackRow('TEXT',Colors.pink,editor.project.elements.where((e)=>e.kind==ElementKind.text).length),_trackRow('OVERLAY',Colors.amber,editor.project.elements.where((e)=>e.kind==ElementKind.image||e.kind==ElementKind.video).length),_trackRow('VFX',Colors.deepPurple,editor.project.elements.where((e)=>e.kind==ElementKind.vfx||e.kind==ElementKind.sticker).length)]);
  }
  Widget _trackRow(String name,Color color,int count)=>Padding(padding:const EdgeInsets.fromLTRB(12,3,12,0),child:Row(children:[SizedBox(width:46,child:Text(name,style:const TextStyle(fontSize:9,color:Colors.white54))),Expanded(child:Container(height:14,decoration:BoxDecoration(color:Colors.white.withOpacity(.04),borderRadius:BorderRadius.circular(4)),child:count==0?null:Align(alignment:Alignment.centerLeft,child:FractionallySizedBox(width:(count/4).clamp(.08,1).toDouble(),child:Container(decoration:BoxDecoration(color:color.withOpacity(.55),borderRadius:BorderRadius.circular(4)))))))]));

  List<(IconData,String,VoidCallback)> get _tools=>[(Icons.content_cut_rounded,'Trim',_trim),(Icons.call_split_rounded,'Split',_split),(Icons.delete_outline,'Delete',_delete),(Icons.music_note,'Audio',_addAudio),(Icons.text_fields,'Text',_addText),(Icons.filter_alt,'Filters',_filters),(Icons.tune,'Adjust',_adjust),(Icons.speed,'Speed',_speed),(Icons.layers,'Overlay',()=>_overlay()),(Icons.emoji_emotions,'Sticker',()=>_overlay(sticker:true)),(Icons.auto_awesome,'VFX',_vfx),(Icons.key,'Keyframe',_keyframe),(Icons.crop,'Crop',_showCanvas),(Icons.volume_off,'Mute',(){editor.toggleMuteOriginal();_snack('Original audio mute toggled');})];

  Widget _clipTile(int i){final c=editor.project.clips[i];final selected=i==editor.selectedClip;return GestureDetector(onTap:(){editor.selectClip(i);_openClip(i);},child:AnimatedContainer(duration:const Duration(milliseconds:160),width:150,decoration:BoxDecoration(color:selected?const Color(0xFF321525):const Color(0xFF171720),borderRadius:BorderRadius.circular(8),border:Border.all(color:selected?const Color(0xFFFF2D75):Colors.white10,width:selected?2:1)),padding:const EdgeInsets.all(7),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:ClipThumbnail(file:c.file,isImage:c.kind==MediaKind.image)),const SizedBox(height:4),Text('${_time(c.duration)} • ${c.speed}x',style:const TextStyle(fontSize:10,color:Colors.white60))]));}
}

class ClipThumbnail extends StatelessWidget{final File file;final bool isImage;const ClipThumbnail({super.key,required this.file,required this.isImage});@override Widget build(BuildContext context)=>ClipRRect(borderRadius:BorderRadius.circular(5),child:isImage?Image.file(file,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const ColoredBox(color:Colors.black,child:Icon(Icons.broken_image))):Container(color:const Color(0xFF252530),child:const Center(child:Icon(Icons.play_arrow_rounded,color:Colors.white54))));}

class _Tool extends StatelessWidget{final IconData icon;final String label;final VoidCallback onTap;const _Tool({required this.icon,required this.label,required this.onTap});@override Widget build(BuildContext context)=>InkWell(onTap:onTap,borderRadius:BorderRadius.circular(12),child:Container(width:72,padding:const EdgeInsets.symmetric(vertical:9),decoration:BoxDecoration(color:const Color(0xFF12121A),borderRadius:BorderRadius.circular(12),border:Border.all(color:Colors.white10)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:23,color:const Color(0xFFFF2D75)),const SizedBox(height:5),Text(label,style:const TextStyle(fontSize:10),overflow:TextOverflow.ellipsis)])));}

class _Choice<T>{final String title;final T value;const _Choice(this.title,this.value);}
class _ChoiceSheet<T> extends StatelessWidget{final String title;final List<_Choice<T>> items;final T current;const _ChoiceSheet({required this.title,required this.items,required this.current});@override Widget build(BuildContext context)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[for(final item in items)ChoiceChip(label:Text(item.title),selected:item.value==current,onSelected:(_)=>Navigator.pop(context,item.value))]),const SizedBox(height:12)])));}

class _ExportSheet extends StatefulWidget{const _ExportSheet();@override State<_ExportSheet> createState()=>_ExportSheetState();}
class _ExportSheetState extends State<_ExportSheet>{int resolution=1080;int fps=30;String quality='High';@override Widget build(BuildContext context)=>SafeArea(child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Export',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:16),const Text('Resolution'),Wrap(children:[for(final r in [480,720,1080,1440,2160])ChoiceChip(label:Text(r==1440?'2K':'${r}p'),selected:resolution==r,onSelected:(_)=>setState(()=>resolution=r))]),const SizedBox(height:8),const Text('FPS'),Wrap(children:[for(final f in [24,25,30,60])ChoiceChip(label:Text('$f'),selected:fps==f,onSelected:(_)=>setState(()=>fps=f))]),const SizedBox(height:8),const Text('Quality'),Wrap(children:[for(final q in ['Low','Medium','High','Custom'])ChoiceChip(label:Text(q),selected:quality==q,onSelected:(_)=>setState(()=>quality=q))]),const SizedBox(height:16),SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>Navigator.pop(context,ExportOptions(resolution:resolution,fps:fps,quality:quality)),child:const Text('Start Export'))])));}
