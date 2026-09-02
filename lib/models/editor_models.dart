import 'dart:convert';
import 'dart:io';

enum MediaKind { video, image }
enum TrackType { video, audio, text, overlay, vfx, sticker }
enum CanvasRatio { original, r9x16, r16x9, r1x1, r4x3, r4x5 }
enum ElementKind { text, image, video, sticker, vfx }
enum FilterPreset { normal, bright, contrast, warm, cool, vintage, blackWhite, cinematic, dramatic }
enum EffectType { blur, glow, shake, flash, zoom, motion, chromatic, glitch, fade }
enum TransitionType { fade, dissolve, slide, zoom, wipe, blur, push }
enum TextAnimation { none, fade, slideUp, slideDown, pop, typewriter }

String enumName(Object value) => value.toString().split('.').last;
T enumFromName<T>(Iterable<T> values, String name, T fallback) { for (final value in values) { if (enumName(value as Object) == name) return value; } return fallback; }

class Keyframe {
  final Duration time; final double x, y, scale, rotation, opacity;
  const Keyframe({required this.time, required this.x, required this.y, required this.scale, required this.rotation, required this.opacity});
  Map<String,dynamic> toJson()=>{'time':time.inMilliseconds,'x':x,'y':y,'scale':scale,'rotation':rotation,'opacity':opacity};
  factory Keyframe.fromJson(Map<String,dynamic> j)=>Keyframe(time:Duration(milliseconds:j['time'] as int? ?? 0),x:(j['x'] as num?)?.toDouble()??.5,y:(j['y'] as num?)?.toDouble()??.5,scale:(j['scale'] as num?)?.toDouble()??1,rotation:(j['rotation'] as num?)?.toDouble()??0,opacity:(j['opacity'] as num?)?.toDouble()??1);
}

class CropTransform {
  double left,top,right,bottom,zoom,rotation,panX,panY;
  CropTransform({this.left=0,this.top=0,this.right=1,this.bottom=1,this.zoom=1,this.rotation=0,this.panX=0,this.panY=0});
  Map<String,dynamic> toJson()=>{'left':left,'top':top,'right':right,'bottom':bottom,'zoom':zoom,'rotation':rotation,'panX':panX,'panY':panY};
  factory CropTransform.fromJson(Map<String,dynamic> j)=>CropTransform(left:(j['left'] as num?)?.toDouble()??0,top:(j['top'] as num?)?.toDouble()??0,right:(j['right'] as num?)?.toDouble()??1,bottom:(j['bottom'] as num?)?.toDouble()??1,zoom:(j['zoom'] as num?)?.toDouble()??1,rotation:(j['rotation'] as num?)?.toDouble()??0,panX:(j['panX'] as num?)?.toDouble()??0,panY:(j['panY'] as num?)?.toDouble()??0);
}

class EditorClip {
  final String id; final File file; final MediaKind kind; Duration sourceDuration,start,end; double speed; bool muted; double volume; CropTransform transform; double? chromaSimilarity,chromaBlend; String? chromaColor; TransitionType transitionAfter; Duration transitionDuration;
  EditorClip({required this.id,required this.file,required this.kind,required this.sourceDuration,Duration? start,Duration? end,this.speed=1,this.muted=false,this.volume=1,CropTransform? transform,this.chromaSimilarity,this.chromaBlend,this.chromaColor,this.transitionAfter=TransitionType.fade,this.transitionDuration=const Duration(milliseconds:350)}):start=start??Duration.zero,end=end??sourceDuration,transform=transform??CropTransform();
  Duration get duration=>end-start;
  EditorClip copyWith({String? id,Duration? start,Duration? end,double? speed,bool? muted,double? volume,CropTransform? transform,double? chromaSimilarity,double? chromaBlend,String? chromaColor,TransitionType? transitionAfter,Duration? transitionDuration})=>EditorClip(id:id??this.id,file:file,kind:kind,sourceDuration:sourceDuration,start:start??this.start,end:end??this.end,speed:speed??this.speed,muted:muted??this.muted,volume:volume??this.volume,transform:transform??this.transform,chromaSimilarity:chromaSimilarity??this.chromaSimilarity,chromaBlend:chromaBlend??this.chromaBlend,chromaColor:chromaColor??this.chromaColor,transitionAfter:transitionAfter??this.transitionAfter,transitionDuration:transitionDuration??this.transitionDuration);
  Map<String,dynamic> toJson()=>{'id':id,'path':file.path,'kind':enumName(kind),'sourceDuration':sourceDuration.inMilliseconds,'start':start.inMilliseconds,'end':end.inMilliseconds,'speed':speed,'muted':muted,'volume':volume,'transform':transform.toJson(),'chromaSimilarity':chromaSimilarity,'chromaBlend':chromaBlend,'chromaColor':chromaColor,'transitionAfter':enumName(transitionAfter),'transitionDuration':transitionDuration.inMilliseconds};
  factory EditorClip.fromJson(Map<String,dynamic> j){final d=Duration(milliseconds:j['sourceDuration'] as int? ?? 0);return EditorClip(id:j['id'] as String,file:File(j['path'] as String),kind:enumFromName(MediaKind.values,j['kind'] as String? ?? 'video',MediaKind.video),sourceDuration:d,start:Duration(milliseconds:j['start'] as int? ?? 0),end:Duration(milliseconds:j['end'] as int? ?? d.inMilliseconds),speed:(j['speed'] as num?)?.toDouble()??1,muted:j['muted'] as bool? ?? false,volume:(j['volume'] as num?)?.toDouble()??1,transform:CropTransform.fromJson(Map<String,dynamic>.from(j['transform'] as Map? ?? const {})),chromaSimilarity:(j['chromaSimilarity'] as num?)?.toDouble(),chromaBlend:(j['chromaBlend'] as num?)?.toDouble(),chromaColor:j['chromaColor'] as String?,transitionAfter:enumFromName(TransitionType.values,j['transitionAfter'] as String? ?? 'fade',TransitionType.fade),transitionDuration:Duration(milliseconds:j['transitionDuration'] as int? ?? 350));}
}

