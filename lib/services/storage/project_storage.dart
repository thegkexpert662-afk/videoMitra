import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/editor_models.dart';

class ProjectStorage {
  static const _key = 'videomitra_projects_v1';

  Future<List<ProjectModel>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final result = <ProjectModel>[];
    for (final item in raw) {
      try {
        result.add(ProjectModel.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> save(ProjectModel project) async {
    final projects = await loadProjects();
    final index = projects.indexWhere((p) => p.id == project.id);
    project.updatedAt = DateTime.now();
    if (index >= 0) {
      projects[index] = project;
    } else {
      projects.insert(0, project);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, projects.map((p) => p.encode()).toList());
  }

  Future<void> delete(String id) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, projects.map((p) => p.encode()).toList());
  }

  Future<void> duplicate(String id) async {
    final projects = await loadProjects();
    final original = projects.firstWhere((p) => p.id == id);
    final copy = ProjectModel.fromJson(jsonDecode(original.encode()) as Map<String, dynamic>);
    copy.id = '${original.id}_copy_${DateTime.now().millisecondsSinceEpoch}';
    copy.name = '${original.name} Copy';
    await save(copy);
  }
}
