import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:salon_management_system/view_models/pos_view_model.dart';
import 'package:salon_management_system/widgets/pos_search_field.dart';

void main() {
  testWidgets('search preserves input identity, focus, cursor and composing', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: POSSearchField())),
    ));
    final finder = find.byType(TextField);
    await tester.tap(finder);
    await tester.pump();
    final element = tester.element(finder);
    final field = tester.widget<TextField>(finder);
    for (final text in ['h', 'ha', 'hai', 'hair']) {
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ));
      await tester.pump();
      expect(tester.element(finder), same(element));
      expect(tester.widget<TextField>(finder).controller, same(field.controller));
      expect(tester.widget<TextField>(finder).focusNode, same(field.focusNode));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(container.read(posProvider).searchQuery, text);
    }
    const edit = TextEditingValue(
      text: 'haXir',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 2, end: 3),
    );
    tester.testTextInput.updateEditingValue(edit);
    await tester.pump();
    expect(field.controller!.value, edit);
    container.read(posProvider.notifier).setSearch('abcde');
    await tester.pump();
    expect(field.controller!.selection.baseOffset, 3);
    expect(field.controller!.text, 'abcde');
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(field.controller!.text, isEmpty);
    expect(container.read(posProvider).searchQuery, isEmpty);
    expect(field.controller!.selection.baseOffset, 0);
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