class EditorElement {
  final String id; final ElementKind kind; String text; String? assetPath; Duration start,end; double x,y,scale,rotation,opacity; int layer; double intensity; String color,backgroundColor,outlineColor,fontFamily; double fontSize; bool bold,italic,outline,shadow; double outlineWidth; TextAnimation animation; List<Keyframe> keyframes;
  EditorElement({required this.id,required this.kind,this.text='',this.assetPath,this.start=Duration.zero,this.end=const Duration(seconds:10),this.x=.5,this.y=.5,this.scale=1,this.rotation=0,this.opacity=1,this.layer=0,this.intensity=.5,this.color='#FFFFFF',this.backgroundColor='#00000000',this.outlineColor='#000000',this.fontFamily='sans',this.fontSize=32,this.bold=false,this.italic=false,this.outline=false,this.shadow=false,this.outlineWidth=2,this.animation=TextAnimation.none,List<Keyframe>? keyframes}):keyframes=keyframes??<Keyframe>[];
  EditorElement copy()=>EditorElement(id:id,kind:kind,text:text,assetPath:assetPath,start:start,end:end,x:x,y:y,scale:scale,rotation:rotation,opacity:opacity,layer:layer,intensity:intensity,color:color,backgroundColor:backgroundColor,outlineColor:outlineColor,fontFamily:fontFamily,fontSize:fontSize,bold:bold,italic:italic,outline:outline,shadow:shadow,outlineWidth:outlineWidth,animation:animation,keyframes:List<Keyframe>.from(keyframes));
  Map<String,dynamic> toJson()=>{'id':id,'kind':enumName(kind),'text':text,'assetPath':assetPath,'start':start.inMilliseconds,'end':end.inMilliseconds,'x':x,'y':y,'scale':scale,'rotation':rotation,'opacity':opacity,'layer':layer,'intensity':intensity,'color':color,'backgroundColor':backgroundColor,'outlineColor':outlineColor,'fontFamily':fontFamily,'fontSize':fontSize,'bold':bold,'italic':italic,'outline':outline,'shadow':shadow,'outlineWidth':outlineWidth,'animation':enumName(animation),'keyframes':keyframes.map((e)=>e.toJson()).toList()};
  factory EditorElement.fromJson(Map<String,dynamic> j)=>EditorElement(id:j['id'] as String,kind:enumFromName(ElementKind.values,j['kind'] as String? ?? 'text',ElementKind.text),text:j['text'] as String? ?? '',assetPath:j['assetPath'] as String?,start:Duration(milliseconds:j['start'] as int? ?? 0),end:Duration(milliseconds:j['end'] as int? ?? 10000),x:(j['x'] as num?)?.toDouble()??.5,y:(j['y'] as num?)?.toDouble()??.5,scale:(j['scale'] as num?)?.toDouble()??1,rotation:(j['rotation'] as num?)?.toDouble()??0,opacity:(j['opacity'] as num?)?.toDouble()??1,layer:j['layer'] as int? ?? 0,intensity:(j['intensity'] as num?)?.toDouble()??.5,color:j['color'] as String? ?? '#FFFFFF',backgroundColor:j['backgroundColor'] as String? ?? '#00000000',outlineColor:j['outlineColor'] as String? ?? '#000000',fontFamily:j['fontFamily'] as String? ?? 'sans',fontSize:(j['fontSize'] as num?)?.toDouble()??32,bold:j['bold'] as bool? ?? false,italic:j['italic'] as bool? ?? false,outline:j['outline'] as bool? ?? false,shadow:j['shadow'] as bool? ?? false,outlineWidth:(j['outlineWidth'] as num?)?.toDouble()??2,animation:enumFromName(TextAnimation.values,j['animation'] as String? ?? 'none',TextAnimation.none),keyframes:(j['keyframes'] as List<dynamic>? ?? const[]).map((e)=>Keyframe.fromJson(Map<String,dynamic>.from(e as Map))).toList());
}

