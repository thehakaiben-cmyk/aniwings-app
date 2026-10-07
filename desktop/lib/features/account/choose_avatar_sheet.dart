import 'package:flutter/material.dart';
import '../../core/constants/anime_avatars.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_page_shell.dart';
import '../../widgets/web_safe_image.dart';

class ChooseAvatarSheet extends StatelessWidget {
  final String? currentAvatarUrl;
  final ValueChanged<String> onAvatarSelected;

  const ChooseAvatarSheet({
    super.key,
    this.currentAvatarUrl,
    required this.onAvatarSelected,
  });

  @override
  Widget build(BuildContext context) {
    final categories = AnimeAvatarRepository.getCategories();
    final mediaQuery = MediaQuery.of(context);
    final bottomScrollPadding = mediaQuery.viewPadding.bottom + 56;

    return DesktopPageShell(
      onRootBack: () => Navigator.of(context).pop(),
      child: Center(
        child: Container(
          height: mediaQuery.size.height * ((0.82)),
          width: (920),
          decoration: BoxDecoration(
            color: AppColors.elevatedSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag indicator bar
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Header: Choose Avatar + Close Button
              Padding(
                padding: EdgeInsets.symmetric(horizontal: (28), vertical: (10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Choose Avatar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (24),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.borderSubtle, height: 1),

              // Category List Body
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: bottomScrollPadding,
                    top: (14),
                  ),
                  itemCount: categories.keys.length,
                  itemBuilder: (context, index) {
                    final categoryName = categories.keys.elementAt(index);
                    final avatars = categories[categoryName]!;

                    return Padding(
                      padding: EdgeInsets.only(top: (20), bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category Header
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: (28)),
                            child: Text(
                              categoryName,
                              style: const TextStyle(
                                color: AppColors.accentPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Horizontal Scrollable Avatars Row
                          SizedBox(
                            height: (98),
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.symmetric(horizontal: (22)),
                              itemCount: avatars.length,
                              itemBuilder: (context, avatarIdx) {
                                final avatar = avatars[avatarIdx];
                                final isSelected =
                                    currentAvatarUrl == avatar.imageUrl;

                                final avatarButton = Container(
                                  margin: EdgeInsets.symmetric(horizontal: (8)),
                                  width: (90),
                                  height: (90),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.accentPrimary
                                          : avatar.borderColor.withValues(
                                              alpha: 0.5,
                                            ),
                                      width: isSelected ? 3.0 : 2.0,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.accentPrimary
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 12,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all((3)),
                                    child: ClipOval(
                                      child: _buildAvatarImage(avatar),
                                    ),
                                  ),
                                );

                                void selectAvatar() {
                                  onAvatarSelected(avatar.imageUrl);
                                  Navigator.of(context).pop();
                                }

                                return DesktopFocusWrapper(
                                  onTap: selectAvatar,
                                  borderRadius: BorderRadius.circular(48),
                                  focusedScale: 1.06,
                                  child: avatarButton,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarImage(AnimeAvatar avatar) {
    const imageSize = 84.0;
    if (avatar.imageUrl.startsWith('assets/')) {
      return Image.asset(
        avatar.imageUrl,
        fit: BoxFit.cover,
        width: imageSize,
        height: imageSize,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: const Color(0xFF1E2533),
            child: Center(
              child: Text(
                avatar.name.isNotEmpty ? avatar.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: avatar.borderColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          );
        },
      );
    }
    return Image.network(
      WebSafeImage.proxyUrl(avatar.imageUrl),
      fit: BoxFit.cover,
      width: imageSize,
      height: imageSize,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return Container(
          color: const Color(0xFF1E2533),
          child: Center(
            child: Text(
              avatar.name.isNotEmpty ? avatar.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: avatar.borderColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: const Color(0xFF1E2533),
          child: Center(
            child: Text(
              avatar.name.isNotEmpty ? avatar.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: avatar.borderColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        );
      },
    );
  }
}
