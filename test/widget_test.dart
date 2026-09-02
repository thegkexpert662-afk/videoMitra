import 'package:flutter_test/flutter_test.dart';
import 'package:videomitra/main.dart';

void main() {
  testWidgets('VideoMitra app starts', (tester) async {
    await tester.pumpWidget(const VideoMitraApp());
    expect(find.byType(VideoMitraApp), findsOneWidget);
  });
}
