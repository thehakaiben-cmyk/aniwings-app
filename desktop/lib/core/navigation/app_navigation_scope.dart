import 'package:flutter/widgets.dart';

typedef BranchNavigationCallback = void Function(int index, {bool reset});

class AppNavigationScope extends InheritedWidget {
  final int currentBranchIndex;
  final BranchNavigationCallback goToBranch;
  final VoidCallback goBack;

  const AppNavigationScope({
    super.key,
    required this.currentBranchIndex,
    required this.goToBranch,
    required this.goBack,
    required super.child,
  });

  static AppNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppNavigationScope>();
  }

  @override
  bool updateShouldNotify(AppNavigationScope oldWidget) {
    return currentBranchIndex != oldWidget.currentBranchIndex ||
        goToBranch != oldWidget.goToBranch ||
        goBack != oldWidget.goBack;
  }
}
