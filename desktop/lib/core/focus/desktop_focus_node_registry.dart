import 'package:flutter/widgets.dart';

/// Central registry for managing stable desktop FocusNode lifecycles.
///
/// Prevents recreating FocusNodes during widget rebuilds, ensures clean disposal,
/// and eliminates "FocusNode used after being disposed" errors.
class DesktopFocusNodeRegistry {
  DesktopFocusNodeRegistry._();
  static final DesktopFocusNodeRegistry instance = DesktopFocusNodeRegistry._();

  final Map<String, FocusNode> _registry = {};
  final Map<String, Set<String>> _scopeMembers = {};
  final Set<String> _ownedKeys = {};

  /// Retrieves an existing FocusNode or creates and caches a new one for [key].
  FocusNode getOrCreateNode(
    String key, {
    String? debugLabel,
    String? scope,
    bool skipTraversal = false,
    bool canRequestFocus = true,
  }) {
    final existing = _registry[key];
    if (existing != null) {
      try {
        if (!existing.canRequestFocus && canRequestFocus) {
          existing.canRequestFocus = true;
        }
        return existing;
      } catch (_) {
        _registry.remove(key);
        _ownedKeys.remove(key);
      }
    }

    final newNode = FocusNode(
      debugLabel: debugLabel ?? key,
      skipTraversal: skipTraversal,
      canRequestFocus: canRequestFocus,
    );

    _registry[key] = newNode;
    _ownedKeys.add(key);

    if (scope != null) {
      _scopeMembers.putIfAbsent(scope, () => {}).add(key);
    }

    return newNode;
  }

  /// Registers an externally managed FocusNode under [key].
  void register(String key, FocusNode node) {
    _registry[key] = node;
    _ownedKeys.remove(key);
  }

  /// Unregisters an externally managed FocusNode without disposing it.
  void unregister(String key) {
    _registry.remove(key);
    _ownedKeys.remove(key);
    for (final members in _scopeMembers.values) {
      members.remove(key);
    }
  }

  /// Checks if a node exists and is currently mounted and active.
  bool hasActiveNode(String key) {
    final node = _registry[key];
    if (node == null) return false;
    try {
      return node.context != null && node.canRequestFocus;
    } catch (_) {
      return false;
    }
  }

  /// Attempts to find an existing active node by key.
  FocusNode? getNode(String key) {
    final node = _registry[key];
    if (node == null) return null;
    try {
      if (node.context != null) return node;
      return node;
    } catch (_) {
      _registry.remove(key);
      _ownedKeys.remove(key);
      return null;
    }
  }

  /// Safely disposes and removes a single node by [key].
  void disposeNode(String key) {
    final isOwned = _ownedKeys.remove(key);
    final node = _registry.remove(key);
    if (isOwned && node != null) {
      try {
        node.dispose();
      } catch (_) {}
    }

    for (final members in _scopeMembers.values) {
      members.remove(key);
    }
  }

  /// Safely disposes all nodes registered under [scope].
  void disposeScope(String scope) {
    final keys = _scopeMembers.remove(scope);
    if (keys == null || keys.isEmpty) return;

    for (final key in keys) {
      final isOwned = _ownedKeys.remove(key);
      final node = _registry.remove(key);
      if (isOwned && node != null) {
        try {
          node.dispose();
        } catch (_) {}
      }
    }
  }

  /// Disposes and clears unattached nodes in the registry.
  void disposeAll() {
    for (final key in _ownedKeys) {
      final node = _registry[key];
      if (node != null) {
        try {
          if (node.context == null) {
            node.dispose();
          }
        } catch (_) {}
      }
    }
    _ownedKeys.clear();
    _registry.clear();
    _scopeMembers.clear();
  }
}

// ── Backwards Compatibility Alias ──────────────────────────────────────────
