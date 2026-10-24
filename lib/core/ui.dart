import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import 'env.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 640, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: Padding(padding: padding, child: child)),
      );
}

/// Page-level heading: title, optional description, and right-aligned actions
/// that wrap below the title on narrow screens.
class PageHeader extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> actions;
  final Widget? leading;

  PageHeader({
    super.key,
    required this.title,
    String? description,
    String? subtitle,
    List<Widget>? actions,
    Widget? action,
    this.leading,
  })  : description = description ?? subtitle,
        actions = actions ?? (action != null ? [action] : const []);

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppText.pageTitle),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: AppText.body),
        ],
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      final stack = c.maxWidth < 640 || actions.isEmpty;
      final titleRow = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(child: text),
        ],
      );
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleRow,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: titleRow),
          const SizedBox(width: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    });
  }
}

class BrandMark extends StatelessWidget {
  final double size;
  final bool light;
  final bool showSubtitle;
  const BrandMark({super.key, this.size = 38, this.light = false, this.showSubtitle = true});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: light ? Colors.white.withValues(alpha: 0.12) : AppColors.primary,
              borderRadius: BorderRadius.circular(size * 0.26),
              border: light ? Border.all(color: Colors.white.withValues(alpha: 0.18)) : null,
            ),
            child: Icon(Icons.electric_rickshaw_rounded, color: Colors.white, size: size * 0.56),
          ),
          SizedBox(width: size * 0.3),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LuTrike',
                  style: TextStyle(
                    fontSize: size * 0.47,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: light ? Colors.white : AppColors.ink,
                    height: 1.1,
                  ),
                ),
                if (showSubtitle)
                  Text(
                    'Laguna University',
                    style: TextStyle(
                      fontSize: (size * 0.3).clamp(10.5, 13.0),
                      fontWeight: FontWeight.w500,
                      color: light ? Colors.white.withValues(alpha: 0.7) : AppColors.inkMuted,
                      height: 1.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
        ],
      );
}

/// Circular initials avatar.
class AppAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final Color? background;
  const AppAvatar(this.name, {super.key, this.size = 32, this.color, this.background});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1 ? parts.first.characters.first : '${parts.first.characters.first}${parts.last.characters.first}')
            .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? AppColors.primarySoft,
        shape: BoxShape.circle,
        border: Border.all(color: (color ?? AppColors.primary).withValues(alpha: 0.14)),
      ),
      child: Text(
        initials,
        style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w600, color: color ?? AppColors.primary, height: 1),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cards & badges
// ---------------------------------------------------------------------------
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final List<BoxShadow>? boxShadow;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color,
    this.borderColor,
    this.shadows,
    this.boxShadow,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final border = widget.borderColor ?? (_hover && interactive ? AppColors.borderStrong : AppColors.border);
    final shadow = widget.shadows ?? widget.boxShadow ?? (_hover && interactive ? AppShadows.cardHover : AppShadows.card);

    return MouseRegion(
      onEnter: interactive ? (_) => setState(() => _hover = true) : null,
      onExit: interactive ? (_) => setState(() => _hover = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.color ?? AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: border, width: 1),
          boxShadow: shadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: AppColors.primary.withValues(alpha: 0.06),
            hoverColor: Colors.transparent,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.sectionTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppText.caption.copyWith(fontSize: 13)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final QueueStatus status;
  final bool compact;
  const StatusChip(this.status, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = styleFor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: s.fg.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: s.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            s.label,
            style: TextStyle(color: s.fg, fontWeight: FontWeight.w500, fontSize: compact ? 11.5 : 12.5),
          ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color fg, bg;
  final IconData? icon;
  const Pill(this.text, {super.key, this.fg = AppColors.inkSecondary, this.bg = AppColors.surfaceMuted, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: fg.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11.5, letterSpacing: 0.1),
              ),
            ),
          ],
        ),
      );
}

/// Metric tile. Flat (border, no shadow) so it can sit inside other cards
/// without the "card in a card" look.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;

  const StatTile({super.key, required this.label, required this.value, required this.icon, this.color = AppColors.primary, this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppText.label.copyWith(fontSize: 12.5, color: AppColors.inkSecondary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: AppText.metric, overflow: TextOverflow.ellipsis, maxLines: 1),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: AppText.caption.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 1),
          ],
        ],
      ),
    );
  }
}

/// Philippine vehicle-plate style badge.
class PlateBadge extends StatelessWidget {
  final String plateNo;
  final bool large;
  final bool isFront;

  const PlateBadge(this.plateNo, {super.key, this.large = false, this.isFront = false});

