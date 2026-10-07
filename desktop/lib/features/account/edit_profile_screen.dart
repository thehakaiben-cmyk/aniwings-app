import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../widgets/desktop_focus_wrapper.dart';
import '../../widgets/desktop_page_shell.dart';
import '../../widgets/desktop_layout.dart';
import 'choose_avatar_sheet.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _usernameController;
  final _formKey = GlobalKey<FormState>();
  String? _pendingAvatarUrl;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider);
    _usernameController = TextEditingController(text: user?.username ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  bool _isSaving = false;

  Widget _buildAvatarWidget({
    required String? avatarUrl,
    required String username,
    required double radius,
  }) {
    final diameter = radius * 2;
    Widget imageChild;

    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      final url = avatarUrl.trim();
      if (url.startsWith('data:image')) {
        try {
          final base64Content = url.split(',').last;
          final bytes = base64Decode(base64Content);
          imageChild = Image.memory(
            bytes,
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildFallbackAvatar(username, radius),
          );
        } catch (_) {
          imageChild = _buildFallbackAvatar(username, radius);
        }
      } else if (url.startsWith('assets/')) {
        imageChild = Image.asset(
          url,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildFallbackAvatar(username, radius),
        );
      } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
        try {
          final cleanPath = url.replaceFirst('file://', '');
          final file = File(cleanPath);
          if (file.existsSync()) {
            imageChild = Image.file(
              file,
              width: diameter,
              height: diameter,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _buildFallbackAvatar(username, radius),
            );
          } else {
            imageChild = _buildFallbackAvatar(username, radius);
          }
        } catch (_) {
          imageChild = _buildFallbackAvatar(username, radius);
        }
      } else {
        imageChild = Image.network(
          url,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildFallbackAvatar(username, radius),
        );
      }
    } else {
      imageChild = _buildFallbackAvatar(username, radius);
    }

    return ClipOval(
      child: SizedBox(width: diameter, height: diameter, child: imageChild),
    );
  }

  Widget _buildFallbackAvatar(String username, double radius) {
    final initial = username.trim().isNotEmpty
        ? username.trim()[0].toUpperCase()
        : 'A';
    return Container(
      color: AppColors.accentPrimary.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: AppColors.accentPrimary,
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showChooseAvatarSheet(BuildContext context, User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ChooseAvatarSheet(
          currentAvatarUrl: _pendingAvatarUrl ?? user.avatarUrl,
          onAvatarSelected: (selectedUrl) {
            setState(() {
              _pendingAvatarUrl = selectedUrl;
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider);
    if (user == null) {
      return DesktopPageShell(
        onRootBack: () =>
            context.canPop() ? context.pop() : context.go('/home'),
        child: Scaffold(
          backgroundColor: AppColors.primaryBg,
          body: DesktopPageBackdrop(
            child: SafeArea(
              child: Column(
                children: [
                  DesktopPageHeader(
                    leading: DesktopBackButton(
                      autofocus: true,
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/home'),
                    ),
                    eyebrow: 'ACCOUNT',
                    title: 'Edit Profile',
                  ),
                  const Expanded(
                    child: DesktopEmptyState(
                      icon: Icons.account_circle_outlined,
                      title: 'User not found.',
                      message: 'Sign in again before editing this profile.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                    autofocus: false,
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/home'),
                  ),
                  eyebrow: 'ACCOUNT',
                  title: 'Edit Profile',
                  subtitle: 'Avatar and display name for this desktop profile',
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      DesktopLayout.pagePadding(context),
                      0,
                      DesktopLayout.pagePadding(context),
                      32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 920),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar Edit Section
                              Center(
                                child: Builder(
                                  builder: (context) {
                                    final avatarChooser = Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Hero(
                                          tag: 'profile_avatar_hero',
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: AppColors.accentPrimary,
                                                width: 3,
                                              ),
                                            ),
                                            child: _buildAvatarWidget(
                                              avatarUrl:
                                                  _pendingAvatarUrl ??
                                                  user.avatarUrl,
                                              username: user.username,
                                              radius: 56,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: const BoxDecoration(
                                              color: AppColors.accentPrimary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.edit_rounded,
                                              color: Colors.black,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );

                                    return DesktopFocusWrapper(
                                      onTap: () =>
                                          _showChooseAvatarSheet(context, user),
                                      borderRadius: BorderRadius.circular(64),
                                      focusedScale: 1.04,
                                      child: avatarChooser,
                                    );
                                  },
                                ),
                              ),
                              SizedBox(height: (44)),

                              // Name field
                              Text(
                                'Full Name',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: (17),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _usernameController,
                                autofocus: true,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: (18),
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Enter your name',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Name cannot be empty.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),

                              // Email field (read-only)
                              Text(
                                'Email (Cannot be changed)',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: (17),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: user.email,
                                readOnly: true,
                                canRequestFocus: false,
                                style: TextStyle(
                                  color: AppColors.textPrimary.withValues(
                                    alpha: 0.5,
                                  ),
                                  fontSize: (18),
                                ),
                                decoration: InputDecoration(
                                  fillColor: AppColors.elevatedSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              SizedBox(height: (52)),

                              // Save button
                              SizedBox(
                                width: double.infinity,
                                height: (58),
                                child: ElevatedButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () async {
                                          if (!_formKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                          setState(() {
                                            _isSaving = true;
                                          });
                                          try {
                                            final newName = _usernameController
                                                .text
                                                .trim();
                                            final updatedUser = User(
                                              id: user.id,
                                              email: user.email,
                                              username: newName,
                                              avatarUrl:
                                                  _pendingAvatarUrl ??
                                                  user.avatarUrl,
                                              createdAt: user.createdAt,
                                              totalHoursWatched:
                                                  user.totalHoursWatched,
                                              favoriteGenre: user.favoriteGenre,
                                              authProvider: user.authProvider,
                                            );
                                            await ref
                                                .read(
                                                  authStateProvider.notifier,
                                                )
                                                .updateUser(updatedUser);
                                            if (context.mounted) {
                                              context.pop();
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Profile updated successfully!',
                                                  ),
                                                  backgroundColor:
                                                      AppColors.accentPrimary,
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() {
                                                _isSaving = false;
                                              });
                                            }
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accentPrimary,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(26),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.black,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : Text(
                                          'Save Changes',
                                          style: TextStyle(
                                            fontSize: (17),
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
