import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../editor/editor_screen.dart';
import '../projects/projects_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();

  Future<void> _newProject() async {
    try {
      final files = await _picker.pickMultipleMedia();
      if (files.isEmpty || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorScreen(mediaFiles: files.map((e) => File(e.path)).toList())));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Media select failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06060B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('VideoMitra', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())))],
      ),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
        Container(
          height: 190,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFFFF2D75), Color(0xFF8B3CFF), Color(0xFF286BFF)])),
          child: InkWell(borderRadius: BorderRadius.circular(28), onTap: _newProject, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_circle_outline_rounded, size: 54), SizedBox(height: 12), Text('New Project', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), SizedBox(height: 6), Text('Video + image editor', style: TextStyle(color: Colors.white70)),
          ])),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: _QuickAction(icon: Icons.video_library_outlined, title: 'Import Video', onTap: _newProject)),
          const SizedBox(width: 12),
          Expanded(child: _QuickAction(icon: Icons.image_outlined, title: 'Import Image', onTap: _newProject)),
        ]),
        const SizedBox(height: 28),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('My Projects', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProjectsScreen())), child: const Text('See all')),
        ]),
        const SizedBox(height: 70),
        const Icon(Icons.movie_creation_outlined, size: 58, color: Colors.white24),
        const SizedBox(height: 12),
        const Center(child: Text('No projects yet\nTap New Project to start editing', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, height: 1.5))),
      ])),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon; final String title; final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.title, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFF12121A), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)), child: Row(children: [Icon(icon, color: const Color(0xFFFF2D75)), const SizedBox(width: 10), Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)))])));
}
