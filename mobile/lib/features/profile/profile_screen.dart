import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/user_profile.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _medicalNotesController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  void _loadProfileData() {
    final profile = ref.read(userProfileProvider);
    if (profile != null) {
      _nameController.text = profile.fullName;
      _phoneController.text = profile.phoneNumber ?? '';
      _bloodGroupController.text = profile.bloodGroup ?? '';
      _medicalNotesController.text = profile.medicalNotes ?? '';
      _contactNameController.text = profile.emergencyContactName ?? '';
      _contactPhoneController.text = profile.emergencyContactPhone ?? '';
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final current = ref.read(userProfileProvider);
    final supabase = ref.read(supabaseServiceProvider);

    final updated = UserProfile(
      id: current?.id ?? supabase.currentUser?.id ?? 'LOCAL_USER',
      fullName: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'Civilian Responder',
      phoneNumber: _phoneController.text.trim(),
      email: current?.email ?? supabase.currentUser?.email,
      bloodGroup: _bloodGroupController.text.trim(),
      medicalNotes: _medicalNotesController.text.trim(),
      emergencyContactName: _contactNameController.text.trim(),
      emergencyContactPhone: _contactPhoneController.text.trim(),
      createdAt: current?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(userProfileProvider.notifier).updateProfile(updated);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile successfully updated!'),
          backgroundColor: AppColors.successGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.emergencyRed),
            SizedBox(width: 8),
            Text('Log Out from SORYNTH?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out of your SORYNTH account? '
          'Your offline emergency records, pending transmissions, and local '
          'safety settings will remain safely stored on this device.\n\n'
          'Guest SOS remains accessible at all times without logging in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergencyRed,
              foregroundColor: AppColors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final supabase = ref.read(supabaseServiceProvider);
      await supabase.signOut();
      ref.read(userProfileProvider.notifier).clear();
      if (mounted) {
        context.go(AppRoutes.login);
      }
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Recent';
    try {
      final dt = DateTime.parse(isoString);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return isoString.split('T').first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bloodGroupController.dispose();
    _medicalNotesController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final supabase = ref.watch(supabaseServiceProvider);
    final currentUser = supabase.currentUser;
    final isAuthenticated = currentUser != null;

    // Determine avatar URL if any
    final avatarUrl = currentUser?.userMetadata?['avatar_url']?.toString() ??
        currentUser?.userMetadata?['picture']?.toString();
    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : (currentUser?.userMetadata?['full_name']?.toString() ??
            currentUser?.userMetadata?['name']?.toString() ??
            (isAuthenticated ? 'Civilian Responder' : 'Guest Civilian'));
    final emailDisplay = currentUser?.email ?? profile?.email ?? (isAuthenticated ? 'No email' : 'Guest Session');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isAuthenticated)
            IconButton(
              icon: Icon(_isEditing ? Icons.close_rounded : Icons.edit_rounded),
              tooltip: _isEditing ? 'Cancel Editing' : 'Edit Medical Profile',
              onPressed: () {
                setState(() {
                  _isEditing = !_isEditing;
                  if (!_isEditing) _loadProfileData();
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'App Settings',
            onPressed: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // User Avatar Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borderColor),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 42,
                          backgroundColor:
                              AppColors.primaryBlue.withValues(alpha: 0.12),
                          child: ClipOval(
                            child: (avatarUrl != null && avatarUrl.isNotEmpty)
                                ? Image.network(
                                    avatarUrl,
                                    width: 84,
                                    height: 84,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                      Icons.person_rounded,
                                      size: 48,
                                      color: AppColors.primaryBlue,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_rounded,
                                    size: 48,
                                    color: AppColors.primaryBlue,
                                  ),
                          ),
                        ),
                        if (isAuthenticated)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.successGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified_user_rounded,
                              size: 14,
                              color: AppColors.white,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      emailDisplay,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    if (isAuthenticated) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          'AUTHENTICATED CIVILIAN RESPONDER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // GUEST BANNER (If not authenticated)
              if (!isAuthenticated) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              color: AppColors.primaryBlue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Guest Emergency Session',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'You are using SORYNTH in guest emergency mode without an authenticated account. '
                        'Guest SOS alerts, GPS coordinates, and offline transmissions are fully supported. '
                        'Sign in to link alerts to your permanent identity.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 42),
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: AppColors.white,
                        ),
                        onPressed: () => context.push(AppRoutes.login),
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: const Text('Sign In / Register Account'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // AUTHENTICATED ACCOUNT DETAILS (Only if authenticated)
              if (isAuthenticated) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_circle_outlined,
                              color: AppColors.primaryBlue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Account Details',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: primaryTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // UID with copy option
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'User ID (UID)',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    currentUser.id.length > 10
                                        ? '${currentUser.id.substring(0, 6)}...${currentUser.id.substring(currentUser.id.length - 4)}'
                                        : currentUser.id,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w700,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Copy UID',
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: currentUser.id));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('User ID copied to clipboard'),
                                        duration: Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      Divider(height: 18, color: borderColor),

                      // Email Verification Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Email Status',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (currentUser.emailConfirmedAt != null)
                                    ? AppColors.successGreen
                                        .withValues(alpha: 0.12)
                                    : AppColors.warningYellow
                                        .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    currentUser.emailConfirmedAt != null
                                        ? Icons.check_circle_rounded
                                        : Icons.pending_rounded,
                                    size: 13,
                                    color: currentUser.emailConfirmedAt != null
                                        ? AppColors.successGreen
                                        : AppColors.warningYellow,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      currentUser.emailConfirmedAt != null
                                          ? 'Verified'
                                          : 'Pending Verification',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: currentUser.emailConfirmedAt != null
                                            ? AppColors.successGreen
                                            : AppColors.warningYellow,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      Divider(height: 18, color: borderColor),

                      // Auth Provider
                      _buildProfileRow(
                        'Authentication',
                        (currentUser.appMetadata['provider'] ?? 'email')
                            .toString()
                            .toUpperCase(),
                      ),

                      Divider(height: 18, color: borderColor),

                      // Member Since
                      _buildProfileRow(
                        'Member Since',
                        _formatDate(currentUser.createdAt),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Emergency Medical & Contact Info
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Rescue Medical Profile',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: primaryTextColor,
                          ),
                        ),
                        if (_isEditing)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(80, 36),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            onPressed: _isSaving ? null : _saveProfile,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                          AppColors.white),
                                    ),
                                  )
                                : const Text('Save',
                                    style: TextStyle(fontSize: 13)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (_isEditing) ...[
                      TextFormField(
                        controller: _nameController,
                        decoration:
                            const InputDecoration(labelText: 'Full Name'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _phoneController,
                        decoration:
                            const InputDecoration(labelText: 'Phone Number'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _bloodGroupController,
                        decoration: const InputDecoration(
                            labelText: 'Blood Group (e.g. O+)'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _medicalNotesController,
                        decoration: const InputDecoration(
                            labelText: 'Allergies / Critical Medical Notes'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _contactNameController,
                        decoration: const InputDecoration(
                            labelText: 'Primary Emergency Contact Name'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _contactPhoneController,
                        decoration: const InputDecoration(
                            labelText: 'Emergency Contact Phone'),
                      ),
                    ] else ...[
                      _buildProfileRow('Blood Group',
                          profile?.bloodGroup ?? 'Not Specified'),
                      Divider(height: 18, color: borderColor),
                      _buildProfileRow('Medical Notes',
                          profile?.medicalNotes ?? 'None recorded'),
                      Divider(height: 18, color: borderColor),
                      _buildProfileRow('Emergency Contact',
                          profile?.emergencyContactName ?? 'None recorded'),
                      Divider(height: 18, color: borderColor),
                      _buildProfileRow('Contact Phone',
                          profile?.emergencyContactPhone ?? 'Not Provided'),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Settings & System Navigation Card
              Material(
                color: cardBg,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: borderColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.settings_outlined,
                              color: AppColors.primaryBlue, size: 20),
                        ),
                        title: Text(
                          'Settings & System Preferences',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                        subtitle: Text(
                          'Notifications, theme, radio diagnostics & safety',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                        trailing: Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: secondaryTextColor),
                        onTap: () => context.push(AppRoutes.settings),
                      ),
                      Divider(height: 1, color: borderColor),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.history_rounded,
                              color: AppColors.primaryBlue, size: 20),
                        ),
                        title: Text(
                          'Emergency SOS Logs',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                        subtitle: Text(
                          'Review prior local & cloud emergency dispatches',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                        trailing: Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: secondaryTextColor),
                        onTap: () => context.push(AppRoutes.history),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Logout Button (ONLY FOR AUTHENTICATED USERS)
              if (isAuthenticated) ...[
                OutlinedButton.icon(
                  onPressed: _logout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.emergencyRed,
                    side: const BorderSide(color: AppColors.emergencyRed, width: 1.5),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'Log Out from Account',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Logging out does not delete offline emergency records or active SOS transmissions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: secondaryTextColor,
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final secondaryTextColor =
        isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
        ),
      ],
    );
  }
}
