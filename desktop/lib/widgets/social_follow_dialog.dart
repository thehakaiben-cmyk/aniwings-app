import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../services/storage_service.dart';

class SocialFollowDialog extends ConsumerStatefulWidget {
  const SocialFollowDialog({super.key});

  @override
  ConsumerState<SocialFollowDialog> createState() => _SocialFollowDialogState();
}

class _SocialFollowDialogState extends ConsumerState<SocialFollowDialog> {
  late bool _dontShowAgain;

  @override
  void initState() {
    super.initState();
    final storageService = ref.read(storageServiceProvider);
    _dontShowAgain = storageService.getHideSocialPopupForever();
  }

  Future<void> _toggleDontShowAgain(bool? value) async {
    final newValue = value ?? false;
    setState(() {
      _dontShowAgain = newValue;
    });
    final storageService = ref.read(storageServiceProvider);
    await storageService.setHideSocialPopupForever(newValue);
  }

  Future<void> _launchSocialUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching URL ($urlString): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: AppColors.secondaryBg,
          borderRadius: AppRadii.dialog,
          border: Border.all(color: AppColors.borderStrong, width: 1.5),
          boxShadow: const [AppColors.shadowPanel, AppColors.shadowAccentGlow],
        ),
        child: ClipRRect(
          borderRadius: AppRadii.dialog,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Row with Title & Close Icon
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brandRed.withValues(alpha: 0.15),
                          border: Border.all(
                            color: AppColors.brandRed.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          color: AppColors.brandRed,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Join Our Community',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textMuted,
                          size: 22,
                        ),
                        splashRadius: 20,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Subtitle Description
                  Text(
                    'Connect with the AniWings community! Follow us for live release announcements, anime schedules, support, and discussions.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Social Media Links List
                  _SocialTile(
                    title: 'Telegram Channel',
                    subtitle: 'Official updates & release schedules',
                    brandColor: const Color(0xFF0088CC),
                    painter: _DialogTelegramPainter(const Color(0xFF0088CC)),
                    onTap: () =>
                        _launchSocialUrl('https://t.me/aniwings_community'),
                  ),
                  const SizedBox(height: 10),
                  _SocialTile(
                    title: 'Discord Server',
                    subtitle: 'Chat, feature requests & anime discussions',
                    brandColor: const Color(0xFF5865F2),
                    painter: _DialogDiscordPainter(const Color(0xFF5865F2)),
                    onTap: () =>
                        _launchSocialUrl('https://discord.gg/5WBhW723uB'),
                  ),
                  const SizedBox(height: 10),
                  _SocialTile(
                    title: 'Reddit Community',
                    subtitle: 'r/AniWings_Official',
                    brandColor: const Color(0xFFFF4500),
                    painter: _DialogRedditPainter(const Color(0xFFFF4500)),
                    onTap: () => _launchSocialUrl(
                      'https://www.reddit.com/r/AniWings_Official/',
                    ),
                  ),

                  const SizedBox(height: 22),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 14),

                  // "Don't show again" Checkbox
                  InkWell(
                    onTap: () => _toggleDontShowAgain(!_dontShowAgain),
                    borderRadius: AppRadii.control,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 2,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _dontShowAgain,
                              onChanged: _toggleDontShowAgain,
                              activeColor: AppColors.brandRed,
                              checkColor: Colors.white,
                              side: BorderSide(
                                color: _dontShowAgain
                                    ? AppColors.brandRed
                                    : AppColors.textMuted,
                                width: 1.8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Don't show again on this device",
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Close / Done Action Button
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.control,
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color brandColor;
  final CustomPainter painter;
  final VoidCallback onTap;

  const _SocialTile({
    required this.title,
    required this.subtitle,
    required this.brandColor,
    required this.painter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.card,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.card,
          border: Border.all(
            color: brandColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: brandColor.withValues(alpha: 0.15),
              ),
              child: Center(
                child: CustomPaint(size: const Size(20, 20), painter: painter),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, color: brandColor, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Custom Painters for Dialog Social Icons ────────────────────────────────

class _DialogTelegramPainter extends CustomPainter {
  final Color color;
  _DialogTelegramPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.51)
      ..lineTo(size.width * 0.85, size.height * 0.18)
      ..lineTo(size.width * 0.75, size.height * 0.82)
      ..lineTo(size.width * 0.48, size.height * 0.68)
      ..lineTo(size.width * 0.36, size.height * 0.80)
      ..lineTo(size.width * 0.37, size.height * 0.61)
      ..lineTo(size.width * 0.68, size.height * 0.33)
      ..lineTo(size.width * 0.29, size.height * 0.57)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DialogDiscordPainter extends CustomPainter {
  final Color color;
  _DialogDiscordPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.25, h * 0.25)
      ..cubicTo(w * 0.35, h * 0.20, w * 0.65, h * 0.20, w * 0.75, h * 0.25)
      ..lineTo(w * 0.78, h * 0.22)
      ..cubicTo(w * 0.85, h * 0.38, w * 0.88, h * 0.58, w * 0.82, h * 0.75)
      ..lineTo(w * 0.77, h * 0.71)
      ..cubicTo(w * 0.72, h * 0.77, w * 0.65, h * 0.80, w * 0.50, h * 0.80)
      ..cubicTo(w * 0.35, h * 0.80, w * 0.28, h * 0.77, w * 0.23, h * 0.71)
      ..lineTo(w * 0.18, h * 0.75)
      ..cubicTo(w * 0.12, h * 0.58, w * 0.15, h * 0.38, w * 0.22, h * 0.22)
      ..close();
    canvas.drawPath(path, paint);

    final eyePaint = Paint()
      ..color = const Color(0xFF181820)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.38, h * 0.50), w * 0.08, eyePaint);
    canvas.drawCircle(Offset(w * 0.62, h * 0.50), w * 0.08, eyePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DialogRedditPainter extends CustomPainter {
  final Color color;
  _DialogRedditPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;

    canvas.drawCircle(Offset(w * 0.5, h * 0.55), w * 0.35, paint);

    final antennaPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.2)
      ..quadraticBezierTo(w * 0.55, h * 0.08, w * 0.68, h * 0.08);
    canvas.drawPath(path, antennaPaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.68, h * 0.08), w * 0.06, dotPaint);

    canvas.drawCircle(Offset(w * 0.18, h * 0.55), w * 0.09, dotPaint);
    canvas.drawCircle(Offset(w * 0.82, h * 0.55), w * 0.09, dotPaint);

    final eyePaint = Paint()
      ..color = const Color(0xFF181820)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.38, h * 0.55), w * 0.07, eyePaint);
    canvas.drawCircle(Offset(w * 0.62, h * 0.55), w * 0.07, eyePaint);

    final mouthPaint = Paint()
      ..color = const Color(0xFF181820)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromLTWH(w * 0.43, h * 0.58, w * 0.14, h * 0.12),
      0.1,
      2.9,
      false,
      mouthPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
