import 'package:flutter/material.dart';

/// Keeps the horizontal handle at the bottom of the visible report panel.
class ReportHorizontalScrollbars extends StatelessWidget {
  const ReportHorizontalScrollbars({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    bool horizontalNotification(ScrollNotification notification) =>
        notification.metrics.axis == Axis.horizontal;

    return ScrollConfiguration(
      // Desktop's automatic scrollbar otherwise draws an extra dark line.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thickness: const WidgetStatePropertyAll(7),
          radius: const Radius.circular(8),
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.dragged) ||
                      states.contains(WidgetState.hovered)
                  ? const Color(0xFFA5A6E8)
                  : const Color(0xFFC4C5EF)),
          trackColor: const WidgetStatePropertyAll(Color(0xFFF4F4FC)),
          trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
          crossAxisMargin: 3,
        ),
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          notificationPredicate: horizontalNotification,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: child,
          ),
        ),
      ),
    );
  }
}
