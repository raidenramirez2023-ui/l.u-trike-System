import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/env.dart';
import '../../core/landing_bg_data.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/models.dart';

final _auth = AuthController.instance;

// ---------------------------------------------------------------------------
// Shared auth scaffold: enterprise split panel on desktop / clean scroll on mobile
// ---------------------------------------------------------------------------
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  final UserRole? portal;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = true,
    this.portal,
  });

  Widget _buildPortalBadge(UserRole? p, String t, {bool light = false}) {
    final (icon, label, color, bg) = switch (p) {
      UserRole.student => (
          Icons.school_rounded,
          'STUDENT MOBILITY PORTAL',
          light ? Colors.white : AppColors.primary,
          light ? Colors.white.withValues(alpha: 0.12) : AppColors.primarySoft,
        ),
      UserRole.driver => (
          Icons.electric_rickshaw_rounded,
          'AUTHORIZED TODA DRIVER PORTAL',
          light ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
          light ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFFEF3C7),
        ),
      UserRole.admin => (
          Icons.shield_outlined,
          'CAMPUS TERMINAL OPERATIONS',
          light ? Colors.white : const Color(0xFF1E293B),
          light ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
        ),
      null => (
          Icons.lock_outline_rounded,
          'LU TRANSIT PLATFORM',
          light ? Colors.white : AppColors.primary,
          light ? Colors.white.withValues(alpha: 0.12) : AppColors.primarySoft,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: light ? Colors.white.withValues(alpha: 0.2) : color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthFooter(BuildContext context, UserRole? p) {
    return Column(
      children: [
        if (p == UserRole.student) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.radar_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Want to check passenger queue without signing in?',
                    style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/student'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text('Live Radar →', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else if (p == UserRole.driver) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.badge_outlined, size: 18, color: Color(0xFFD97706)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'First time driver at Laguna University?',
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/register/driver'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: const Color(0xFFB45309),
                  ),
                  child: const Text('Register →', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else if (p == UserRole.admin) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 16, color: AppColors.inkMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Laguna University Authorized Terminal Marshals Only',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.inkDisabled),
            SizedBox(width: 6),
            Text(
              'Laguna University Mobility Protocol · End-to-End Encrypted',
              style: TextStyle(fontSize: 11, color: AppColors.inkDisabled, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final hero = Container(
      decoration: const BoxDecoration(
        gradient: AppColors.meshHeroGradient,
      ),
      padding: EdgeInsets.fromLTRB(wide ? 48 : 24, wide ? 48 : 24, wide ? 48 : 24, wide ? 48 : 28),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (showBack)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: IconButton.filledTonal(
                          tooltip: 'Back to Home',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.12),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        ),
                      ),
                    const BrandMark(size: 34, light: true),
                  ],
                ),
                const SizedBox(height: 36),
                _buildPortalBadge(portal, title, light: true),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: wide ? 30 : 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: wide ? 14.5 : 13.5,
                    height: 1.45,
                  ),
                ),
                if (wide) ...[
                  const SizedBox(height: 32),
                  const _FeatureBullet(
                    icon: Icons.bolt_rounded,
                    title: 'Real-time Queue Updates',
                    subtitle: 'Live seat counts and queue positions sync instantly without manual refreshes.',
                  ),
                  const SizedBox(height: 16),
                  const _FeatureBullet(
                    icon: Icons.verified_user_rounded,
                    title: 'Verified Drivers & Vehicles',
                    subtitle: 'All tricycle operators are reviewed and authorized by LU transport marshals.',
                  ),
                  const SizedBox(height: 16),
                  const _FeatureBullet(
                    icon: Icons.timer_outlined,
                    title: 'Smart Commute Timing',
                    subtitle: 'Eliminate terminal crowd guessing—know bay availability before walking.',
                  ),
                ],
              ],
            ),
            if (wide)
              Container(
                margin: const EdgeInsets.only(top: 24),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.white70, size: 16),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Laguna University Mobility Protocol · Enterprise RLS Protected',
                        style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Row(
          children: [
            Expanded(flex: 5, child: hero),
            Expanded(
              flex: 6,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                  child: ResponsiveCenter(
                    maxWidth: 460,
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPortalBadge(portal, title),
                              const SizedBox(height: 10),
                              Text(
                                title,
                                style: AppText.pageTitle.copyWith(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: AppText.body.copyWith(fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                        AppCard(
                          padding: const EdgeInsets.all(28),
                          child: child,
                        ),
                        const SizedBox(height: 16),
                        _buildAuthFooter(context, portal),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 380;

    // Mobile / Tablet layout: vertically centered in viewport, zero dead whitespace
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: BrandMark(size: isNarrow ? 24 : 28, showSubtitle: !isNarrow),
        leading: showBack
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
              )
            : null,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableH = constraints.maxHeight;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isNarrow ? 14 : 20,
                vertical: 18,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (availableH - 36).clamp(0, double.infinity),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 16, left: 2, right: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPortalBadge(portal, title),
                              const SizedBox(height: 10),
                              Text(
                                title,
                                style: AppText.pageTitle.copyWith(
                                  fontSize: isNarrow ? 22 : 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: AppText.body.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        AppCard(
                          padding: EdgeInsets.all(isNarrow ? 18 : 24),
                          child: child,
                        ),
                        const SizedBox(height: 16),
                        _buildAuthFooter(context, portal),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureBullet({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String? text;
  const _ErrorText(this.text);
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Banner2(icon: Icons.error_outline_rounded, text: text!, fg: AppColors.danger, bg: AppColors.dangerSoft),
        );
}

String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
String? _validateEmail(String? v) =>
    (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'Enter a valid email address' : null;
String? _password(String? v) {
  if (v == null || v.length < 8) return 'At least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) return 'Use letters and numbers';
  return null;
}

String? _phone(String? v) =>
    (v == null || !RegExp(r'^(\+?63|0)9\d{9}$').hasMatch(v.replaceAll(RegExp(r'[\s-]'), ''))) ? 'Enter a valid PH mobile number (09XXXXXXXXX)' : null;

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputAction action;
  final VoidCallback? onSubmit;
  const PasswordField({super.key, required this.controller, this.label = 'Password', this.validator, this.action = TextInputAction.done, this.onSubmit});
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _hidden,
        validator: widget.validator,
        textInputAction: widget.action,
        onFieldSubmitted: (_) => widget.onSubmit?.call(),
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Landing – Enterprise Mobility Portal
// ---------------------------------------------------------------------------
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 900;
    final isMobile = screenWidth < 600;
    final isNarrow = screenWidth < 400;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        titleSpacing: isNarrow ? 8 : (wide ? 32 : 16),
        title: BrandMark(
          size: isNarrow ? 26 : (isMobile ? 28 : 32),
          showSubtitle: !isNarrow,
        ),
        actions: [
          if (screenWidth >= 640)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PulseDot(color: AppColors.primary, size: 6),
                  SizedBox(width: 6),
                  Text(
                    'SYSTEM ONLINE',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            )
          else if (screenWidth >= 440)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PulseDot(color: AppColors.primary, size: 6),
                  SizedBox(width: 5),
                  Text(
                    'ONLINE',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            )
          else
            Tooltip(
              message: 'LU Transit System Online',
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const PulseDot(color: AppColors.primary, size: 6),
              ),
            ),
          const SizedBox(width: 8),
          if (screenWidth >= 520)
            FilledButton.tonalIcon(
              onPressed: () => context.push('/login/driver'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFEF3C7),
                foregroundColor: const Color(0xFF92400E),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.two_wheeler_rounded, size: 16),
              label: const Text('Driver Portal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            )
          else
            Tooltip(
              message: 'Driver Portal',
              child: FilledButton.tonal(
                onPressed: () => context.push('/login/driver'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFEF3C7),
                  foregroundColor: const Color(0xFF92400E),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Icon(Icons.two_wheeler_rounded, size: 18),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Terminal Admin Access',
            icon: const Icon(Icons.shield_outlined, size: 18, color: AppColors.inkMuted),
            onPressed: () => context.push('/login/admin'),
          ),
          SizedBox(width: isNarrow ? 6 : (wide ? 24 : 12)),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero section with authentic cover photo (Tricycle Driver & Students)
            Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(
                    landingCoverBytes,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF064E3B).withValues(alpha: 0.78),
                          const Color(0xFF0F172A).withValues(alpha: 0.84),
                          const Color(0xFF0F172A).withValues(alpha: 0.94),
                        ],
                      ),
                    ),
                  ),
                ),
                ResponsiveCenter(
                  maxWidth: 1100,
                  padding: EdgeInsets.fromLTRB(
                    isNarrow ? 16 : (wide ? 32 : 20),
                    wide ? 48 : (isNarrow ? 22 : 28),
                    isNarrow ? 16 : (wide ? 32 : 20),
                    wide ? 68 : (isNarrow ? 38 : 44),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.hub_outlined, size: 13, color: Color(0xFF10B981)),
                              const SizedBox(width: 6),
                              Text(
                                isNarrow ? 'LU CAMPUS TRANSIT PLATFORM' : 'LAGUNA UNIVERSITY CAMPUS TRANSIT PLATFORM',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Real-Time Tricycle Terminal\n& Queue Management',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: wide ? 40 : (isNarrow ? 23 : 26),
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          'Eliminating queue guesswork and crowding for Laguna University. '
                          'Track live tricycle seat occupancy, sequence dispatching, and departures in real time.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: wide ? 16 : (isNarrow ? 13.5 : 14),
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: const [
                          _HeroFeatureChip(icon: Icons.bolt_rounded, label: 'Sub-second Realtime Sync'),
                          _HeroFeatureChip(icon: Icons.storefront_outlined, label: '2 Campus Terminals Active'),
                          _HeroFeatureChip(icon: Icons.verified_outlined, label: 'Authorized Driver Network'),
                        ],
                      ),
                      const SizedBox(height: 26),
                      // Primary Commuter CTA - Adapts dynamically to mobile
                      LayoutBuilder(
                        builder: (context, c) {
                          final isCompact = c.maxWidth < 460;
                          final studentBtn = FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 18, vertical: wide ? 15 : 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.school_rounded, size: 18),
                            label: const Text('Sign In as Student', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            onPressed: () => context.push('/login/student'),
                          );

                          final createBtn = OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
                              padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 16, vertical: wide ? 15 : 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                            ),
                            icon: const Icon(Icons.person_add_outlined, size: 18),
                            label: const Text('Create Student Account', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            onPressed: () => context.push('/register/student'),
                          );

                          final radarLink = TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF34D399),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.radar_rounded, size: 16),
                            label: const Text('View Live Terminal Radar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
                            onPressed: () => context.push('/student'),
                          );

                          if (isCompact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                studentBtn,
                                const SizedBox(height: 10),
                                createBtn,
                                const SizedBox(height: 4),
                                Align(alignment: Alignment.centerLeft, child: radarLink),
                              ],
                            );
                          }

                          return Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              studentBtn,
                              createBtn,
                              radarLink,
                            ],
                          );
                        },
                      ),
                      const _LiveTerminalTelemetryPreview(),
                    ],
                  ),
                ),
              ],
            ),

            // Production Commuter Features & Driver Network
            ResponsiveCenter(
              maxWidth: 1100,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section Header
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Text(
                          'CAMPUS COMMUTER EXPERIENCE',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Designed for Laguna University Students',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.4),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Real-time transit tools eliminating guesswork, long queues, and terminal crowding.',
                        style: TextStyle(fontSize: 13.5, color: AppColors.inkSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 3 Feature Cards
                  LayoutBuilder(
                    builder: (context, c) {
                      final wideCards = c.maxWidth >= 768;
                      const c1 = _CommuterFeatureCard(
                        icon: Icons.radar_rounded,
                        iconColor: AppColors.primary,
                        title: 'Live Bay Occupancy Radar',
                        description: 'Check actual seat availability in Bay 1 before leaving class. Sub-second Supabase WebSocket sync keeps counts updated live.',
                        tag: 'SUB-SECOND RADAR',
                      );
                      const c2 = _CommuterFeatureCard(
                        icon: Icons.cell_tower_rounded,
                        iconColor: Color(0xFF0284C7),
                        title: 'Gate Pick-up Signal Beacon',
                        description: 'Waiting at Gate 1 or Gate 2? Tap to signal student demand. Queued drivers get an instant alert with GPS coordinates and ETA.',
                        tag: 'DEMAND BEACON',
                      );
                      const c3 = _CommuterFeatureCard(
                        icon: Icons.balance_rounded,
                        iconColor: Color(0xFFD97706),
                        title: 'Fair FIFO TODA Dispatch',
                        description: 'Automated first-in, first-out sequence prevents queue cutting while guaranteeing official student discount fare matrices.',
                        tag: 'FAIR & TRANSPARENT',
                      );

                      if (wideCards) {
                        return const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: c1),
                            SizedBox(width: 16),
                            Expanded(child: c2),
                            SizedBox(width: 16),
                            Expanded(child: c3),
                          ],
                        );
                      }
                      return const Column(
                        children: [
                          c1,
                          SizedBox(height: 12),
                          c2,
                          SizedBox(height: 12),
                          c3,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),

                  // Dedicated Driver Operations Banner
                  const _DriverPartnerBanner(),
                ],
              ),
            ),

            // Enterprise Trust & Compliance Footer
            ResponsiveCenter(
              maxWidth: 1100,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
              child: Column(
                children: [
                  const Divider(height: 32),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.shield_outlined, size: 15, color: AppColors.inkMuted),
                          SizedBox(width: 6),
                          Text('Laguna University Smart Mobility Pilot', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.inkMuted),
                          SizedBox(width: 6),
                          Text('Atomic PostgreSQL Concurrency', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.sync_rounded, size: 15, color: AppColors.inkMuted),
                          SizedBox(width: 6),
                          Text('Realtime Supabase WebSocket Engine', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'LuTrike Digital Terminal & Queue Management System · Laguna University',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.inkMuted,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => context.push('/login/admin'),
                    icon: const Icon(Icons.shield_outlined, size: 14),
                    label: const Text('Terminal Administration & Operations Console', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroFeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroFeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF10B981)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveTerminalTelemetryPreview extends StatefulWidget {
  const _LiveTerminalTelemetryPreview();
  @override
  State<_LiveTerminalTelemetryPreview> createState() => _LiveTerminalTelemetryPreviewState();
}

class _LiveTerminalTelemetryPreviewState extends State<_LiveTerminalTelemetryPreview> {
  TerminalOverview? _overview;
  Terminal? _terminal;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await Api.terminals();
      if (!mounted || list.isEmpty) return;
      final t = list.first;
      final ov = await Api.overview(t.id);
      if (!mounted) return;
      setState(() {
        _terminal = t;
        _overview = ov;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _terminal == null || _overview == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCardNarrow = constraints.maxWidth < 480;

        final iconWidget = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const Icon(Icons.radar_rounded, color: Color(0xFF34D399), size: 18),
        );

        final textWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('LIVE TELEMETRY: ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF34D399), letterSpacing: 0.4)),
                Flexible(
                  child: Text(
                    _terminal!.name,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${_overview!.inQueue} in queue · ${_overview!.accepting} accepting · ${_overview!.ready} ready',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
        );

        final buttonWidget = FilledButton.tonal(
          onPressed: () => context.push('/student'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(36, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            foregroundColor: Colors.white,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Open Live Radar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              SizedBox(width: 5),
              Icon(Icons.arrow_forward_rounded, size: 13),
            ],
          ),
        );

        return Container(
          margin: const EdgeInsets.only(top: 22),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: isCardNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        iconWidget,
                        const SizedBox(width: 10),
                        Expanded(child: textWidget),
                      ],
                    ),
                    const SizedBox(height: 10),
                    buttonWidget,
                  ],
                )
              : Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 12),
                    Expanded(child: textWidget),
                    const SizedBox(width: 10),
                    buttonWidget,
                  ],
                ),
        );
      },
    );
  }
}

