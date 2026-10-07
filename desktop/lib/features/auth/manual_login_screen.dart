import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_brand.dart';
import '../../widgets/desktop_focus_wrapper.dart';

class ManualLoginScreen extends ConsumerStatefulWidget {
  const ManualLoginScreen({super.key});

  @override
  ConsumerState<ManualLoginScreen> createState() => _ManualLoginScreenState();
}

class _ManualLoginScreenState extends ConsumerState<ManualLoginScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _confirmation = TextEditingController();
  bool _createAccount = false;
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  String? _editing;
  final _nodes = <String, FocusNode>{};
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    final visible = View.of(context).viewInsets.bottom > 0;
    if (_keyboardVisible && !visible && _editing != null && mounted) {
      setState(() => _editing = null);
    }
    _keyboardVisible = visible;
  }

  List<String> get _order => [
    'back',
    if (_createAccount) 'username',
    'email',
    'password',
    if (_createAccount) 'confirmation',
    'visibility',
    'submit',
    if (!_createAccount) 'reset',
    'mode',
  ];

  FocusNode _node(String id) => _nodes.putIfAbsent(id, () {
    final node = FocusNode(debugLabel: 'Manual auth $id');
    node.onKeyEvent = (_, event) => _fieldKey(id, event);
    node.addListener(() {
      if (!mounted) return;
      if (!node.hasFocus && _editing == id) {
        setState(() => _editing = null);
      }
      if (node.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && node.context != null) {
            Scrollable.ensureVisible(
              node.context!,
              alignment: 0.5,
              duration: const Duration(milliseconds: 120),
            );
          }
        });
      }
    });
    return node;
  });

  void _move(String id, int direction) {
    if (_busy) return;
    setState(() => _editing = null);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    final index = (_order.indexOf(id) + direction).clamp(0, _order.length - 1);
    _node(_order[index]).requestFocus();
  }

  KeyEventResult _fieldKey(String id, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      _move(id, key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (_editing == id) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _edit(id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _edit(String id) {
    if (_busy) return;
    setState(() => _editing = id);
    _node(id).requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing == id) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  void _back() {
    if (_editing != null) {
      setState(() => _editing = null);
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/profile');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final node in _nodes.values) {
      node.dispose();
    }
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit({bool reset = false}) async {
    if (_busy) return;
    if (reset) {
      if (!_validEmail(_email.text)) {
        setState(
          () => _message = 'Enter your email address to reset your password.',
        );
        return;
      }
    } else if (!_form.currentState!.validate()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final auth = ref.read(authStateProvider.notifier);
      final error = reset
          ? await auth.resetPassword(_email.text.trim())
          : _createAccount
          ? await auth.register(
              _username.text.trim(),
              _email.text.trim(),
              _password.text,
            )
          : await auth.login(_email.text.trim(), _password.text);
      if (!mounted) return;
      if (!reset && error == null) {
        context.go('/home');
        return;
      }
      setState(
        () => _message =
            error ??
            'If an account exists, a password reset email has been sent.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = _createAccount
              ? 'Unable to create your account. Please try again.'
              : 'Unable to sign in. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _node('submit').requestFocus();
        });
      }
    }
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

  void _switchMode() {
    FocusManager.instance.primaryFocus?.unfocus();
    _form.currentState?.reset();
    _password.clear();
    _confirmation.clear();
    setState(() {
      _createAccount = !_createAccount;
      _obscure = true;
      _message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(_createAccount ? 'username' : 'email').requestFocus();
    });
  }

  Widget _action(
    String id,
    String label,
    VoidCallback action, {
    bool primary = false,
    IconData? icon,
  }) => DesktopFocusWrapper.builder(
    focusNode: _node(id),
    canRequestFocus: !_busy,
    focusedScale: 1,
    debugLabel: label,
    targetScrollAlignment: 0.5,
    onTap: _busy ? null : action,
    directionalKeyHandlers: {
      LogicalKeyboardKey.arrowUp: () => _move(id, -1),
      LogicalKeyboardKey.arrowDown: () => _move(id, 1),
    },
    builder: (context, focused, hovered) => AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: _busy
            ? AppColors.elevatedSurface
            : primary
            ? AppColors.brandRed
            : focused
            ? AppColors.hoverState
            : hovered
            ? AppColors.elevatedSurface
            : AppColors.surface,
        borderRadius: AppRadii.control,
        border: Border.all(
          color: focused
              ? Colors.white
              : (hovered ? AppColors.borderStrong : AppColors.borderSubtle),
          width: focused ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _busy ? Colors.white38 : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    String id,
    String label,
    TextEditingController controller, {
    required String? Function(String?) validator,
    bool password = false,
    TextInputType? keyboardType,
    bool last = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey(id),
      controller: controller,
      focusNode: _node(id),
      autofocus: id == (_createAccount ? 'username' : 'email'),
      enabled: !_busy,
      readOnly: _editing != id,
      showCursor: _editing == id,
      onTap: () => _edit(id),
      obscureText: password && _obscure,
      autocorrect: false,
      enableSuggestions: !password,
      keyboardType: keyboardType,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onEditingComplete: () => _move(id, 1),
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(
          password
              ? Icons.lock_outline
              : id == 'email'
              ? Icons.email_outlined
              : Icons.person_outline,
          color: AppColors.textMuted,
          size: 20,
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadii.control,
          borderSide: BorderSide(color: Colors.white, width: 1.5),
        ),
      ),
      validator: validator,
    ),
  );

  Widget _intro() => Container(
    key: const ValueKey('auth-intro'),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: AppColors.secondaryBg,
      borderRadius: AppRadii.dialog,
      border: Border.all(color: AppColors.borderSubtle),
      boxShadow: const [AppColors.shadowPanel],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.control,
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: const Icon(
            Icons.desktop_windows_rounded,
            color: AppColors.brandRed,
            size: 36,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _createAccount
              ? 'Your anime.\nYour account.'
              : 'Welcome back\nto your anime.',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _createAccount
              ? 'Choose a username and create your AniWings account right here on AniWings Desktop.'
              : 'Sign in to keep your watchlist and viewing progress with you.',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Sign in on your desktop',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '↑ ↓  Move between controls\nOK  Edit a field or select an action\nBack  Close the keyboard',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.7,
          ),
        ),
      ],
    ),
  );

  Widget _credentials() => Container(
    key: const ValueKey('auth-form-panel'),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: AppColors.secondaryBg,
      borderRadius: AppRadii.dialog,
      border: Border.all(color: AppColors.borderSubtle),
      boxShadow: const [AppColors.shadowPanel],
    ),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _createAccount
                ? 'Create your AniWings account'
                : 'Sign in with email',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _createAccount
                ? 'Your username appears on your profile.'
                : 'Enter the email and password for your account.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 22),
          if (_createAccount)
            _field(
              'username',
              'Username',
              _username,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter a username.'
                  : value!.trim().length > 30
                  ? 'Use no more than 30 characters.'
                  : null,
            ),
          _field(
            'email',
            'Email',
            _email,
            keyboardType: TextInputType.emailAddress,
            validator: (value) => _validEmail(value ?? '')
                ? null
                : 'Enter a valid email address.',
          ),
          _field(
            'password',
            'Password',
            _password,
            password: true,
            last: !_createAccount,
            validator: (value) => value == null || value.isEmpty
                ? 'Enter your password.'
                : _createAccount && value.length < 8
                ? 'Use at least 8 characters.'
                : null,
          ),
          if (_createAccount)
            _field(
              'confirmation',
              'Confirm password',
              _confirmation,
              password: true,
              last: true,
              validator: (value) =>
                  value != _password.text || (value ?? '').isEmpty
                  ? 'Passwords must match.'
                  : null,
            ),
          _action(
            'visibility',
            _obscure ? 'Show password' : 'Hide password',
            () => setState(() => _obscure = !_obscure),
            icon: _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          const SizedBox(height: 14),
          if (_message != null) ...[
            Text(
              _message!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
            const SizedBox(height: 14),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandRed,
                  ),
                ),
              ),
            ),
          _action(
            'submit',
            _createAccount ? 'Create account' : 'Sign in',
            () => _submit(),
            primary: true,
            icon: Icons.arrow_forward_rounded,
          ),
          if (!_createAccount) ...[
            const SizedBox(height: 12),
            _action('reset', 'Forgot password?', () => _submit(reset: true)),
          ],
          const SizedBox(height: 12),
          _action(
            'mode',
            _createAccount
                ? 'Already have an account? Sign in'
                : 'New here? Create account',
            _switchMode,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          [
            LogicalKeyboardKey.escape,
            LogicalKeyboardKey.goBack,
            LogicalKeyboardKey.browserBack,
            LogicalKeyboardKey.gameButtonB,
          ].contains(event.logicalKey)) {
        _back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: ExcludeFocus(child: const AppBrand())),
                  SizedBox(
                    width: 220,
                    child: _action(
                      'back',
                      'Close authentication',
                      () => context.go('/home'),
                      icon: Icons.close,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 720) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(child: _intro()),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _credentials(),
                            ),
                          ),
                        ],
                      );
                    }
                    return SingleChildScrollView(child: _credentials());
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
