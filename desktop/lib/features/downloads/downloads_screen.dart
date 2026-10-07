import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/anime.dart';
import '../../models/episode.dart';
import '../../services/download_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/custom_video_player.dart';
import '../../widgets/desktop_layout.dart';
import '../../widgets/desktop_focus_wrapper.dart';

const downloadQualities = ['1080P', '720P', '360P', 'Auto'];

Future<void> showAnimeDownloadDialog(
  BuildContext context,
  Anime anime,
  List<Episode> episodes,
) => showDialog<void>(
  context: context,
  builder: (_) => _DownloadDialog(anime: anime, episodes: episodes),
);

class _DownloadDialog extends ConsumerStatefulWidget {
  final Anime anime;
  final List<Episode> episodes;
  const _DownloadDialog({required this.anime, required this.episodes});
  @override
  ConsumerState<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends ConsumerState<_DownloadDialog> {
  final Set<String> selected = {};
  String filter = '';
  late String quality;
  late String audio;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final storage = ref.read(storageServiceProvider);
    quality = storage.getDefaultDownloadQuality();
    audio = storage.getDefaultDownloadAudio();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.episodes
        .where(
          (episode) => '${episode.episodeNumber} ${episode.title}'
              .toLowerCase()
              .contains(filter.toLowerCase()),
        )
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.download_rounded,
                    color: AppColors.accentPrimary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Download episodes',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                widget.anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  DropdownButton<String>(
                    value: quality,
                    items: downloadQualities
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setState(() => quality = value!),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'SUB', label: Text('SUB')),
                      ButtonSegment(value: 'DUB', label: Text('DUB')),
                    ],
                    selected: {audio},
                    onSelectionChanged: saving
                        ? null
                        : (value) => setState(() => audio = value.single),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: 'Filter episodes'),
                onChanged: (value) => setState(() => filter = value),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(
                            () => selected.addAll(
                              visible.map((episode) => episode.id),
                            ),
                          ),
                    child: const Text('Select all visible'),
                  ),
                  TextButton(
                    onPressed: saving ? null : () => setState(selected.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final episode = visible[index];
                    return CheckboxListTile(
                      value: selected.contains(episode.id),
                      title: Text(
                        'Episode ${episode.episodeNumber} · ${episode.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: saving
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                selected.add(episode.id);
                              } else {
                                selected.remove(episode.id);
                              }
                            }),
                    );
                  },
                ),
              ),
              const Text(
                'Downloads continue while AniWings stays open. Quality and audio depend on the available source.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(
                  saving
                      ? 'Queuing…'
                      : 'Download ${selected.length} episode(s)',
                ),
                onPressed: saving || selected.isEmpty
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          await ref
                              .read(downloadServiceProvider)
                              .enqueue(
                                anime: widget.anime,
                                episodes: widget.episodes
                                    .where(
                                      (episode) =>
                                          selected.contains(episode.id),
                                    )
                                    .toList(),
                                quality: quality,
                                audio: audio,
                              );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Added to Downloads'),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            setState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Could not queue downloads: $error',
                                ),
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(downloadServiceProvider);
    final tasks = service.tasks.reversed.toList();
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Downloads',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/download-settings'),
                    icon: const Icon(Icons.settings),
                    label: const Text('Download settings'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/support'),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('FAQs'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Your download queue and offline episodes',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(
                        child: Text(
                          'Choose Download episodes on an anime details page to begin.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final exists =
                              task.path != null &&
                              File(task.path!).existsSync();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${task.anime.title} · Episode ${task.episode.episodeNumber}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${task.audio} · ${task.quality} · ${task.status.name}${task.status == DownloadStatus.downloading ? ' ${(task.progress * 100).toInt()}%' : ''}',
                                  ),
                                  if (task.status ==
                                          DownloadStatus.downloading ||
                                      task.status ==
                                          DownloadStatus.resolving) ...[
                                    const SizedBox(height: 10),
                                    LinearProgressIndicator(
                                      value:
                                          task.status ==
                                                  DownloadStatus.resolving ||
                                              task.progress == 0
                                          ? null
                                          : task.progress,
                                    ),
                                  ],
                                  if (task.path != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: SelectableText(
                                        exists
                                            ? task.path!
                                            : 'File is missing. Download this episode again.',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  if (task.error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        task.error!,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.danger,
                                        ),
                                      ),
                                    ),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      if (task.status ==
                                              DownloadStatus.completed &&
                                          exists)
                                        FilledButton.icon(
                                          onPressed: () =>
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      _OfflinePlayer(
                                                        task: task,
                                                      ),
                                                ),
                                              ),
                                          icon: const Icon(Icons.play_arrow),
                                          label: const Text('Watch offline'),
                                        ),
                                      if (task.active)
                                        TextButton(
                                          onPressed: () => service.cancel(task),
                                          child: const Text('Cancel'),
                                        ),
                                      if (!task.active &&
                                          (task.status !=
                                                  DownloadStatus.completed ||
                                              !exists))
                                        TextButton(
                                          onPressed: () => service.retry(task),
                                          child: const Text('Retry'),
                                        ),
                                      if (!task.active)
                                        TextButton(
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                  'Remove download?',
                                                ),
                                                content: const Text(
                                                  'This removes this download and its saved video and subtitle files.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text('Keep'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text('Remove'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              try {
                                                await service.remove(task);
                                              } catch (error) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Could not remove download: $error',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            }
                                          },
                                          child: const Text('Remove'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
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
}