class _CommuterFeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String tag;

  const _CommuterFeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.2),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

class _DriverPartnerBanner extends StatelessWidget {
  const _DriverPartnerBanner();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;

    return Container(
      padding: EdgeInsets.all(wide ? 24 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: AppShadows.card,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color(0xFFFFFBEB),
          ],
        ),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: const Icon(Icons.electric_rickshaw_rounded, color: Color(0xFFD97706), size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Text(
                              'AUTHORIZED TODA NETWORK',
                              style: TextStyle(color: Color(0xFF92400E), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Are you a Laguna University Tricycle Driver?',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Join the active terminal bay queue, manage real-time passenger counts, and accept student gate pick-up beacons.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB45309),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Driver Sign In', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      onPressed: () => context.push('/login/driver'),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF92400E),
                        side: const BorderSide(color: Color(0xFFFCD34D)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      onPressed: () => context.push('/register/driver'),
                      child: const Text('Register Vehicle / Franchise', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Icon(Icons.electric_rickshaw_rounded, color: Color(0xFFD97706), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Text(
                        'AUTHORIZED TODA NETWORK',
                        style: TextStyle(color: Color(0xFF92400E), fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Are you a Laguna University Tricycle Driver?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Join the active terminal bay queue, manage real-time passenger counts, and accept student gate pick-up beacons.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSecondary, height: 1.4),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, c) {
                    final stack = c.maxWidth < 360;
                    final signInBtn = FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB45309),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      icon: const Icon(Icons.login_rounded, size: 15),
                      label: const Text('Driver Sign In', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                      onPressed: () => context.push('/login/driver'),
                    );
                    final regBtn = OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF92400E),
                        side: const BorderSide(color: Color(0xFFFCD34D)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      onPressed: () => context.push('/register/driver'),
                      child: const FittedBox(child: Text('Register Franchise', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    );

                    if (stack) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          signInBtn,
                          const SizedBox(height: 8),
                          regBtn,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: signInBtn),
                        const SizedBox(width: 8),
                        Expanded(child: regBtn),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login (one widget, three portals)
// ---------------------------------------------------------------------------
class LoginPage extends StatefulWidget {
  final UserRole portal;
  final String? next;
  const LoginPage({super.key, required this.portal, this.next});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signIn(_email.text, _pw.text, widget.portal);
      if (mounted && widget.next != null) context.go(widget.next!);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, sub) = switch (widget.portal) {
      UserRole.student => ('Student Sign In', 'Check the terminal queue in real time.'),
      UserRole.driver => ('Driver Sign In', 'Manage your queue position and passengers.'),
      UserRole.admin => ('Administrator Access', 'Authorized terminal managers only.'),
    };
    return AuthScaffold(
      portal: widget.portal,
      title: title,
      subtitle: sub,
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _ErrorText(_error),
            TextFormField(
              key: const Key('login-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
              decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.alternate_email_rounded)),
            ),
            const SizedBox(height: 14),
            PasswordField(controller: _pw, validator: _req, onSubmit: _submit),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push('/forgot-password'),
                style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 12.5)),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 6),
            FilledButton(
              key: const Key('login-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign in'),
            ),
            if (widget.portal != UserRole.admin) ...[
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('No account yet?', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
                TextButton(
                  onPressed: () => context.pushReplacement('/register/${widget.portal.name}'),
                  style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  child: const Text('Register'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Registration success panel (email confirmation)
// ---------------------------------------------------------------------------
class _RegisteredPanel extends StatelessWidget {
  final String email;
  final bool needsConfirm;
  final bool driver;
  const _RegisteredPanel({required this.email, required this.needsConfirm, required this.driver});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        EmptyState(
          icon: needsConfirm ? Icons.mark_email_unread_outlined : Icons.check_circle_outline_rounded,
          title: needsConfirm ? 'Confirm your email' : 'Registration submitted',
          message: [
            if (needsConfirm) 'We sent a confirmation link to $email. Open it, then sign in.',
            if (driver) 'Your driver account must be approved by an administrator before you can join a terminal queue.',
          ].join('\n\n'),
        ),
        FilledButton(onPressed: () => context.go('/login/${driver ? 'driver' : 'student'}'), child: const Text('Go to sign in')),
      ]);
}

// ---------------------------------------------------------------------------
// Student registration
// ---------------------------------------------------------------------------
class StudentRegisterPage extends StatefulWidget {
  const StudentRegisterPage({super.key});
  @override
  State<StudentRegisterPage> createState() => _StudentRegisterPageState();
}

class _StudentRegisterPageState extends State<StudentRegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _num = TextEditingController();
  final _email = TextEditingController();
  final _contact = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false, _agree = false;
  String? _error;
  bool? _needsConfirm;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_agree) return setState(() => _error = 'Please accept the data privacy notice.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final needs = await _auth.signUpStudent(
        fullName: _name.text,
        studentNumber: _num.text,
        email: _email.text,
        password: _pw.text,
        contactNo: _contact.text.isEmpty ? null : _contact.text,
      );
      setState(() => _needsConfirm = needs);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        portal: UserRole.student,
        title: 'Create Student Account',
        subtitle: 'Use your Laguna University student number to register.',
        child: _needsConfirm != null
            ? _RegisteredPanel(email: _email.text, needsConfirm: _needsConfirm!, driver: false)
            : Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _ErrorText(_error),
                  TextFormField(controller: _name, validator: _req, textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline_rounded))),
                  const SizedBox(height: 14),
                  TextFormField(controller: _num, validator: _req,
                      decoration: const InputDecoration(labelText: 'LU Student Number', prefixIcon: Icon(Icons.badge_outlined))),
                  const SizedBox(height: 14),
                  TextFormField(controller: _email, validator: _validateEmail, keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Email (institutional if available)', prefixIcon: Icon(Icons.alternate_email_rounded))),
                  const SizedBox(height: 14),
                  TextFormField(controller: _contact, keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.isEmpty) ? null : _phone(v),
                      decoration: const InputDecoration(labelText: 'Contact Number (optional)', prefixIcon: Icon(Icons.phone_outlined))),
                  const SizedBox(height: 14),
                  PasswordField(controller: _pw, validator: _password, action: TextInputAction.next),
                  const SizedBox(height: 14),
                  PasswordField(
                    controller: _pw2,
                    label: 'Confirm Password',
                    validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
                    onSubmit: _submit,
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agree,
                    onChanged: (v) => setState(() => _agree = v ?? false),
                    title: const Text(
                      'I agree that my name, student number and contact details are stored only to operate this queue system.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Creating account…' : 'Create Account')),
                ]),
              ),
      );
}

