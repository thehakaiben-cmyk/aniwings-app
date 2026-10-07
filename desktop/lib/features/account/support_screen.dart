import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/desktop_page_shell.dart';
import '../../widgets/desktop_layout.dart';

enum _FaqCategory {
  all('All', Icons.grid_view_rounded, AppColors.brandRed),
  general('General', Icons.desktop_windows_rounded, Color(0xFF5C6BC0)),
  streaming('Servers & Streaming', Icons.dns_rounded, Color(0xFFE53935)),
  providers('Providers & Catalog', Icons.dataset_rounded, Color(0xFF4A90E2)),
  audio('Audio & Subtitles', Icons.subtitles_rounded, Color(0xFF8E24AA)),
  enhancement(
    'Video Enhancement',
    Icons.auto_awesome_rounded,
    Color(0xFF00E676),
  ),
  sync('Sync & Watchlist', Icons.sync_rounded, Color(0xFF00ACC1)),
  milestones(
    'Milestones & Badges',
    Icons.military_tech_rounded,
    Color(0xFFFFB300),
  ),
  downloads('Downloads & Offline', Icons.download_rounded, Color(0xFF43A047));

  final String label;
  final IconData icon;
  final Color iconColor;

  const _FaqCategory(this.label, this.icon, this.iconColor);
}

class _FaqItem {
  final String question;
  final String answer;
  final IconData icon;
  final _FaqCategory category;