class _OfflinePlayer extends StatelessWidget {
  final DownloadTask task;
  const _OfflinePlayer({required this.task});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: CustomVideoPlayer(
      videoUrls: [File(task.path!).uri.toString()],
      animeTitle: task.anime.title,
      episodeTitle: 'Episode ${task.episode.episodeNumber}',
      subtitleUrl: task.subtitlePath == null
          ? null
          : File(task.subtitlePath!).uri.toString(),
      autoPlayNext: false,
      isFullscreen: true,
      onBack: () => Navigator.pop(context),
    ),
  );
}

class DownloadSettingsScreen extends ConsumerStatefulWidget {
  const DownloadSettingsScreen({super.key});
  @override
  ConsumerState<DownloadSettingsScreen> createState() =>
      _DownloadSettingsState();
}

class _DownloadSettingsState extends ConsumerState<DownloadSettingsScreen> {
  late String quality;
  late String audio;
  String? directory;
  late final Future<Directory> defaultDirectory =
      DownloadService.defaultDirectory();

  @override
  void initState() {
    super.initState();
    final storage = ref.read(storageServiceProvider);
    quality = storage.getDefaultDownloadQuality();
    audio = storage.getDefaultDownloadAudio();
    directory = storage.getCustomDownloadDirectory();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb.toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.read(storageServiceProvider);
    final completedCount = ref
        .watch(downloadServiceProvider)
        .tasks
        .where((task) => task.status == DownloadStatus.completed)
        .length;

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: DesktopPageBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              DesktopPageHeader(
                leading: DesktopBackButton(
                  autofocus: true,
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/downloads'),
                ),
                eyebrow: 'DOWNLOADS & OFFLINE',
                title: 'Download Settings',
                subtitle:
                    'Configure default resolution, audio language, storage directory, and offline library',
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
                    48,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── 1. Defaults for new downloads ──────────────────────
                          const DesktopSectionHeader(
                            title: 'Defaults for New Downloads',
                            subtitle:
                                'Pre-selected resolution and audio track applied when queueing episodes',
                          ),
                          const SizedBox(height: 18),

                          // Video Quality Row
                          _buildSettingRow(
                            title: 'Video Quality Target',
                            description:
                                'Preferred stream resolution. HLS sources automatically select the highest available variant within this cap.',
                            control: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: downloadQualities.map((val) {
                                final isSelected = quality == val;
                                return DesktopFocusWrapper(
                                  onTap: () async {
                                    await storage.setDefaultDownloadQuality(val);
                                    if (mounted) setState(() => quality = val);
                                  },
                                  borderRadius: AppRadii.control,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.brandRed.withValues(alpha: 0.16)
                                          : AppColors.surface,
                                      borderRadius: AppRadii.control,
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.brandRed
                                            : AppColors.borderSubtle,
                                        width: isSelected ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSelected) ...[
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            size: 15,
                                            color: AppColors.brandRed,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          val,
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : AppColors.textSecondary,
                                            fontSize: 13,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Divider(color: AppColors.borderSubtle, height: 1),
                          const SizedBox(height: 16),

                          // Audio Track Row
                          _buildSettingRow(
                            title: 'Default Audio Language',
                            description:
                                'Select between original Japanese audio with soft/hard subtitles (SUB) or localized English dubbing (DUB).',
                            control: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildAudioOption(
                                  label: 'SUB (Subtitled)',
                                  icon: Icons.subtitles_rounded,
                                  isSelected: audio == 'SUB',
                                  onTap: () async {
                                    await storage.setDefaultDownloadAudio('SUB');
                                    if (mounted) setState(() => audio = 'SUB');
                                  },
                                ),
                                const SizedBox(width: 8),
                                _buildAudioOption(
                                  label: 'DUB (Dubbed)',
                                  icon: Icons.record_voice_over_rounded,
                                  isSelected: audio == 'DUB',
                                  onTap: () async {
                                    await storage.setDefaultDownloadAudio('DUB');
                                    if (mounted) setState(() => audio = 'DUB');
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),

                          // ── 2. Download Folder ─────────────────────────────────
                          const DesktopSectionHeader(
                            title: 'Download Folder',
                            subtitle:
                                'Destination directory on your local filesystem for saved episodes and subtitle files',
                          ),
                          const SizedBox(height: 18),

                          FutureBuilder<Directory>(
                            future: defaultDirectory,
                            builder: (context, snapshot) {
                              final currentPath = directory ??
                                  snapshot.data?.path ??
                                  (snapshot.hasError
                                      ? 'Default folder unavailable'
                                      : 'Locating default download folder…');
                              final isCustom = directory != null;

                              return Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: AppRadii.card,
                                  border: Border.all(color: AppColors.borderSubtle),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: AppColors.brandRed.withValues(
                                              alpha: 0.14,
                                            ),
                                            borderRadius: AppRadii.control,
                                          ),
                                          child: const Icon(
                                            Icons.folder_rounded,
                                            color: AppColors.brandRed,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    isCustom
                                                        ? 'Custom Storage Location'
                                                        : 'Default System Location',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isCustom
                                                          ? AppColors.brandRed
                                                              .withValues(alpha: 0.16)
                                                          : AppColors.elevatedSurface,
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                      border: Border.all(
                                                        color: isCustom
                                                            ? AppColors.brandRed
                                                                .withValues(alpha: 0.3)
                                                            : AppColors.borderSubtle,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      isCustom
                                                          ? 'Custom'
                                                          : 'Default',
                                                      style: TextStyle(
                                                        color: isCustom
                                                            ? AppColors.brandRed
                                                            : AppColors.textMuted,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              SelectableText(
                                                currentPath,
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontSize: 12.5,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    const Divider(
                                      color: AppColors.borderSubtle,
                                      height: 1,
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        DesktopFocusWrapper(
                                          onTap: () async {
                                            try {
                                              final path =
                                                  await FilePicker.getDirectoryPath(
                                                dialogTitle:
                                                    'Choose AniWings download folder',
                                              );
                                              if (path != null) {
                                                await storage
                                                    .setCustomDownloadDirectory(path);
                                                if (mounted) {
                                                  setState(() => directory = path);
                                                }
                                              }
                                            } catch (error) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Could not choose folder: $error',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          borderRadius: AppRadii.control,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.brandRed,
                                              borderRadius: AppRadii.control,
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.folder_open_rounded,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Choose Folder',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (isCustom) ...[
                                          const SizedBox(width: 10),
                                          DesktopFocusWrapper(
                                            onTap: () async {
                                              await storage
                                                  .setCustomDownloadDirectory(null);
                                              if (mounted) {
                                                setState(() => directory = null);
                                              }
                                            },
                                            borderRadius: AppRadii.control,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.elevatedSurface,
                                                borderRadius: AppRadii.control,
                                                border: Border.all(
                                                  color: AppColors.borderSubtle,
                                                ),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.restore_rounded,
                                                    size: 15,
                                                    color: AppColors.textSecondary,
                                                  ),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Reset to Default',
                                                    style: TextStyle(
                                                      color: AppColors.textPrimary,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        const Text(
                                          'Folder changes apply to new downloads only.',
                                          style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 36),

                          // ── 3. Storage & Offline Library ───────────────────────
                          const DesktopSectionHeader(
                            title: 'Storage & Offline Library',
                            subtitle:
                                'Local disk usage and downloaded media ready for offline watching',
                          ),
                          const SizedBox(height: 18),

                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: AppRadii.card,
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: AppColors.elevatedSurface,
                                          borderRadius: AppRadii.control,
                                          border: Border.all(
                                            color: AppColors.borderSubtle,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.download_done_rounded,
                                          color: AppColors.brandRed,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$completedCount Completed Episodes',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            'Saved to disk for offline viewing',
                                            style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 36,
                                  color: AppColors.borderSubtle,
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: FutureBuilder<int>(
                                    future: ref
                                        .read(downloadServiceProvider)
                                        .completedBytes(),
                                    builder: (context, snapshot) {
                                      final bytes = snapshot.data ?? 0;
                                      return Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: AppColors.elevatedSurface,
                                              borderRadius: AppRadii.control,
                                              border: Border.all(
                                                color: AppColors.borderSubtle,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.storage_rounded,
                                              color: AppColors.textSecondary,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _formatBytes(bytes),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              const Text(
                                                'Local disk storage occupied',
                                                style: TextStyle(
                                                  color: AppColors.textMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                DesktopFocusWrapper(
                                  onTap: () => context.go('/downloads'),
                                  borderRadius: AppRadii.control,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.elevatedSurface,
                                      borderRadius: AppRadii.control,
                                      border: Border.all(
                                        color: AppColors.borderStrong,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Manage Downloads',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 15,
                                          color: Colors.white70,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),

                          // ── 4. Transfer Guidance & FAQs ────────────────────────
                          const DesktopSectionHeader(
                            title: 'Download Guidance',
                            subtitle:
                                'How background downloads and adaptive video streams operate on desktop',
                          ),
                          const SizedBox(height: 18),

                          _buildGuidanceCard(
                            icon: Icons.sync_rounded,
                            title: 'Background Queue Processing',
                            description:
                                'Downloads continue seamlessly across app pages while AniWings is open. If closed or interrupted, uncompleted transfers resume automatically at next launch.',
                          ),
                          const SizedBox(height: 12),
                          _buildGuidanceCard(
                            icon: Icons.high_quality_rounded,
                            title: 'Adaptive Variant Selection',
                            description:
                                'HLS media streams automatically select the highest available quality stream within your chosen limit; direct files preserve source resolution and audio channels.',
                          ),
                          const SizedBox(height: 16),

                          // FAQs Banner
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: AppRadii.card,
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.help_outline_rounded,
                                  color: AppColors.brandRed,
                                  size: 22,
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Need Help or Troubleshooting?',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Explore comprehensive answers about offline playback, failed downloads, and storage in the Help Center.',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                DesktopFocusWrapper(
                                  onTap: () => context.push('/support'),
                                  borderRadius: AppRadii.control,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.elevatedSurface,
                                      borderRadius: AppRadii.control,
                                      border: Border.all(
                                        color: AppColors.borderSubtle,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Open FAQs',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(
                                          Icons.open_in_new_rounded,
                                          size: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),
                          const Center(
                            child: Text(
                              'Crafted by Cosmic Garou',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                                letterSpacing: 0.3,
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
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String description,
    required Widget control,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 28),
        control,
      ],
    );
  }

  Widget _buildAudioOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return DesktopFocusWrapper(
      onTap: onTap,
      borderRadius: AppRadii.control,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandRed.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: AppRadii.control,
          border: Border.all(
            color: isSelected ? AppColors.brandRed : AppColors.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.brandRed : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidanceCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: AppRadii.control,
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
