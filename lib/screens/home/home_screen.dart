import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../editor/editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _createNewProject() async {
    final List<XFile> selectedFiles =
    await _picker.pickMultipleMedia();

    if (selectedFiles.isEmpty) return;

    final List<File> videos = selectedFiles
        .map((file) => File(file.path))
        .toList();

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          mediaFiles: videos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030307),

      appBar: AppBar(
        backgroundColor: const Color(0xFF030307),
        elevation: 0,

        title: const Text(
          'VideoMitra',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),

        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),

      body: Column(
        children: [
          const SizedBox(height: 25),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              onTap: _createNewProject,
              borderRadius: BorderRadius.circular(22),

              child: Ink(
                height: 150,

                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF2D75),
                      Color(0xFF8B3CFF),
                      Color(0xFF286BFF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),

                child: const Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,

                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 50,
                      color: Colors.white,
                    ),

                    SizedBox(height: 12),

                    Text(
                      'New Project',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    SizedBox(height: 5),

                    Text(
                      'Create your next video',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: Text(
                'My Projects',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const Expanded(
            child: Center(
              child: Text(
                'No projects yet\nTap New Project to start editing',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}