// ---------------------------------------------------------------------------
// Driver registration request
// ---------------------------------------------------------------------------
class DriverRegisterPage extends StatefulWidget {
  const DriverRegisterPage({super.key});
  @override
  State<DriverRegisterPage> createState() => _DriverRegisterPageState();
}

class _DriverRegisterPageState extends State<DriverRegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _contact = TextEditingController();
  final _plate = TextEditingController();
  final _license = TextEditingController();
  final _cap = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _terminalId;
  late final Future<List<Terminal>> _terminals = Api.terminals();
  bool _busy = false;
  String? _error;
  bool? _needsConfirm;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final needs = await _auth.signUpDriver(
        fullName: _name.text,
        email: _email.text,
        password: _pw.text,
        contactNo: _contact.text,
        plateNo: _plate.text,
        capacity: int.parse(_cap.text),
        terminalId: _terminalId!,
        licenseNo: _license.text.isEmpty ? null : _license.text,
      );
      setState(() => _needsConfirm = needs);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        portal: UserRole.driver,
        title: 'Driver Registration',
        subtitle: 'Submit an application. A terminal administrator must verify it first.',
        child: _needsConfirm != null
            ? _RegisteredPanel(email: _email.text, needsConfirm: _needsConfirm!, driver: true)
            : Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _ErrorText(_error),
                  const Banner2(
                    icon: Icons.info_outline_rounded,
                    text: 'New driver accounts cannot manage a live queue until approved by transport marshals.',
                    fg: AppColors.info,
                    bg: AppColors.infoSoft,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(controller: _name, validator: _req, textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline_rounded))),
                  const SizedBox(height: 14),
                  TextFormField(controller: _email, validator: _validateEmail, keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.alternate_email_rounded))),
                  const SizedBox(height: 14),
                  TextFormField(controller: _contact, validator: _phone, keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Contact Number', prefixIcon: Icon(Icons.phone_outlined))),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _plate,
                        validator: (v) => (v == null || v.trim().length < 3) ? 'Required' : null,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Plate Number', prefixIcon: Icon(Icons.pin_outlined)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _cap,
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return (n == null || n < 1 || n > 12) ? '1–12' : null;
                        },
                        decoration: const InputDecoration(labelText: 'Seats'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  TextFormField(controller: _license,
                      decoration: const InputDecoration(labelText: 'Driver\'s License No. (optional)', prefixIcon: Icon(Icons.credit_card_outlined))),
                  const SizedBox(height: 14),
                  FutureBuilder<List<Terminal>>(
                    future: _terminals,
                    builder: (context, snap) {
                      if (snap.hasError) return Text(friendlyError(snap.error!), style: const TextStyle(color: AppColors.danger));
                      final list = snap.data ?? const <Terminal>[];
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _terminalId,
                        validator: (v) => v == null ? 'Select a terminal' : null,
                        decoration: InputDecoration(
                          labelText: snap.connectionState == ConnectionState.waiting ? 'Loading terminals…' : 'Assigned Terminal',
                          prefixIcon: const Icon(Icons.place_outlined),
                        ),
                        items: [for (final t in list) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis))],
                        onChanged: (v) => setState(() => _terminalId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  PasswordField(controller: _pw, validator: _password, action: TextInputAction.next),
                  const SizedBox(height: 14),
                  PasswordField(controller: _pw2, label: 'Confirm Password', validator: (v) => v != _pw.text ? 'Passwords do not match' : null),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Submitting application…' : 'Submit Registration')),
                ]),
              ),
      );
}