  const _FaqItem({
    required this.question,
    required this.answer,
    required this.icon,
    required this.category,
  });
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _FaqCategory _selectedCategory = _FaqCategory.all;
  String? _expandedQuestion;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const List<_FaqItem> _faqs = [
    // 1. General
    _FaqItem(
      question: 'How do I sign in and sync my desktop account?',
      answer:
          'Sign in with your AniWings account to sync your desktop library:\n\n'
          '• Sign in with your AniWings account on Desktop to immediately sync your Watchlist, Custom Lists, and Continue Watching history.\n'
          '• Keyboard shortcuts (Ctrl+K, F for fullscreen, M for mute, Space for play/pause, Arrow keys for navigation) make Desktop navigation swift and seamless.',
      icon: Icons.qr_code_scanner_rounded,
      category: _FaqCategory.general,
    ),
    _FaqItem(
      question:
          'How do the Live 7-Day Airing Schedule and release countdowns work?',
      answer:
          'AniWings cross-references broadcast schedules directly across AniList and Jikan (MyAnimeList) in real time:\n\n'
          '• Releasing: Shows the exact released episode number and next episode countdown converted to your local system timezone.\n'
          '• Upcoming: Highlights announced anime series, premiere seasons, and key visual artworks before Episode 1 airs.\n'
          '• Completed: Marks finished titles with full episode catalogs.',
      icon: Icons.calendar_month_outlined,
      category: _FaqCategory.general,
    ),
    _FaqItem(
      question:
          'How do I enable high refresh rate and smooth inertial scrolling?',
      answer:
          'AniWings Desktop features native desktop scroll physics with hardware-accelerated animations calibrated for 120Hz/144Hz/240Hz monitors. If you experience stutters, check Settings > Appearance to choose between compact, standard, and spacious layouts.',
      icon: Icons.speed_rounded,
      category: _FaqCategory.general,
    ),

    // 2. Servers & Streaming
    _FaqItem(
      question:
          'What are the differences between Gojo, Kakashi, Luffy, Tanjiro, Zoro, Ichigo, Nezuko, Levi, Eren, and Mikasa servers?',
      answer:
          'AniWings features dedicated built-in streaming servers optimized for high-availability playback:\n\n'
          '• Gojo: Primary high-speed multi-quality server (1080p, 720p, 480p, 360p) with synchronized soft subtitles.\n'
          '• Kakashi: Ultra-fast low-latency CDN streaming server with synchronized subtitle tracks.\n'
          '• Luffy: Global hybrid direct streaming server optimized for both Japanese anime and Chinese donghua.\n'
          '• Tanjiro: Low-bandwidth optimized streaming server with comprehensive multi-subtitle tracks.\n'
          '• Zoro: Fast adaptive streaming provider supporting both MAL and AniList catalog IDs.\n'
          '• Ichigo: High-performance direct video streaming server with low buffering.\n'
          '• Nezuko: Multi-audio server offering Japanese audio with English subtitles, plus regional dubs.\n'
          '• Levi: High-bitrate torrent streaming server delivering pristine, uncompressed Blu-ray releases.\n'
          '• Eren: High-speed torrent streaming server optimized for rapid episode discovery and peer swarms.\n'
          '• Mikasa: Precision anime torrent streaming server featuring verified releases and multi-source fallbacks.\n\n'
          'Select your preferred default server anytime in Settings > Playback.',
      icon: Icons.dns_rounded,
      category: _FaqCategory.streaming,
    ),
    _FaqItem(
      question: 'How do Auto-Skip Intro & Outro and Quick Skip work?',
      answer:
          'AniWings integrates crowd-verified episode timing data from SkipTimes:\n\n'
          '• Auto-Skip Intro & Outro: When enabled in Settings > Playback, the player automatically seeks past opening (OP) and ending (ED) themes without requiring manual clicks.\n'
          '• Quick Skip (+85s): A prompt appears on screen during openings allowing a single click or remote select to skip the theme.',
      icon: Icons.fast_forward_rounded,
      category: _FaqCategory.streaming,
    ),
    _FaqItem(
      question: 'What should I do if a stream buffers or fails to load?',
      answer:
          '1. Switch Servers: Click the "Switch Server" button on the video player or press S to pick an alternative server (e.g., switch from Gojo to Kakashi or Luffy).\n'
          '2. Secure DNS (DoH): In Settings > Playback, switch Secure DNS Mode to 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google) to bypass ISP throttling or DNS blocking.\n'
          '3. Flush Cache: In Settings > Data & Cache, click "Flush Image Memory Cache" to free memory.',
      icon: Icons.refresh_rounded,
      category: _FaqCategory.streaming,
    ),
    _FaqItem(
      question: 'Does AniWings support Chinese anime (Donghua) series?',
      answer:
          'Yes! AniWings automatically detects Donghua series (including Battle Through the Heavens, Perfect World, Renegade Immortal, and Soul Land) and routes them to compatible servers (Luffy, Nezuko, etc.) with accurate season-cumulative episode numbers.',
      icon: Icons.auto_stories_rounded,
      category: _FaqCategory.streaming,
    ),

    // 3. Metadata & Catalog Providers
    _FaqItem(
      question:
          'How do I switch the metadata provider between MyAnimeList and AniList?',
      answer:
          'You can switch your primary catalog in Settings > Metadata Provider:\n\n'
          '• MyAnimeList (MAL): Comprehensive community scores, rankings, and broadcast schedules via Jikan.\n'
          '• AniList: Modern seasonal charts, HD banners, real-time airing countdowns, and rich tags.\n\n'
          'Your Watchlist and Continue Watching history remain completely safe regardless of provider choice.',
      icon: Icons.dataset_rounded,
      category: _FaqCategory.providers,
    ),

    // 4. Audio & Subtitles
    _FaqItem(
      question: 'How do I switch between Sub (Japanese) and English Dub?',
      answer:
          '• In the Player: Click the SUB / DUB toggle button in the player overlay to switch streams on the fly.\n'
          '• Global Default: Go to Settings > Playback > Audio Preference to select SUB or DUB as your global preference.',
      icon: Icons.record_voice_over_rounded,
      category: _FaqCategory.audio,
    ),
    _FaqItem(
      question: 'How do I customize subtitle font size, colors, and styling?',
      answer:
          'Navigate to Settings > Playback > Subtitle Appearance (click "Customize") or open the route /subtitle-settings. You can adjust:\n\n'
          '• Font size (12px to 32px)\n'
          '• Text styling (Normal, Bold, Italic)\n'
          '• Text color and background box opacity\n'
          '• Text outline shadow intensity and vertical bottom positioning.',
      icon: Icons.subtitles_outlined,
      category: _FaqCategory.audio,
    ),

    // 5. Sync & Watchlist
    _FaqItem(
      question: 'How does MyAnimeList (MAL) and AniList sync work?',
      answer:
          '1. Go to Settings > Account & Profile > External List Sync or navigate to /sync.\n'
          '2. Click "Connect" for MyAnimeList or AniList to authenticate via secure OAuth2 PKCE.\n'
          '3. Episodes are automatically marked as watched once you reach 80% completion during playback.\n'
          '4. Click "Sync Now" anytime to pull external lists into AniWings or push local progress to the cloud.',
      icon: Icons.sync_rounded,
      category: _FaqCategory.sync,
    ),
    _FaqItem(
      question: 'How do Canon and Filler episode indicators work?',
      answer:
          'AniWings highlights manga canon and anime-original filler episodes:\n\n'
          '• Canon Episodes: Standard dark slate episode tiles.\n'
          '• Filler Episodes: Highlighted with an amber badge indicating anime-original filler arcs.\n'
          'On the Anime Details page, you can filter episode lists between All, Canon, and Filler with a single click.',
      icon: Icons.bookmark_added_rounded,
      category: _FaqCategory.sync,
    ),

    // 6. Milestones & Badges
    _FaqItem(
      question: 'How do watch-time milestones and cosmetic rewards work?',
      answer:
          'Watch anime to unlock cosmetic profile rewards and aura glows:\n\n'
          '• 2 Hours: Bronze Glow & Starter Badges\n'
          '• 5 Hours: Silver & Sapphire Neon\n'
          '• 10 Hours: Gold, Emerald & Ruby Glow\n'
          '• 50 Hours: Royal Amethyst & Cyberpunk Prism\n'
          '• 100+ Hours: Master Celestial Rainbow Glow & animated borders.',
      icon: Icons.military_tech_rounded,
      category: _FaqCategory.milestones,
    ),

    // 7. Downloads & Offline
    _FaqItem(
      question: 'Can I download episodes for offline viewing?',
      answer:
          'Open an anime details page and click Download episodes. Select one or more episodes, SUB or DUB, and quality. The Downloads tab shows progress, cancellation, retries and completed files. Watch offline opens the saved video in AniWings; text subtitles are saved when the source supplies them.',
      icon: Icons.download_done_rounded,
      category: _FaqCategory.downloads,
    ),
    _FaqItem(
      question: 'Where are downloads saved and how do I change quality?',
      answer:
          'Open Settings > Downloads > Download settings. Choose 1080P, 720P, 360P or Auto and your default SUB/DUB audio. Desktop files default to Downloads/AniWings; Android preview uses the app documents folder. Choose a custom folder if needed. Folder changes apply to new downloads; existing files keep their location. HLS selects the best available quality within your limit; direct video files keep their source quality.',
      icon: Icons.folder_open_rounded,
      category: _FaqCategory.downloads,
    ),
    _FaqItem(
      question: 'Will downloads continue if I close AniWings?',
      answer:
          'Keep AniWings open while downloading. You can navigate to other pages or minimize the desktop window. The queue is saved locally; if the app closes, unfinished transfers restart at the next launch. Completed episodes remain available offline.',
      icon: Icons.queue_rounded,
      category: _FaqCategory.downloads,
    ),
    _FaqItem(
      question: 'Why did an episode download fail?',
      answer:
          'A provider may be offline, lack the selected audio, or return an unsupported stream. AniWings tries other available downloadable sources and verifies media before saving it. Encrypted HLS and streams with separate audio may need another source. Check your connection, folder permissions and free disk space, then use Retry or choose a different audio option.',
      icon: Icons.error_outline,
      category: _FaqCategory.downloads,
    ),
    _FaqItem(
      question: 'How do I free download storage?',
      answer:
          'Open Downloads and select Remove beside a completed episode. Confirm to delete its saved video and subtitle file. Removing a cancelled or failed entry clears that record. Files moved or deleted outside AniWings appear as missing and can be downloaded again.',
      icon: Icons.delete_outline,
      category: _FaqCategory.downloads,
    ),
  ];

