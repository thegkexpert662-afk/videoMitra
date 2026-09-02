import 'package:flutter/material.dart';

String friendlyError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('permission')) return 'Permission denied. Please allow media access in Android settings.';
  if (text.contains('space') || text.contains('storage')) return 'Insufficient storage. Free some space and try again.';
  if (text.contains('unsupported')) return 'Unsupported media format.';
  if (text.contains('not found')) return 'The selected media file is no longer available.';
  if (text.contains('export')) return 'Export failed. Try a lower resolution or shorter project.';
  return 'Something went wrong. Please try again.';
}

void showVideoMitraError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error)), behavior: SnackBarBehavior.floating));
}