// ---------------------------------------------------------------------------
// Forgot / reset password
// ---------------------------------------------------------------------------
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false, _sent = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _auth.sendPasswordReset(_email.text);
      setState(() => _sent = true);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Reset Password',
        subtitle: 'We\'ll email you a secure link to reset your account credentials.',
        child: _sent
            ? const EmptyState(
                icon: Icons.mark_email_read_outlined,
                title: 'Check your email',
                message: 'If an account exists for that address, a reset link has been sent.',
              )
            : Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _ErrorText(_error),
                  TextFormField(controller: _email, validator: _validateEmail, keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.alternate_email_rounded))),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _busy ? null : _submit, child: const Text('Send Reset Link')),
                ]),
              ),
      );
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _auth.updatePassword(_pw.text);
      if (mounted) {
        showSnack(context, 'Password updated.');
        context.go('/');
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Choose a New Password',
        subtitle: 'Use at least 8 characters with letters and numbers.',
        showBack: false,
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _ErrorText(_error),
            PasswordField(controller: _pw, label: 'New Password', validator: _password, action: TextInputAction.next),
            const SizedBox(height: 14),
            PasswordField(controller: _pw2, label: 'Confirm New Password', validator: (v) => v != _pw.text ? 'Passwords do not match' : null),
            const SizedBox(height: 18),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('Update Password')),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Account status (pending / suspended / rejected / missing profile)