  @override
  Widget build(BuildContext context) {
    final edge = isFront ? AppColors.accent : AppColors.ink;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 6, vertical: large ? 3 : 2),
      decoration: BoxDecoration(
        color: isFront ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: edge.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(color: edge, borderRadius: BorderRadius.circular(2)),
            child: const Text(
              'LU',
              style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.4, height: 1.2),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            plateNo.toUpperCase(),
            style: TextStyle(
              color: isFront ? AppColors.accentDark : AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: large ? 14 : 12,
              letterSpacing: 1.0,
              fontFamily: 'monospace',
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented filter control with optional counts.
class FilterTabs<T> extends StatelessWidget {
  final T selected;
  final List<FilterOption<T>> options;
  final ValueChanged<T> onSelected;

  const FilterTabs({super.key, required this.selected, required this.options, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final isSelected = opt.value == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(opt.value),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.ink : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: isSelected ? AppColors.ink : AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (opt.icon != null) ...[
                        Icon(opt.icon, size: 14, color: isSelected ? Colors.white : AppColors.inkMuted),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        opt.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.inkSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      if (opt.count != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withValues(alpha: 0.16) : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            '${opt.count}',
                            style: TextStyle(
                              color: isSelected ? Colors.white : AppColors.inkMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class FilterOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final int? count;

  const FilterOption({required this.value, required this.label, this.icon, this.count});
}

/// Seat occupancy bar.
class SeatBar extends StatelessWidget {
  final int filled, capacity;
  final Color color;
  const SeatBar({super.key, required this.filled, required this.capacity, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(capacity, (i) {
        final isOccupied = i < filled;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: 8,
            margin: EdgeInsets.only(right: i == capacity - 1 ? 0 : 4),
            decoration: BoxDecoration(
              color: isOccupied ? color : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(4),
              border: isOccupied ? null : Border.all(color: AppColors.border),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Live indicator
// ---------------------------------------------------------------------------
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, this.color = AppColors.primaryLight, this.size = 8});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2,
      height: widget.size * 2,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * (1 + _ctrl.value),
                height: widget.size * (1 + _ctrl.value),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: (1 - _ctrl.value) * 0.35),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LiveBadge extends StatelessWidget {
  final LiveState state;
  const LiveBadge(this.state, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      LiveState.live => ('Live', AppColors.success),
      LiveState.connecting => ('Connecting', AppColors.warning),
      LiveState.offline => ('Offline', AppColors.danger),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == LiveState.live)
            PulseDot(color: AppColors.primaryLight, size: 6)
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(Icons.sync_problem_rounded, size: 12, color: color),
            ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feedback: banners, empty / loading / error states
// ---------------------------------------------------------------------------
class Banner2 extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color fg, bg;
  final Widget? action;
  const Banner2({super.key, required this.icon, required this.text, required this.fg, required this.bg, this.action});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: fg.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w500, fontSize: 13, height: 1.4)),
            ),
            ?action,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppShadows.card,
                ),
                child: Icon(icon, size: 22, color: AppColors.inkSecondary),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: AppText.sectionTitle),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!, textAlign: TextAlign.center, style: AppText.body.copyWith(fontSize: 13.5, color: AppColors.inkMuted)),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary)),
              if (message != null) ...[
                const SizedBox(height: 14),
                Text(message!, textAlign: TextAlign.center, style: AppText.caption.copyWith(fontSize: 13.5)),
              ],
            ],
          ),
        ),
      );
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load this page',
        message: friendlyError(error),
        action: onRetry == null
            ? null
            : OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
      );
}

enum LiveState { connecting, live, offline }

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final isDesktop = MediaQuery.sizeOf(context).width > 640;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: error ? const Color(0xFFFDA29B) : const Color(0xFF6CE9A6),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5, color: Colors.white))),
          ],
        ),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        margin: isDesktop ? null : const EdgeInsets.all(16),
        width: isDesktop ? 440 : null,
      ),
    );
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String confirm = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: Text(message)),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> reasonDialog(BuildContext context,
    {required String title, String hint = 'Reason', String confirm = 'Submit', bool danger = false}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            maxLength: 300,
            decoration: InputDecoration(hintText: hint, helperText: 'Recorded in the audit log. Minimum 3 characters.'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
            onPressed: ctrl.text.trim().length < 3 ? null : () => Navigator.pop(c, ctrl.text.trim()),
            child: Text(confirm),
          ),
        ],
      ),
    ),
  );
}

String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 10) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return DateFormat('MMM d, h:mm a').format(t);
}

String fmtDateTime(DateTime t) => DateFormat('MMM d, y · h:mm a').format(t);
String fmtTime(DateTime t) => DateFormat('h:mm a').format(t);

String fmtDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60}h ${m % 60}m';
}

void showFareMatrixSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Campus TODA Fare Matrix',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink),
                      ),
                      Text(
                        'Authorized rates for Laguna University routes',
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 20% Student Discount Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.discount_rounded, size: 18, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'R.A. 11314: Enrolled students are legally entitled to 20% discount upon presenting a valid Laguna University ID.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.primaryDark, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Fare Table
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text('Route Destination', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.ink))),
                        Expanded(flex: 2, child: Text('Student (20%)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.primary))),
                        Expanded(flex: 2, child: Text('Regular', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppColors.inkMuted))),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  _buildFareRow('LU Gate ➔ Bubukal Junction', '₱12.00', '₱15.00'),
                  const Divider(height: 1, color: AppColors.border),
                  _buildFareRow('LU Gate ➔ Sta. Cruz Town Plaza', '₱16.00', '₱20.00'),
                  const Divider(height: 1, color: AppColors.border),
                  _buildFareRow('LU Gate ➔ Sambat / Sunstar Mall', '₱20.00', '₱25.00'),
                  const Divider(height: 1, color: AppColors.border),
                  _buildFareRow('Solo / Special Trip (Pakyaw Direct)', '₱50.00', '₱60.00', isSpecial: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // TODA Policy Reminder
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Passenger Rights & Guidelines:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.ink)),
                  SizedBox(height: 4),
                  Text('• Drivers must not charge more than the official LTFRB / Municipal fare tariff.', style: TextStyle(fontSize: 11.5, color: AppColors.inkSecondary)),
                  Text('• Heavy cargo or market baggage occupying a passenger seat may be charged one regular seat fare.', style: TextStyle(fontSize: 11.5, color: AppColors.inkSecondary)),
                  Text('• For complaints, report via the system Feedback dialog or Laguna University Guard Post.', style: TextStyle(fontSize: 11.5, color: AppColors.inkSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildFareRow(String route, String student, String regular, {bool isSpecial = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Row(
            children: [
              if (isSpecial) ...[
                const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFD97706)),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  route,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSpecial ? FontWeight.w700 : FontWeight.w500,
                    color: isSpecial ? const Color(0xFFB45309) : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            student,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            regular,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ),
      ],
    ),
  );
}
