import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../view_models/pos_view_model.dart';

class POSSearchField extends ConsumerStatefulWidget {
  const POSSearchField({super.key});

  @override
  ConsumerState<POSSearchField> createState() => _POSSearchFieldState();
}

class _POSSearchFieldState extends ConsumerState<POSSearchField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(posProvider).searchQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(posProvider.select((state) => state.searchQuery), (_, query) {
      // Typing already updated the controller: preserve selection and composing.
      if (_controller.text == query) return;
      final selection = _controller.selection;
      _controller.value = TextEditingValue(
        text: query,
        selection: selection.isValid
            ? selection.copyWith(
                baseOffset: selection.baseOffset.clamp(0, query.length),
                extentOffset: selection.extentOffset.clamp(0, query.length),
              )
            : TextSelection.collapsed(offset: query.length),
      );
    });
    final query = ref.watch(posProvider.select((state) => state.searchQuery));
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      onChanged: (value) => ref.read(posProvider.notifier).setSearch(value),
      style: GoogleFonts.outfit(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search by service name, category or package...',
        hintStyle: GoogleFonts.outfit(color: Colors.black26, fontSize: 13),
        prefixIcon: const Icon(LucideIcons.search, size: 18, color: Colors.black26),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(LucideIcons.x, size: 16, color: Colors.black38),
                onPressed: () {
                  ref.read(posProvider.notifier).setSearch('');
                  _focusNode.requestFocus();
                },
              )
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
