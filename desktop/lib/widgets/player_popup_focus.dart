import 'package:flutter/material.dart';
import '../core/focus/desktop_navigation_controller.dart';

class PlayerPopupFocus extends StatefulWidget {
  final Widget child;
  const PlayerPopupFocus({super.key, required this.child});

  @override
  State<PlayerPopupFocus> createState() => _PlayerPopupFocusState();
}

class _PlayerPopupFocusState extends State<PlayerPopupFocus> {
  final _scope = FocusScopeNode(
    debugLabel: 'Player popup',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    onKeyEvent: (_, event) {
      if (DesktopNavigationController.isDesktopBackKey(event)) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: widget.child,
  );
}