// ---------------------------------------------------------------------------
class AccountStatusPage extends StatelessWidget {
  const AccountStatusPage({super.key});
  @override
  Widget build(BuildContext context) {
    final p = _auth.profile;
    final (icon, title, msg) = switch (p?.status) {
      AccountStatus.pending when p?.role == UserRole.driver => (
          Icons.hourglass_top_rounded,
          'Awaiting Administrator Approval',
          'Your driver registration was received. You can join a terminal queue once an administrator verifies your details.'
        ),
      AccountStatus.pending => (Icons.hourglass_top_rounded, 'Awaiting Verification', 'An administrator needs to verify your student account.'),
      AccountStatus.suspended => (Icons.block_rounded, 'Account Suspended', p?.statusReason ?? 'Please contact the terminal administrator.'),
      AccountStatus.rejected => (Icons.cancel_outlined, 'Registration Not Approved', p?.statusReason ?? 'Please contact the terminal administrator.'),
      _ => (Icons.help_outline_rounded, 'Account Not Set Up', 'No profile was found for this login. Please contact the administrator.'),
    };
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 480,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            EmptyState(icon: icon, title: title, message: msg),
            if (p?.statusReason != null && p?.status == AccountStatus.pending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Note: ${p!.statusReason}', style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _auth.refreshProfile, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Check Status Again')),
            const SizedBox(height: 8),
            TextButton(onPressed: _auth.signOut, child: const Text('Sign Out')),
          ]),
        ),
      ),
    );
  }
}

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.canvas,
        body: ResponsiveCenter(
          maxWidth: 560,
          child: EmptyState(
            icon: Icons.settings_suggest_outlined,
            title: 'Backend not configured',
            message: 'Run the app with your Supabase settings:\n\n'
                'flutter run -d chrome --dart-define-from-file=env.json\n\n'
                'See README.md for setup steps.',
          ),
        ),
      );
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.canvas,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [BrandMark(size: 44), SizedBox(height: 24), LoadingView()])),
      );
}
