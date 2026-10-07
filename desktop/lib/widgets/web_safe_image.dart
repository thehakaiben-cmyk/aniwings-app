import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'downloaded_network_image.dart';

/// Shared network image caching and placeholders for desktop artwork.
class WebSafeImage extends StatelessWidget {
  static const homeBackdropCacheWidth = 1280;
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final Color? color;
  final BlendMode? colorBlendMode;

  const WebSafeImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.errorBuilder,
    this.loadingBuilder,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.color,
    this.colorBlendMode,
  });

  /// Returns a proxied URL on Web to bypass CORS restrictions from CDNs like
  /// AniList. On non-web platforms the original URL is returned unchanged.
  static String proxyUrl(String url) => url;

  /// Share the exact decoded cache entry between startup and visible artwork.
  static ImageProvider provider(
    String url, {
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      DownloadedNetworkImage(proxyUrl(url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.5;
    final int? effectiveCacheWidth =
        cacheWidth ??
        ((width != null && width!.isFinite && width! > 0)
            ? (width! * dpr).round().clamp(80, 1920)
            : null);
    final int? effectiveCacheHeight =
        cacheHeight ??
        ((height != null && height!.isFinite && height! > 0)
            ? (height! * dpr).round().clamp(80, 1920)
            : null);

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final decodeWidth =
              effectiveCacheWidth ??
              (bounds.hasBoundedWidth && bounds.maxWidth > 0
                  ? (bounds.maxWidth * dpr).round().clamp(80, 1920)
                  : null);
          return Image(
            image: provider(
              url,
              cacheWidth: decodeWidth,
              cacheHeight: effectiveCacheHeight,
            ),
            fit: fit,
            alignment: alignment,
            filterQuality: filterQuality,
            gaplessPlayback: true,
            width: width,
            height: height,
            color: color,
            colorBlendMode: colorBlendMode,
            errorBuilder:
                errorBuilder ??
                (context, error, stackTrace) => Container(
                  color: const Color(0xFF1A1A2E),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: Color(0xFF4A4A6A),
                      size: 28,
                    ),
                  ),
                ),
            loadingBuilder: loadingBuilder,
            frameBuilder: loadingBuilder != null
                ? null
                : (context, child, frame, synchronous) {
                    if (synchronous || frame != null) return child;
                    return Container(
                      width: width,
                      height: height,
                      color: const Color(0xFF1A1A2E),
                    );
                  },
          );
        },
      ),
    );
  }
}

/// A premium backdrop image component that displays a blurred background image
/// with the sharp image centered on top. Excellent for movie / series detail pages
/// and hero banners where wide images might crop or contain blank space.
class BlurredBackdropImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? overlay;

  const BlurredBackdropImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final overlayElement = overlay;
    final logicalWidth = width ?? MediaQuery.sizeOf(context).width;
    final cacheWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(320, 1920)
        .toInt();
    return Container(
      width: width ?? double.infinity,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Blurred Background Image (Covers entire space)
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
              child: WebSafeImage(
                url: url,
                fit: BoxFit.cover,
                alignment: alignment,
                filterQuality: FilterQuality.low,
                cacheWidth: 120,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          // 2. Dark tint overlay to blend background and ensure text readability
          Container(color: Colors.black.withValues(alpha: 0.35)),
          // 3. Sharp Foreground Image (Contained / centered)
          WebSafeImage(
            url: url,
            fit: fit,
            alignment: alignment,
            cacheWidth: cacheWidth,
            errorBuilder: (context, error, stackTrace) => Container(
              color: const Color(0xFF1A1A2E),
              child: const Center(
                child: Icon(
                  Icons.movie_creation_outlined,
                  color: Color(0xFF4A4A6A),
                  size: 40,
                ),
              ),
            ),
          ),
          // 4. Custom gradient / element overlay if specified
          overlayElement ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}
