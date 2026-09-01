import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trek/design/widgets/skeleton_box.dart';

void main() {
  testWidgets('SkeletonBox renders at the given size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SkeletonBox(width: 100, height: 20)),
      ),
    );

    final size = tester.getSize(find.byType(SkeletonBox));
    expect(size.width, 100);
    expect(size.height, 20);
  });

  testWidgets('SkeletonBox pulses opacity over time without error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkeletonBox())),
    );

    await tester.pump(const Duration(milliseconds: 450));
    final opacity1 = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    await tester.pump(const Duration(milliseconds: 450));
    final opacity2 = tester.widget<Opacity>(find.byType(Opacity)).opacity;

    expect(opacity1, isNot(opacity2));
  });

  testWidgets('SkeletonListTile lays out an avatar and two text lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkeletonListTile())),
    );

    expect(find.byType(SkeletonBox), findsNWidgets(3));
  });
}