class AudioTrack {
  final String id; final File file; Duration start,end,position; double volume; bool muted; Duration fadeIn,fadeOut;
  AudioTrack({required this.id,required this.file,required this.start,required this.end,this.position=Duration.zero,this.volume=1,this.muted=false,this.fadeIn=Duration.zero,this.fadeOut=Duration.zero});
  Map<String,dynamic> toJson()=>{'id':id,'path':file.path,'start':start.inMilliseconds,'end':end.inMilliseconds,'position':position.inMilliseconds,'volume':volume,'muted':muted,'fadeIn':fadeIn.inMilliseconds,'fadeOut':fadeOut.inMilliseconds};
  factory AudioTrack.fromJson(Map<String,dynamic> j)=>AudioTrack(id:j['id'] as String,file:File(j['path'] as String),start:Duration(milliseconds:j['start'] as int? ?? 0),end:Duration(milliseconds:j['end'] as int? ?? 0),position:Duration(milliseconds:j['position'] as int? ?? 0),volume:(j['volume'] as num?)?.toDouble()??1,muted:j['muted'] as bool? ?? false,fadeIn:Duration(milliseconds:j['fadeIn'] as int? ?? 0),fadeOut:Duration(milliseconds:j['fadeOut'] as int? ?? 0));
}

class ProjectModel {
  String id,name; CanvasRatio ratio; List<EditorClip> clips; List<AudioTrack> audioTracks; List<EditorElement> elements; FilterPreset filter; double filterIntensity; Map<String,double> adjustments; String? backgroundColor,chromaBackgroundPath; DateTime updatedAt;
  ProjectModel({required this.id,required this.name,required this.clips,this.audioTracks=const[],this.elements=const[],this.ratio=CanvasRatio.original,this.filter=FilterPreset.normal,this.filterIntensity=1,Map<String,double>? adjustments,this.backgroundColor,this.chromaBackgroundPath,DateTime? updatedAt}):adjustments=adjustments??<String,double>{},updatedAt=updatedAt??DateTime.now();
  Duration get duration=>clips.fold(Duration.zero,(s,c)=>s+c.duration);
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'ratio':enumName(ratio),'clips':clips.map((e)=>e.toJson()).toList(),'audioTracks':audioTracks.map((e)=>e.toJson()).toList(),'elements':elements.map((e)=>e.toJson()).toList(),'filter':enumName(filter),'filterIntensity':filterIntensity,'adjustments':adjustments,'backgroundColor':backgroundColor,'chromaBackgroundPath':chromaBackgroundPath,'updatedAt':updatedAt.toIso8601String()};
  String encode()=>jsonEncode(toJson());
  factory ProjectModel.fromJson(Map<String,dynamic> j)=>ProjectModel(id:j['id'] as String,name:j['name'] as String? ?? 'VideoMitra Project',ratio:enumFromName(CanvasRatio.values,j['ratio'] as String? ?? 'original',CanvasRatio.original),clips:(j['clips'] as List<dynamic>? ?? const[]).map((e)=>EditorClip.fromJson(Map<String,dynamic>.from(e as Map))).toList(),audioTracks:(j['audioTracks'] as List<dynamic>? ?? const[]).map((e)=>AudioTrack.fromJson(Map<String,dynamic>.from(e as Map))).toList(),elements:(j['elements'] as List<dynamic>? ?? const[]).map((e)=>EditorElement.fromJson(Map<String,dynamic>.from(e as Map))).toList(),filter:enumFromName(FilterPreset.values,j['filter'] as String? ?? 'normal',FilterPreset.normal),filterIntensity:(j['filterIntensity'] as num?)?.toDouble()??1,adjustments:Map<String,double>.from(j['adjustments'] as Map? ?? const{}),backgroundColor:j['backgroundColor'] as String?,chromaBackgroundPath:j['chromaBackgroundPath'] as String?,updatedAt:DateTime.tryParse(j['updatedAt'] as String? ?? '')??DateTime.now());
}
