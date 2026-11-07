import 'package:flutter/widgets.dart';

import 'rex_store.dart';

class RexScope extends InheritedNotifier<RexStore> {
  const RexScope({super.key, required RexStore store, required super.child})
    : super(notifier: store);
  static RexStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RexScope>()!.notifier!;
}
