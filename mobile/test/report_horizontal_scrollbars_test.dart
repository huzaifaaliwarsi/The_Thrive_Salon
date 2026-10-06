import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salon_management_system/widgets/report_horizontal_scrollbars.dart';

void main() {
  testWidgets('horizontal handle stays at visible bottom while report scrolls vertically',
      (tester) async {
    final horizontal = ScrollController();
    final vertical = ScrollController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 300, height: 250,
        child: ReportHorizontalScrollbars(controller: horizontal,
          child: SingleChildScrollView(controller: vertical,
            child: SingleChildScrollView(controller: horizontal,
              scrollDirection: Axis.horizontal,
              child: const SizedBox(width: 1200, height: 1500),
            ),
          ),
        ),
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsOneWidget);
    final bounds = tester.getRect(find.byType(ReportHorizontalScrollbars));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset(30, bounds.bottom - 6));
    await pointer.down(Offset(30, bounds.bottom - 6));
    await pointer.moveBy(const Offset(60, 0));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(horizontal.offset, greaterThan(0));
    vertical.jumpTo(600);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ReportHorizontalScrollbars)), bounds);
    final initialOffset = horizontal.offset;
    final thumbX = horizontal.offset / 1200 * 300 + 20;
    await pointer.down(Offset(thumbX, bounds.bottom - 6));
    await pointer.moveBy(const Offset(-30, 0));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(horizontal.offset, lessThan(initialOffset));
    expect(vertical.offset, 600);
    expect(tester.takeException(), isNull);
    await pointer.removePointer();
    await tester.pumpWidget(const SizedBox());
    horizontal.dispose();
    vertical.dispose();
  });
}

