import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../models/collection.dart';
import '../../services/anime_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/anime_card.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/web_safe_image.dart';

/// AniWings Desktop — Smart Collections Screen.
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  late final ScrollController _scrollController;
  AnimeCollection? _selectedCollection;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showCreateCollectionDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.secondaryBg,
            borderRadius: AppRadii.dialog,
            border: Border.all(color: AppColors.border, width: 1.0),
            boxShadow: const [AppColors.shadowPanel],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandRed.withValues(alpha: 0.15),
                      borderRadius: AppRadii.control,
                      border: Border.all(
                        color: AppColors.brandRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.video_library_rounded,
                      color: AppColors.brandRed,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Create Collection',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Collection Name',
                  hintText: 'e.g., Mind-Bending Thrillers',
                  labelStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: AppColors.brandRed),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Short notes about this collection',
                  labelStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: AppColors.brandRed),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DesktopFocusWrapper(
                    borderRadius: AppRadii.control,
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.control,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DesktopFocusWrapper(
                    borderRadius: AppRadii.control,
                    onTap: () async {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.of(dialogContext).pop();
                        await ref
                            .read(storageServiceProvider)
                            .createCollection(
                              name,
                              description: descController.text.trim(),
                            );
                        if (mounted) {
                          setState(() {});
                          ref.read(storageRevisionProvider.notifier).state++;
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandRed,
                        borderRadius: AppRadii.control,
                      ),
                      child: const Text(
                        'Create',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteCollectionDialog(BuildContext context, AnimeCollection col) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.secondaryBg,
            borderRadius: AppRadii.dialog,
            border: Border.all(color: AppColors.border, width: 1.0),
            boxShadow: const [AppColors.shadowPanel],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete "${col.name}"?',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This will remove this custom collection. The anime titles themselves will remain accessible in your library.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DesktopFocusWrapper(
                    autofocus: true,
                    borderRadius: AppRadii.control,
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.control,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DesktopFocusWrapper(
                    borderRadius: AppRadii.control,
                    onTap: () async {
                      Navigator.of(dialogContext).pop();
                      await ref
                          .read(storageServiceProvider)
                          .deleteCollection(col.id);
                      if (mounted) {
                        setState(() {
                          if (_selectedCollection?.id == col.id) {
                            _selectedCollection = null;
                          }
                        });
                        ref.read(storageRevisionProvider.notifier).state++;
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: AppRadii.control,
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storageService = ref.watch(storageServiceProvider);
    final animeService = ref.watch(animeServiceProvider);
    ref.watch(storageRevisionProvider);

    final collections = storageService.getCollections();
    final leftPadding = DesktopLayout.pageLeftPadding(context);
    final rightPadding = DesktopLayout.pagePadding(context);

    // If a collection is selected, render its titles
    if (_selectedCollection != null) {
      return _buildCollectionDetailView(
        context: context,
        collection: _selectedCollection!,
        storageService: storageService,
        animeService: animeService,
        leftPadding: leftPadding,
        rightPadding: rightPadding,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Stack(
        children: [
          const Positioned.fill(child: DesktopBackground()),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(leftPadding, 24, rightPadding, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header
                  _buildHeader(context, collections.length),

                  const SizedBox(height: 24),

                  // Collections Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    clipBehavior: Clip.none,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 320,
                          mainAxisExtent: 180,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: collections.length,
                    itemBuilder: (context, index) {
                      final col = collections[index];
                      return _buildCollectionCard(context, col, storageService);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.brandRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'CURATED FOLDERS',
                  style: TextStyle(
                    color: AppColors.brandRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Smart Collections',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$count collections',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // New Collection Button
        DesktopFocusWrapper.builder(
          onTap: () => _showCreateCollectionDialog(context),
          borderRadius: AppRadii.control,
          builder: (context, isFocused, isHovered) {
            final active = isFocused || isHovered;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.brandRed : AppColors.surface,
                borderRadius: AppRadii.control,
                border: Border.all(
                  color: active ? AppColors.brandRed : AppColors.border,
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: active ? Colors.white : AppColors.brandRed,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'New Collection',
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCollectionCard(
    BuildContext context,
    AnimeCollection col,
    StorageService storage,
  ) {
    final isCustom = !col.id.startsWith('col_');
    final count = col.animeIds.length;

    // Get sample preview artwork if available
    String? previewUrl;
    if (col.animeIds.isNotEmpty) {
      final sample = storage.getCachedAnimeById(col.animeIds.first);
      previewUrl = sample?.backdropUrl.isNotEmpty == true
          ? sample!.backdropUrl
          : sample?.posterUrl;
    }

    return DesktopFocusWrapper.builder(
      onTap: () => setState(() => _selectedCollection = col),
      borderRadius: AppRadii.card,
      builder: (context, isFocused, isHovered) {
        final active = isFocused || isHovered;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: active ? AppColors.hoverState : AppColors.surface,
            borderRadius: AppRadii.card,
            border: Border.all(
              color: active ? AppColors.brandRed : AppColors.border,
              width: 1.0,
            ),
            boxShadow: active ? const [AppColors.shadowSoft] : null,
          ),
          child: Stack(
            children: [
              // Background Artwork preview
              if (previewUrl != null && previewUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: AppRadii.card,
                  child: Opacity(
                    opacity: active ? 0.35 : 0.15,
                    child: WebSafeImage(
                      url: previewUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),

              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.brandRed
                                : AppColors.brandRed.withValues(alpha: 0.15),
                            borderRadius: AppRadii.control,
                          ),
                          child: Icon(
                            Icons.folder_special_rounded,
                            size: 16,
                            color: active ? Colors.white : AppColors.brandRed,
                          ),
                        ),
                        if (isCustom)
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () =>
                                _showDeleteCollectionDialog(context, col),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          col.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count titles',
                          style: TextStyle(
                            color: active
                                ? AppColors.brandRed
                                : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollectionDetailView({
    required BuildContext context,
    required AnimeCollection collection,
    required StorageService storageService,
    required AnimeService animeService,
    required double leftPadding,
    required double rightPadding,
  }) {
    // Resolve anime objects
    final animeList = collection.animeIds
        .map((id) => storageService.getCachedAnimeById(id))
        .whereType<Anime>()
        .toList();

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Stack(
        children: [
          const Positioned.fill(child: DesktopBackground()),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(leftPadding, 24, rightPadding, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back to collections bar
                  Row(
                    children: [
                      DesktopFocusWrapper.builder(
                        autofocus: true,
                        onTap: () => setState(() => _selectedCollection = null),
                        borderRadius: AppRadii.control,
                        builder: (context, isFocused, isHovered) {
                          final active = isFocused || isHovered;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.brandRed
                                  : AppColors.surface,
                              borderRadius: AppRadii.control,
                              border: Border.all(
                                color: active
                                    ? AppColors.brandRed
                                    : AppColors.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.arrow_back_rounded,
                                  size: 15,
                                  color: active
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'All Collections',
                                  style: TextStyle(
                                    color: active
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      Text(
                        collection.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '(${animeList.length} items)',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  if (animeList.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 60,
                        horizontal: 24,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.folder_open_rounded,
                            size: 48,
                            color: AppColors.brandRed,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No anime added to this collection yet',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'You can add anime to collections directly from any Anime Details screen.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          DesktopFocusWrapper(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => context.go('/discover'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandRed,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Explore Anime',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      clipBehavior: Clip.none,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 215,
                            mainAxisExtent: 310,
                            crossAxisSpacing: 18,
                            mainAxisSpacing: 22,
                          ),
                      itemCount: animeList.length,
                      itemBuilder: (context, index) {
                        final anime = animeList[index];
                        return AnimeCard(
                          anime: anime,
                          width: double.infinity,
                          height: double.infinity,
                          layout: AnimeCardLayout.poster,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
