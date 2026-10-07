import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../services/app_update_service.dart';
import 'desktop_update_dialog.dart';

/// A sleek, non-intrusive desktop notification banner displayed when a new
/// AniWings Desktop update is available on GitHub or the release channel.
class DesktopUpdateBanner extends ConsumerStatefulWidget {
  const DesktopUpdateBanner({super.key});

  @override
  ConsumerState<DesktopUpdateBanner> createState() =>
      _DesktopUpdateBannerState();
}

class _DesktopUpdateBannerState extends ConsumerState<DesktopUpdateBanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(desktopUpdateAvailableProvider.notifier).checkForUpdates();
      }
    });
  }

  Future<void> _launchDownload(String url) async {
    final target = url.isNotEmpty
        ? url
        : 'https://github.com/thehakaiben-cmyk/aniwings-app/releases';
    final uri = Uri.tryParse(target);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateResult = ref.watch(desktopUpdateAvailableProvider);
    if (updateResult == null || !updateResult.hasUpdate) {
      return const SizedBox.shrink();
    }

    final release = updateResult.release;
    final version = release.version;
    final downloadUrl = updateResult.desktopUpdateUrl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF2121724),
        border: const Border(
          bottom: BorderSide(color: Color(0x334E80EE), width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Indicator Icon
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0x264E80EE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x4D4E80EE), width: 0.8),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              size: 14,
              color: Color(0xFF6BA3FF),
            ),
          ),
          const SizedBox(width: 12),

          // Message
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'AniWings Desktop v$version is available! ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                children: const [
                  TextSpan(
                    text:
                        '— A new build with improvements is ready to install.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 12),

          // Action 1: What's New dialog
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: Color(0x33FFFFFF)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () {
              showDesktopUpdateDialog(context, initialResult: updateResult);
            },
            child: const Text(
              "What's New",
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(width: 8),

          // Action 2: Direct Download Redirect
          ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 13),
            label: Text('Download v$version'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => _launchDownload(downloadUrl),
          ),

          const SizedBox(width: 6),

          // Dismiss Button
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 15),
            color: AppColors.textMuted,
            hoverColor: Colors.white12,
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Dismiss update notice',
            onPressed: () {
              ref.read(desktopUpdateAvailableProvider.notifier).dismiss();
            },
          ),
        ],
      ),
    );
  }
}
