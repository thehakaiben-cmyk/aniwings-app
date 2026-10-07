import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../services/storage_service.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_page_shell.dart';
import '../../widgets/desktop_layout.dart';

class SubtitleSettingsScreen extends ConsumerStatefulWidget {
  const SubtitleSettingsScreen({super.key});

  @override
  ConsumerState<SubtitleSettingsScreen> createState() =>
      _SubtitleSettingsScreenState();
}

class _SubtitleSettingsScreenState
    extends ConsumerState<SubtitleSettingsScreen> {
  static const _textColours = <int>[
    0xFFFFFFFF,
    0xFFFFEB3B,
    0xFF58E86B,
    0xFF48DDF0,
    0xFFFF5D5D,
    0xFF778BFF,
    0xFFFFAD42,
    0xFFFFB6C6,
  ];
  static const _backgroundColours = <int>[
    0xFF000000,
    0xFF2A2A2A,
    0xFF243B80,
    0xFF7C2B2B,
    0xFF285C33,
    0xFF808080,
  ];

  late String _language;
  late double _fontSize;
  late String _style;
  late int _textColour;
  int? _backgroundColour;
  late double _bottomPosition;
  late double _textShadow;
  late double _backgroundOpacity;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  void _loadPreferences() {
    final storage = ref.read(storageServiceProvider);
    _language = storage.getSubtitlePreference();
    _fontSize = storage.getSubtitleSizePreference();
    _style = storage.getSubtitleTextStylePreference();
    _textColour = storage.getSubtitleTextColorValue();
    _backgroundColour = storage.getSubtitleBackgroundColorValue();
    _bottomPosition = storage.getSubtitleBottomPosition();
    _textShadow = storage.getSubtitleTextShadow();
    _backgroundOpacity = storage.getSubtitleBackgroundOpacity();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final storage = ref.read(storageServiceProvider);
    await Future.wait([
      storage.setSubtitlePreference(_language),
      storage.setSubtitleSizePreference(_fontSize),
      storage.setSubtitleTextStylePreference(_style),
      storage.setSubtitleTextColorValue(_textColour),
      storage.setSubtitleBackgroundColorValue(_backgroundColour),
      storage.setSubtitleBottomPosition(_bottomPosition),
      storage.setSubtitleTextShadow(_textShadow),
      storage.setSubtitleBackgroundOpacity(_backgroundOpacity),
    ]);
    ref.read(storageRevisionProvider.notifier).state++;
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Subtitle settings saved')));
  }

  Future<void> _reset() async {
    await ref.read(storageServiceProvider).resetSubtitleAppearancePreferences();
    if (!mounted) return;
    setState(_loadPreferences);
    ref.read(storageRevisionProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subtitle settings restored to default')),
    );
  }

  FontWeight get _fontWeight => switch (_style) {
    'bold' => FontWeight.w800,
    _ => FontWeight.w600,
  };

  FontStyle get _fontStyle =>
      _style == 'italic' ? FontStyle.italic : FontStyle.normal;

  @override
  Widget build(BuildContext context) {
    return DesktopPageShell(
      onRootBack: () => context.canPop() ? context.pop() : context.go('/home'),
      child: Scaffold(
        backgroundColor: AppColors.primaryBg,
        body: DesktopPageBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                DesktopPageHeader(
                  leading: DesktopBackButton(
                    autofocus: true,
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/home'),
                  ),
                  eyebrow: 'SUBTITLES',
                  title: 'Subtitle settings',
                  subtitle: 'Language, text, color, and player position',
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      DesktopLayout.pagePadding(context),
                      2,
                      DesktopLayout.pagePadding(context),
                      24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1420),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ─── Left Pane: Live Cinema Preview & Actions ─────
                            SizedBox(
                              width: 420,
                              child: DesktopSurface(
                                padding: const EdgeInsets.all(24),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildSubtitleAboutPane(),
                                      const SizedBox(height: 24),
                                      const Divider(
                                        color: AppColors.borderSubtle,
                                        height: 1,
                                      ),
                                      const SizedBox(height: 20),
                                      _SubtitleActionButton(
                                        debugLabel: 'Save subtitle settings',
                                        label: 'SAVE OPTIONS',
                                        icon: Icons.save_rounded,
                                        busy: _isSaving,
                                        onTap: _isSaving ? null : _save,
                                      ),
                                      const SizedBox(height: 12),
                                      _SubtitleActionButton(
                                        debugLabel: 'Reset subtitle settings',
                                        label: 'RESET TO DEFAULT',
                                        icon: Icons.restore_rounded,
                                        filled: false,
                                        onTap: _isSaving ? null : _reset,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(width: DesktopLayout.cardGap(context)),

                            // ─── Right Pane: Subtitle Customization Grid ──────
                            Expanded(
                              child: DesktopSurface(
                                padding: const EdgeInsets.all(24),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Subtitle Appearance & Options',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Adjust language, typography, color palettes, and on-screen dialogue positioning.',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 24),

                                      const Text(
                                        'Default subtitle language',
                                        style: _fieldTitleStyle,
                                      ),
                                      const SizedBox(height: 12),
                                      _buildTextChoices(
                                        values: const [
                                          'English',
                                          'Portuguese',
                                          'Spanish',
                                          'Off',
                                        ],
                                        selected: _language,
                                        onSelected: (value) =>
                                            setState(() => _language = value),
                                      ),
                                      const SizedBox(height: 7),
                                      const Text(
                                        'Falls back to English when your selected language is unavailable.',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 26),

                                      _buildSlider(
                                        title: 'Text size',
                                        value: _fontSize,
                                        min: 10,
                                        max: 28,
                                        valueLabel: '${_fontSize.round()} px',
                                        onChanged: (value) =>
                                            setState(() => _fontSize = value),
                                      ),
                                      const SizedBox(height: 24),

                                      const Text(
                                        'Text style',
                                        style: _fieldTitleStyle,
                                      ),
                                      const SizedBox(height: 12),
                                      _buildStyleChoices(),
                                      const SizedBox(height: 26),

                                      const Text(
                                        'Text color',
                                        style: _fieldTitleStyle,
                                      ),
                                      const SizedBox(height: 14),
                                      _buildColourChoices(
                                        values: _textColours,
                                        selected: _textColour,
                                        onSelected: (value) =>
                                            setState(() => _textColour = value),
                                      ),
                                      const SizedBox(height: 26),

                                      const Text(
                                        'Background color',
                                        style: _fieldTitleStyle,
                                      ),
                                      const SizedBox(height: 14),
                                      Wrap(
                                        spacing: 14,
                                        runSpacing: 14,
                                        children: [
                                          _ColourButton(
                                            label: 'None',
                                            colour: null,
                                            isSelected:
                                                _backgroundColour == null,
                                            onTap: () => setState(
                                              () => _backgroundColour = null,
                                            ),
                                          ),
                                          ..._backgroundColours.map(
                                            (value) => _ColourButton(
                                              colour: Color(value),
                                              isSelected:
                                                  _backgroundColour == value,
                                              onTap: () => setState(
                                                () => _backgroundColour = value,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 26),

                                      _buildSlider(
                                        title: 'Bottom position',
                                        value: _bottomPosition,
                                        min: 0,
                                        max: 1,
                                        valueLabel:
                                            '${(_bottomPosition * 100).round()}%',
                                        onChanged: (value) => setState(
                                          () => _bottomPosition = value,
                                        ),
                                      ),
                                      const SizedBox(height: 24),

                                      _buildSlider(
                                        title: 'Text shadow',
                                        value: _textShadow,
                                        min: 0,
                                        max: 1,
                                        valueLabel:
                                            '${(_textShadow * 100).round()}%',
                                        onChanged: (value) =>
                                            setState(() => _textShadow = value),
                                      ),
                                      const SizedBox(height: 24),

                                      _buildSlider(
                                        title: 'Background opacity',
                                        value: _backgroundOpacity,
                                        min: 0,
                                        max: 1,
                                        valueLabel:
                                            '${(_backgroundOpacity * 100).round()}%',
                                        onChanged: (value) => setState(
                                          () => _backgroundOpacity = value,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleAboutPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreview(),
        const SizedBox(height: 20),
        const Text(
          'About Subtitles',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Preview changes in real-time above. All typography, colors, and positioning apply immediately to the desktop media player.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.secondaryBg,
            borderRadius: AppRadii.card,
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Language', _language, AppColors.brandRed),
              const Divider(color: AppColors.borderSubtle, height: 16),
              _buildSummaryRow(
                'Font Size',
                '${_fontSize.round()} px',
                AppColors.textPrimary,
              ),
              const Divider(color: AppColors.borderSubtle, height: 16),
              _buildSummaryRow(
                'Style',
                _style.toUpperCase(),
                AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final background = _backgroundColour == null
        ? null
        : Color(_backgroundColour!).withValues(alpha: _backgroundOpacity);
    final shadow = _textShadow <= 0
        ? const <Shadow>[]
        : [
            Shadow(
              color: Colors.black.withValues(alpha: 0.88 * _textShadow),
              blurRadius: 8 * _textShadow,
              offset: Offset(0, 2 * _textShadow),
            ),
          ];

    return AspectRatio(
      aspectRatio: 16 / 8.2,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: AppRadii.card,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF26323F), Color(0xFF101419), Color(0xFF20131C)],
          ),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 18,
              left: 18,
              child: Text(
                'LIVE PREVIEW',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 15 + (76 * _bottomPosition),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: background == null
                      ? null
                      : BoxDecoration(
                          color: background,
                          borderRadius: BorderRadius.circular(5),
                        ),
                  child: Text(
                    'The adventure is just beginning.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(_textColour),
                      fontSize: _fontSize.clamp(10, 24),
                      fontWeight: _fontWeight,
                      fontStyle: _fontStyle,
                      shadows: shadow,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String title,
    required double value,
    required double min,
    required double max,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: _fieldTitleStyle),
            const Spacer(),
            Text(
              valueLabel,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        _DesktopSubtitleSlider(
          title: title,
          value: value,
          min: min,
          max: max,
          valueLabel: valueLabel,
          step: max - min >= 10 ? 1 : 0.05,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTextChoices({
    required List<String> values,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final value in values)
          _SubtitleChoiceChip(
            label: value,
            isSelected: selected == value,
            onTap: () => onSelected(value),
          ),
      ],
    );
  }

  Widget _buildStyleChoices() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final style in const ['normal', 'bold', 'italic'])
          _SubtitleChoiceChip(
            label: style[0].toUpperCase() + style.substring(1),
            isSelected: _style == style,
            textStyle: TextStyle(
              fontWeight: style == 'bold' ? FontWeight.w900 : FontWeight.w800,
              fontStyle: style == 'italic'
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
            onTap: () => setState(() => _style = style),
          ),
      ],
    );
  }

  Widget _buildColourChoices({
    required List<int> values,
    required int selected,
    required ValueChanged<int> onSelected,
  }) => Wrap(
    spacing: 14,
    runSpacing: 14,
    children: values
        .map(
          (value) => _ColourButton(
            colour: Color(value),
            isSelected: selected == value,
            onTap: () => onSelected(value),
          ),
        )
        .toList(),
  );
}

const _fieldTitleStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 17,
  fontWeight: FontWeight.w800,
);

class _SubtitleChoiceChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  const _SubtitleChoiceChip({
    required this.label,
    required this.isSelected,
    this.textStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopFocusWrapper(
      debugLabel: label,
      onTap: onTap,
      borderRadius: AppRadii.control,
      focusedScale: 1.02,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(minWidth: 84),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandRed : AppColors.elevatedSurface,
          borderRadius: AppRadii.control,
          border: Border.all(
            color: isSelected ? AppColors.brandRed : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: (textStyle ?? const TextStyle()).copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: textStyle?.fontWeight ?? FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SubtitleActionButton extends StatelessWidget {
  final String debugLabel;
  final String label;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback? onTap;

  const _SubtitleActionButton({
    required this.debugLabel,
    required this.label,
    required this.icon,
    this.filled = true,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return DesktopFocusWrapper(
      debugLabel: debugLabel,
      onTap: enabled ? onTap : null,
      canRequestFocus: enabled,
      borderRadius: AppRadii.control,
      focusedScale: 1.015,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled && enabled
              ? AppColors.brandRed
              : AppColors.elevatedSurface,
          borderRadius: AppRadii.control,
          border: Border.all(
            color: filled && enabled
                ? AppColors.brandRed
                : AppColors.borderSubtle,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: filled && enabled
                        ? Colors.white
                        : AppColors.brandRed,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: filled && enabled
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ColourButton extends StatelessWidget {
  final Color? colour;
  final String? label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColourButton({
    required this.colour,
    this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      selected: isSelected,
      label: label ?? 'Colour option',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour ?? AppColors.elevatedSurface,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.brandRed : AppColors.borderSubtle,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: label == null
            ? null
            : Text(
                label!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );

    return DesktopFocusWrapper(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      focusedScale: 1.06,
      child: button,
    );
  }
}

/// Keeps keyboard navigation between subtitle settings and slider changes distinct.
class _DesktopSubtitleSlider extends StatefulWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final double step;
  final ValueChanged<double> onChanged;

  const _DesktopSubtitleSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.step,
    required this.onChanged,
  });

  @override
  State<_DesktopSubtitleSlider> createState() => _DesktopSubtitleSliderState();
}

class _DesktopSubtitleSliderState extends State<_DesktopSubtitleSlider> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: '${widget.title} slider');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double get _progress =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _adjust(double amount) {
    final next = (widget.value + amount).clamp(widget.min, widget.max);
    if (next != widget.value) widget.onChanged(next.toDouble());
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _adjust(-widget.step);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _adjust(widget.step);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        FocusScope.of(context).previousFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        FocusScope.of(context).nextFocus();
        return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _setFromTap(TapDownDetails details, double width) {
    _focusNode.requestFocus();
    final progress = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final rawValue = widget.min + ((widget.max - widget.min) * progress);
    final stepped = (rawValue / widget.step).round() * widget.step;
    widget.onChanged(stepped.clamp(widget.min, widget.max).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      focusable: true,
      focused: _isFocused,
      label: widget.title,
      value: widget.valueLabel,
      hint:
          'Use left and right to adjust. Use up and down to move between settings.',
      onIncrease: () => _adjust(widget.step),
      onDecrease: () => _adjust(-widget.step),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.elevatedSurface,
            borderRadius: AppRadii.control,
            border: Border.all(
              color: _isFocused ? Colors.white : AppColors.borderSubtle,
              width: _isFocused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.remove_rounded,
                color: AppColors.textMuted,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _setFromTap(details, constraints.maxWidth),
                    child: Center(
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: _progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.brandRed,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.add_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