  List<_FaqItem> get _filteredFaqs {
    final query = _searchQuery.trim().toLowerCase();
    final hasQuery = query.isNotEmpty;
    final hasCategory = _selectedCategory != _FaqCategory.all;

    return _faqs.where((faq) {
      if (hasCategory && faq.category != _selectedCategory) return false;
      if (hasQuery) {
        return faq.question.toLowerCase().contains(query) ||
            faq.answer.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredFaqs;

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
                  eyebrow: 'HELP CENTER',
                  title: 'Frequently Asked Questions',
                  subtitle:
                      'Browse answers and troubleshooting guides for streaming, downloads, sync, and settings',
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      DesktopLayout.pagePadding(context),
                      0,
                      DesktopLayout.pagePadding(context),
                      40,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Search Bar
                            _buildSearchBar(),
                            const SizedBox(height: 16),

                            // 2. Category Filter Chips
                            _buildCategoryFilters(),
                            const SizedBox(height: 20),

                            // 3. Results Counter
                            Text(
                              'Showing ${filtered.length} ${filtered.length == 1 ? "answer" : "answers"}',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 4. FAQ Accordion List
                            if (filtered.isEmpty)
                              _buildEmptyFaqState()
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  final isExpanded =
                                      _expandedQuestion == item.question;
                                  return _buildFaqCard(item, isExpanded);
                                },
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

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondaryBg,
        borderRadius: AppRadii.control,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search FAQs, server guides, or sync instructions...',
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textMuted,
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _FaqCategory.values.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat.label),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = cat),
              avatar: Icon(
                cat.icon,
                size: 14,
                color: isSelected ? Colors.white : cat.iconColor,
              ),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              backgroundColor: AppColors.secondaryBg,
              selectedColor: AppColors.brandRed,
              side: BorderSide(
                color: isSelected ? AppColors.brandRed : AppColors.borderSubtle,
              ),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.control),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFaqCard(_FaqItem item, bool isExpanded) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: AppColors.secondaryBg,
        borderRadius: AppRadii.card,
        border: Border.all(
          color: isExpanded ? AppColors.brandRed : AppColors.borderSubtle,
          width: isExpanded ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _expandedQuestion = isExpanded ? null : item.question;
          });
        },
        borderRadius: AppRadii.card,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: item.category.iconColor.withValues(alpha: 0.15),
                      borderRadius: AppRadii.control,
                    ),
                    child: Icon(
                      item.icon,
                      color: item.category.iconColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.question,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 14),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 14),
                SelectableText(
                  item.answer,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyFaqState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.secondaryBg,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 14),
          const Text(
            'No matching questions found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try adjusting your search terms or switch the category filter to All.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedCategory = _FaqCategory.all;
              });
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.borderStrong),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: AppRadii.control),
            ),
            child: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }
}
