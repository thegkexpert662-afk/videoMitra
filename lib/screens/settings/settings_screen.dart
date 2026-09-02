import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    backgroundColor: const Color(0xFF06060B),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      _SettingTile(icon: Icons.high_quality_outlined, title: 'Export quality', subtitle: 'Choose resolution, FPS and quality'),
      _SettingTile(icon: Icons.cleaning_services_outlined, title: 'Temporary files', subtitle: 'Temporary render files are cleaned automatically'),
      _SettingTile(icon: Icons.info_outline, title: 'About VideoMitra', subtitle: 'Your own video editor'),
    ]),
  );
}

class _SettingTile extends StatelessWidget {
  final IconData icon; final String title; final String subtitle;
  const _SettingTile({required this.icon, required this.title, required this.subtitle});
  @override Widget build(BuildContext context) => Card(color: const Color(0xFF12121A), child: ListTile(leading: Icon(icon, color: const Color(0xFFFF2D75)), title: Text(title), subtitle: Text(subtitle)));
}
