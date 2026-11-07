import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_models.dart';
import 'rex_widgets.dart';

class RexMenuEntry<T> {
  const RexMenuEntry(
    this.value,
    this.label, {
    this.icon,
    this.selected = false,
    this.destructive = false,
  });
  final T value;
  final String label;
  final IconData? icon;
  final bool selected, destructive;
}

Future<T?> showRexMenu<T>(
  BuildContext context, {
  required BuildContext anchor,
  required List<RexMenuEntry<T>> entries,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final media = MediaQuery.of(context);
  final width = math.min(258.0, media.size.width - 32);
  final height = math.min(
    entries.length * 48.0 + 14,
    media.size.height - media.padding.vertical - 32,
  );
  final left = (rect.right - width).clamp(16.0, media.size.width - width - 16);
  final below =
      rect.bottom + 9 + height < media.size.height - media.padding.bottom;
  final top = (below ? rect.bottom + 9 : rect.top - height - 9).clamp(
    media.padding.top + 8,
    media.size.height - media.padding.bottom - height - 8,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    barrierColor: Colors.black.withValues(alpha: .1),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (context, _, _) {
      final rows = <Widget>[];
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final color = entry.destructive
            ? const Color(0xFFFF777E)
            : Colors.white;
        if (i > 0) {
          rows.add(
            const Divider(height: 1, color: Color(0x15FFFFFF), indent: 16),
          );
        }
        rows.add(
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
            onPressed: () => Navigator.of(context).pop(entry.value),
            child: Row(
              children: [
                if (entry.icon != null) ...[
                  Icon(entry.icon, size: 18, color: color),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(fontSize: 15, color: color),
                  ),
                ),
                if (entry.selected)
                  const Icon(
                    CupertinoIcons.check_mark,
                    color: Colors.white,
                    size: 17,
                  ),
              ],
            ),
          ),
        );
      }
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Material(
              color: Colors.transparent,
              child: RexGlass(
                radius: 24,
                color: const Color(0xF044394D),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: rows,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: .94, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        alignment: Alignment(
          (rect.center.dx / media.size.width) * 2 - 1,
          (rect.center.dy / media.size.height) * 2 - 1,
        ),
        child: child,
      ),
    ),
  );
}

abstract final class RexFeedback {
  static OverlayEntry? _current;
  static void ticket(BuildContext context, VodItem item, String label) {
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.paddingOf(context).top + 68,
        right: 16,
        width: math.min(258, MediaQuery.sizeOf(context).width - 32),
        child: _TicketMotion(
          item: item,
          label: label,
          onDone: () {
            if (_current == entry) {
              entry.remove();
              _current = null;
            }
          },
        ),
      ),
    );
    _current = entry;
    Overlay.of(context).insert(entry);
  }
}

class _TicketMotion extends StatefulWidget {
  const _TicketMotion({
    required this.item,
    required this.label,
    required this.onDone,
  });
  final VodItem item;
  final String label;
  final VoidCallback onDone;
  @override
  State<_TicketMotion> createState() => _TicketMotionState();
}

class _TicketMotionState extends State<_TicketMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 300),
  );
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1550), _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlideTransition(
    position: Tween(
      begin: const Offset(1.25, -.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)),
    child: AnimatedBuilder(
      animation: _controller,
      builder: (_, child) =>
          Transform.rotate(angle: (1 - _controller.value) * .13, child: child),
      child: GestureDetector(
        onHorizontalDragEnd: (_) => _dismiss(),
        child: Material(
          color: Colors.transparent,
          elevation: 16,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(16),
          child: RexTicket(
            item: widget.item,
            compact: true,
            label: widget.label,
            onTap: _dismiss,
          ),
        ),
      ),
    ),
  );
}
