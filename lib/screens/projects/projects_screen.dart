import 'package:flutter/material.dart';
import '../../models/editor_models.dart';
import '../../services/storage/project_storage.dart';
import '../editor/editor_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final storage = ProjectStorage();
  List<ProjectModel> projects = [];
  bool loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { projects = await storage.loadProjects(); if (mounted) setState(() => loading = false); }
  Future<void> _delete(ProjectModel p) async { await storage.delete(p.id); await _load(); }
  Future<void> _duplicate(ProjectModel p) async { await storage.duplicate(p.id); await _load(); }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF06060B),
    appBar: AppBar(title: const Text('Drafts & Projects')),
    body: loading ? const Center(child: CircularProgressIndicator()) : projects.isEmpty ? const Center(child: Text('No saved drafts yet', style: TextStyle(color: Colors.white54))) : ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: projects.length, itemBuilder: (_, i) { final p = projects[i];
        return Card(color: const Color(0xFF12121A), child: ListTile(
          leading: Container(width: 54, height: 54, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Color(0xFFFF2D75), Color(0xFF673CFF)])), child: const Icon(Icons.movie_outlined)),
          title: Text(p.name), subtitle: Text('${p.clips.length} clips • ${p.duration.inSeconds}s'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(mediaFiles: p.clips.map((e) => e.file).toList(), project: p))).then((_) => _load()),
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'delete') _delete(p); if (v == 'duplicate') _duplicate(p); }, itemBuilder: (_) => const [PopupMenuItem(value: 'duplicate', child: Text('Duplicate')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
        ));
      }),
  );
}
