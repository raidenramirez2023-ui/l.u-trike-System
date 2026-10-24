import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/models.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _auth = AuthController.instance;
  int _navIndex = 0;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _checkPending();
  }

  Future<void> _checkPending() async {
    try {
      final res = await sb.rpc('admin_overview') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _pendingCount = (res['pending_drivers'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final pages = [
      _AdminOverviewTab(onRefreshPending: _checkPending),
      _AdminDriversTab(onUpdated: _checkPending),
      const _AdminStudentsTab(),
      const _AdminTerminalsTab(),
      const _AdminReportsTab(),
    ];

    final navDestinations = [
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard_rounded),
        label: 'Overview',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: _pendingCount > 0,
          label: Text('$_pendingCount'),
          backgroundColor: const Color(0xFFD97706),
          child: const Icon(Icons.electric_rickshaw_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: _pendingCount > 0,
          label: Text('$_pendingCount'),
          backgroundColor: const Color(0xFFD97706),
          child: const Icon(Icons.electric_rickshaw_rounded),
        ),
        label: 'Drivers',
      ),
      const NavigationDestination(
        icon: Icon(Icons.school_outlined),
        selectedIcon: Icon(Icons.school_rounded),
        label: 'Students',
      ),
      const NavigationDestination(
        icon: Icon(Icons.storefront_outlined),
        selectedIcon: Icon(Icons.storefront_rounded),
        label: 'Terminals',
      ),
      const NavigationDestination(
        icon: Icon(Icons.bar_chart_rounded),
        selectedIcon: Icon(Icons.bar_chart_rounded),
        label: 'Reports',
      ),
    ];

    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth < 100) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final isNarrow = screenWidth < 400;

    return Theme(
      data: buildStudentTheme(),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
          titleSpacing: isNarrow ? 8 : (wide ? 24 : 16),
          title: Row(
            children: [
              BrandMark(size: isNarrow ? 25 : 30, showSubtitle: !isNarrow),
              if (wide) ...[
                const SizedBox(width: 12),
                Container(width: 1, height: 20, color: AppColors.border),
                const SizedBox(width: 12),
                const Text(
                  'Operations Console',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'ENTERPRISE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (wide) ...[
              const LiveBadge(LiveState.live),
              const SizedBox(width: 12),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAvatar(
                    _auth.profile?.fullName ?? 'Admin',
                    size: 24,
                  ),
                  if (wide) ...[
                    const SizedBox(width: 8),
                    Text(
                      _auth.profile?.fullName ?? 'Administrator',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: const Text(
                        'ADMIN',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Sign Out',
              icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.inkSecondary),
              onPressed: () => _auth.signOut(),
            ),
            SizedBox(width: wide ? 20 : 10),
          ],
        ),
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    backgroundColor: Colors.white,
                    indicatorColor: AppColors.primarySoft,
                    selectedIconTheme: const IconThemeData(color: AppColors.primary),
                    unselectedIconTheme: const IconThemeData(color: AppColors.inkMuted),
                    selectedLabelTextStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
                    unselectedLabelTextStyle: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w500, fontSize: 12),
                    selectedIndex: _navIndex,
                    onDestinationSelected: (i) => setState(() => _navIndex = i),
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -0.9,
                    minWidth: 84,
                    destinations: [
                      const NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: Text('Overview'),
                      ),
                      NavigationRailDestination(
                        icon: Badge(
                          isLabelVisible: _pendingCount > 0,
                          label: Text('$_pendingCount'),
                          backgroundColor: AppColors.warning,
                          child: const Icon(Icons.electric_rickshaw_outlined),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: _pendingCount > 0,
                          label: Text('$_pendingCount'),
                          backgroundColor: AppColors.warning,
                          child: const Icon(Icons.electric_rickshaw_rounded),
                        ),
                        label: const Text('Drivers'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.school_outlined),
                        selectedIcon: Icon(Icons.school_rounded),
                        label: Text('Students'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.storefront_outlined),
                        selectedIcon: Icon(Icons.storefront_rounded),
                        label: Text('Terminals'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.bar_chart_rounded),
                        selectedIcon: Icon(Icons.bar_chart_rounded),
                        label: Text('Reports'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(child: pages[_navIndex]),
                ],
              )
            : pages[_navIndex],
        bottomNavigationBar: wide
            ? null
            : Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border, width: 1)),
                ),
                child: NavigationBar(
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.primarySoft,
                  selectedIndex: _navIndex,
                  onDestinationSelected: (i) => setState(() => _navIndex = i),
                  destinations: navDestinations,
                ),
              ),
      ),
    );
  }
}

// ===========================================================================
// Tab 1: Overview
// ===========================================================================
class _AdminOverviewTab extends StatefulWidget {
  final VoidCallback? onRefreshPending;
  const _AdminOverviewTab({this.onRefreshPending});

  @override
  State<_AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<_AdminOverviewTab> {
  late Future<Map<String, dynamic>> _overview = _fetchOverview();

  Future<Map<String, dynamic>> _fetchOverview() async {
    final v = await sb.rpc('admin_overview');
    widget.onRefreshPending?.call();
    return Map<String, dynamic>.from(v);
  }

  Future<void> _refresh() async {
    setState(() {
      _overview = _fetchOverview();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _overview,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Compiling operations telemetry…');
        }
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: _refresh);
        }

        final d = snap.data!;
        final recent = (d['recent_activity'] as List).cast<Map<String, dynamic>>();
        final pendingDrivers = (d['pending_drivers'] as num?)?.toInt() ?? 0;

        final screenWidth = MediaQuery.sizeOf(ctx).width;
        final isMobile = screenWidth < 600;
        final isNarrow = screenWidth < 400;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 12 : (isMobile ? 16 : 24),
              vertical: isNarrow ? 14 : 22,
            ),
            child: ResponsiveCenter(
              maxWidth: 1080,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Operations banner (Compact and overflow-proof)
                  Container(
                    padding: EdgeInsets.all(isNarrow ? 12 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.subtle,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: isNarrow ? 36 : 42,
                          height: isNarrow ? 36 : 42,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(Icons.bolt_rounded, color: AppColors.primary, size: isNarrow ? 18 : 22),
                        ),
                        SizedBox(width: isNarrow ? 10 : 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isNarrow ? 'LU Mobility Engine' : 'Laguna University Mobility Control Engine',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: isNarrow ? 13.5 : 15,
                                  color: AppColors.ink,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isNarrow ? 'Realtime sync & queue arbitration' : 'Real-time WebSocket synchronization · Concurrency-safe queue arbitration',
                                style: TextStyle(
                                  color: AppColors.inkSecondary,
                                  fontSize: isNarrow ? 11 : 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          style: IconButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            foregroundColor: AppColors.inkSecondary,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          tooltip: 'Refresh Operations Data',
                          onPressed: _refresh,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isNarrow ? 16 : 22),
                  Text(
                    'Operational Performance KPI',
                    style: TextStyle(
                      fontSize: isNarrow ? 14 : 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 4 Main KPI Cards: Dynamic 4-col desktop, 2-col tablet/mobile (No giant long boxes)
                  LayoutBuilder(builder: (ctx, c) {
                    final cols = c.maxWidth >= 840 ? 4 : 2;
                    final spacing = c.maxWidth < 400 ? 8.0 : 12.0;
                    final w = (c.maxWidth - (cols - 1) * spacing) / cols;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        _OverviewKpiCard(
                          width: w,
                          label: 'Registered Students',
                          value: '${d['students']}',
                          icon: Icons.school_rounded,
                          color: const Color(0xFF0284C7),
                          badge: 'Roster',
                        ),
                        _OverviewKpiCard(
                          width: w,
                          label: 'Authorized Drivers',
                          value: '${d['drivers']}',
                          icon: Icons.electric_rickshaw_rounded,
                          color: AppColors.primary,
                          badge: 'Fleet',
                        ),
                        _OverviewKpiCard(
                          width: w,
                          label: 'Pending Approvals',
                          value: '$pendingDrivers',
                          icon: Icons.pending_actions_rounded,
                          color: pendingDrivers > 0 ? AppColors.warning : AppColors.inkMuted,
                          badge: pendingDrivers > 0 ? 'Action Req.' : 'All Clear',
                          isAlert: pendingDrivers > 0,
                        ),
                        _OverviewKpiCard(
                          width: w,
                          label: 'Departures Today',
                          value: '${d['departures_today']}',
                          icon: Icons.check_circle_rounded,
                          color: const Color(0xFF10B981),
                          badge: 'Completed',
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 14),

                  // Secondary Metrics (Clean, compact density)
                  LayoutBuilder(builder: (ctx, c) {
                    final isMobileNarrow = c.maxWidth < 560;
                    final spacing = c.maxWidth < 400 ? 8.0 : 12.0;

                    if (isMobileNarrow) {
                      return Column(
                        children: [
                          _SecondaryMetricTile(
                            label: 'Tricycles in Lineups',
                            value: '${d['queue_length']}',
                            icon: Icons.format_list_numbered_rounded,
                            color: AppColors.primary,
                            hint: 'Active in terminal bays',
                          ),
                          SizedBox(height: spacing),
                          _SecondaryMetricTile(
                            label: 'Average Wait Time',
                            value: d['avg_wait_today_sec'] != null
                                ? fmtDuration((d['avg_wait_today_sec'] as num).toInt())
                                : '—',
                            icon: Icons.timer_outlined,
                            color: AppColors.inkSecondary,
                            hint: 'Today\'s completed trips',
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: _SecondaryMetricTile(
                            label: 'Tricycles Currently in Bay Lineups',
                            value: '${d['queue_length']}',
                            icon: Icons.format_list_numbered_rounded,
                            color: AppColors.primary,
                            hint: 'Active across all terminals',
                          ),
                        ),
                        SizedBox(width: spacing),
                        Expanded(
                          child: _SecondaryMetricTile(
                            label: 'Average Passenger Wait Time',
                            value: d['avg_wait_today_sec'] != null
                                ? fmtDuration((d['avg_wait_today_sec'] as num).toInt())
                                : '—',
                            icon: Icons.timer_outlined,
                            color: AppColors.inkSecondary,
                            hint: 'From today\'s completed trips',
                          ),
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 32),
                  const SectionTitle(
                    'Realtime Audit & Operations Log',
                    subtitle: 'Sequential record of departures, queue adjustments, and administrative approvals',
                  ),

                  if (recent.isEmpty)
                    const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No Recent Operations Logged',
                      message: 'Operations and driver departure records will stream here in real time.',
                    )
                  else
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: recent.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (ctx, idx) {
                          final a = recent[idx];
                          final ts = DateTime.parse(a['created_at']).toLocal();
                          final actionStr = a['action'].toString();
                          final isDeparture = actionStr.contains('depart');
                          final isApprove = actionStr.contains('approve') || actionStr.contains('verify');
                          final isCorrect = actionStr.contains('correct') || actionStr.contains('override');

                          final icon = isDeparture
                              ? Icons.departure_board_rounded
                              : isApprove
                                  ? Icons.verified_rounded
                                  : isCorrect
                                      ? Icons.rule_folder_rounded
                                      : Icons.history_rounded;

                          final color = isDeparture
                              ? AppColors.primary
                              : isApprove
                                  ? const Color(0xFF0284C7)
                                  : isCorrect
                                      ? AppColors.warning
                                      : AppColors.inkMuted;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: Icon(icon, color: color, size: 20),
                            ),
                            title: Text(
                              actionStr.replaceAll('_', ' ').toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: 0.2, color: AppColors.ink),
                            ),
                            subtitle: Text(
                              'Terminal: ${a['terminal'] ?? 'LU Campus'} · Operator: ${a['driver'] ?? 'System Admin'}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
                            ),
                            trailing: Text(
                              timeAgo(ts),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkMuted),
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
      },
    );
  }
}

class _OverviewKpiCard extends StatelessWidget {
  final double width;
  final String label, value;
  final IconData icon;
  final Color color;
  final String badge;
  final bool isAlert;

  const _OverviewKpiCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.badge,
    this.isAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = width < 185;

    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isAlert ? const Color(0xFFF59E0B) : AppColors.border,
            width: isAlert ? 1.5 : 1.0,
          ),
          boxShadow: AppShadows.subtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(isCompact ? 6 : 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, color: color, size: isCompact ? 17 : 20),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 6 : 8,
                      vertical: isCompact ? 2.5 : 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: isAlert ? const Color(0xFFFEF3C7) : color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: isAlert ? const Color(0xFF92400E) : color,
                        fontSize: isCompact ? 9.5 : 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 10 : 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: isCompact ? 22 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: isAlert ? const Color(0xFFB45309) : AppColors.ink,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: isCompact ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSecondary,
                height: 1.25,
              ),
              maxLines: isCompact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;

  const _SecondaryMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.subtle,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.inkMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 2: Driver & Vehicle Management
// ===========================================================================
class _AdminDriversTab extends StatefulWidget {
  final VoidCallback? onUpdated;
  const _AdminDriversTab({this.onUpdated});

  @override
  State<_AdminDriversTab> createState() => _AdminDriversTabState();
}

class _AdminDriversTabState extends State<_AdminDriversTab> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all, pending, active, suspended

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final rows = await sb.rpc('admin_list_users', params: {
        'p_role': 'driver',
        'p_search': _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      }) as List;
      if (!mounted) return;
      setState(() {
        _drivers = rows.cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
      widget.onUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _reviewDriver(String driverId, bool approve) async {
    final notes = await reasonDialog(
      context,
      title: approve ? 'Approve Driver Account' : 'Reject Driver Registration',
      hint: approve ? 'Approval notes (e.g., Documents verified)' : 'Reason for rejection (e.g., Invalid plate no.)',
      confirm: approve ? 'Approve Driver' : 'Reject Registration',
      danger: !approve,
    );
    if (notes == null && !approve) return;

    try {
      await sb.rpc('admin_review_driver', params: {
        'p_driver': driverId,
        'p_approve': approve,
        'p_notes': notes,
      });
      if (mounted) showSnack(context, approve ? 'Driver successfully approved and activated' : 'Driver registration rejected');
      _fetch();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _toggleSuspend(String userId, String currentStatus) async {
    final suspend = currentStatus == 'active';
    final reason = await reasonDialog(
      context,
      title: suspend ? 'Suspend Driver Account' : 'Reactivate Driver Account',
      hint: 'Audit reason for this action',
      confirm: suspend ? 'Suspend Account' : 'Reactivate Account',
      danger: suspend,
    );
    if (reason == null) return;

    try {
      await sb.rpc('admin_set_account_status', params: {
        'p_user': userId,
        'p_status': suspend ? 'suspended' : 'active',
        'p_reason': reason,
      });
      if (mounted) showSnack(context, suspend ? 'Driver account suspended' : 'Driver account restored');
      _fetch();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredDrivers = _drivers.where((d) {
      if (_filter == 'all') return true;
      return d['status'] == _filter;
    }).toList();

    final pendingCount = _drivers.where((d) => d['status'] == 'pending').length;
    final activeCount = _drivers.where((d) => d['status'] == 'active').length;
    final suspendedCount = _drivers.where((d) => d['status'] == 'suspended').length;

    return ResponsiveCenter(
      maxWidth: 1080,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Authorized Driver & Fleet Registry',
            subtitle: 'Manage authorized tricycle drivers, verify vehicle plates, and process applications',
            action: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh'),
            ),
          ),

          // Search and Filters (Responsive to prevent mobile overflow)
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isVeryNarrow = constraints.maxWidth < 420;
              if (isVeryNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search driver or plate…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _fetch();
                                },
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _fetch(),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: _fetch,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Search Registry'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search by driver name, email, or plate number…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _fetch();
                                },
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _fetch(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    onPressed: _fetch,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Search'),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 14),

          // Filter tabs
          FilterTabs<String>(
            selected: _filter,
            onSelected: (val) => setState(() => _filter = val),
            options: [
              FilterOption(value: 'all', label: 'All Drivers', count: _drivers.length),
              FilterOption(value: 'pending', label: 'Pending Review', count: pendingCount, icon: Icons.pending_actions_rounded),
              FilterOption(value: 'active', label: 'Active Fleet', count: activeCount, icon: Icons.check_circle_outline_rounded),
              FilterOption(value: 'suspended', label: 'Suspended', count: suspendedCount, icon: Icons.block_rounded),
            ],
          ),

          const SizedBox(height: 16),

          Expanded(
            child: _loading
                ? const LoadingView(message: 'Querying driver registry…')
                : _error != null
                    ? ErrorView(error: _error!, onRetry: _fetch)
                    : filteredDrivers.isEmpty
                        ? const EmptyState(
                            icon: Icons.person_off_outlined,
                            title: 'No Matching Drivers Found',
                            message: 'Try clearing your search or selecting a different filter tab.',
                          )
                        : ListView.separated(
                            itemCount: filteredDrivers.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (ctx, idx) {
                              final d = filteredDrivers[idx];
                              final details = d['details'] as Map<String, dynamic>? ?? {};
                              final veh = details['vehicle'] as Map<String, dynamic>?;
                              final status = d['status'] as String;
                              final isPending = status == 'pending';
                              final plateNo = veh?['plate_no']?.toString() ?? 'NO-PLATE';

                              return AppCard(
                                borderColor: isPending ? AppColors.warning : null,
                                padding: const EdgeInsets.all(16),
                                child: LayoutBuilder(
                                  builder: (ctx, constraints) {
                                    final isNarrow = constraints.maxWidth < 560;
                                    final isVeryNarrow = constraints.maxWidth < 420;

                                    final headerRow = Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: isPending
                                                ? AppColors.warningSoft
                                                : status == 'active'
                                                    ? AppColors.primarySoft
                                                    : AppColors.dangerSoft,
                                            borderRadius: BorderRadius.circular(AppRadius.md),
                                          ),
                                          child: Icon(
                                            Icons.electric_rickshaw_rounded,
                                            color: isPending
                                                ? AppColors.warning
                                                : status == 'active'
                                                    ? AppColors.primary
                                                    : AppColors.danger,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    d['full_name'],
                                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.ink),
                                                  ),
                                                  PlateBadge(plateNo),
                                                  Pill(
                                                    status.toUpperCase(),
                                                    fg: isPending
                                                        ? AppColors.warning
                                                        : status == 'active'
                                                            ? AppColors.primary
                                                            : AppColors.danger,
                                                    bg: isPending
                                                        ? AppColors.warningSoft
                                                        : status == 'active'
                                                            ? AppColors.primarySoft
                                                            : AppColors.dangerSoft,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 4,
                                                children: [
                                                  Text(
                                                    'Cap: ${veh?['capacity'] ?? 4} pax',
                                                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
                                                  ),
                                                  Text(
                                                    'Terminal: ${details['terminal_name'] ?? 'LU Campus'}',
                                                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
                                                  ),
                                                  Text(
                                                    'Mobile: ${details['contact_no'] ?? '—'}',
                                                    style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
                                                  ),
                                                  Text(
                                                    'Email: ${d['email']}',
                                                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isNarrow && !isPending)
                                          IconButton.filledTonal(
                                            tooltip: status == 'active' ? 'Suspend driver account' : 'Reactivate driver account',
                                            style: IconButton.styleFrom(
                                              backgroundColor: status == 'active' ? AppColors.dangerSoft : AppColors.primarySoft,
                                              foregroundColor: status == 'active' ? AppColors.danger : AppColors.primary,
                                            ),
                                            icon: Icon(
                                              status == 'active' ? Icons.block_rounded : Icons.check_circle_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () => _toggleSuspend(d['id'], status),
                                          ),
                                      ],
                                    );

                                    Widget? actionButtons;
                                    if (isPending) {
                                      if (isVeryNarrow) {
                                        actionButtons = Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            FilledButton.icon(
                                              onPressed: () => _reviewDriver(d['id'], true),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: AppColors.primary,
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                              ),
                                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                              label: const Text('Approve Driver'),
                                            ),
                                            const SizedBox(height: 6),
                                            OutlinedButton.icon(
                                              onPressed: () => _reviewDriver(d['id'], false),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.danger,
                                                side: const BorderSide(color: AppColors.danger),
                                                padding: const EdgeInsets.symmetric(vertical: 10),
                                              ),
                                              icon: const Icon(Icons.cancel_outlined, size: 16),
                                              label: const Text('Reject Registration'),
                                            ),
                                          ],
                                        );
                                      } else {
                                        actionButtons = Row(
                                          children: [
                                            Expanded(
                                              child: FilledButton.icon(
                                                onPressed: () => _reviewDriver(d['id'], true),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: AppColors.primary,
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                ),
                                                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                                label: const Text('Approve Driver'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => _reviewDriver(d['id'], false),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: AppColors.danger,
                                                  side: const BorderSide(color: AppColors.danger),
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                ),
                                                icon: const Icon(Icons.cancel_outlined, size: 16),
                                                label: const Text('Reject'),
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                    } else if (isNarrow) {
                                      actionButtons = Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: () => _toggleSuspend(d['id'], status),
                                          style: TextButton.styleFrom(
                                            foregroundColor: status == 'active' ? AppColors.danger : AppColors.primary,
                                          ),
                                          icon: Icon(status == 'active' ? Icons.block_rounded : Icons.check_circle_rounded, size: 16),
                                          label: Text(status == 'active' ? 'Suspend Account' : 'Reactivate Account'),
                                        ),
                                      );
                                    }

                                    if (actionButtons == null) {
                                      return headerRow;
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        headerRow,
                                        const SizedBox(height: 12),
                                        actionButtons,
                                      ],
                                    );
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 3: Student Management
// ===========================================================================
class _AdminStudentsTab extends StatefulWidget {
  const _AdminStudentsTab();

  @override
  State<_AdminStudentsTab> createState() => _AdminStudentsTabState();
}

class _AdminStudentsTabState extends State<_AdminStudentsTab> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final rows = await sb.rpc('admin_list_users', params: {
        'p_role': 'student',
        'p_search': _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      }) as List;
      if (!mounted) return;
      setState(() {
        _students = rows.cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _verifyStudent(String studentId) async {
    final reason = await reasonDialog(
      context,
      title: 'Verify Student Number',
      hint: 'Verification note (e.g. Validated against official LU registrar list)',
      confirm: 'Mark as Verified',
    );
    if (reason == null) return;

    try {
      await sb.rpc('admin_set_student_verification', params: {
        'p_student': studentId,
        'p_status': 'verified',
        'p_reason': reason,
      });
      if (mounted) showSnack(context, 'Student marked as officially verified');
      _fetch();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _toggleSuspend(String userId, String currentStatus) async {
    final suspend = currentStatus == 'active';
    final reason = await reasonDialog(
      context,
      title: suspend ? 'Suspend Student Account' : 'Reactivate Student Account',
      hint: 'Audit reason for this action',
      confirm: suspend ? 'Suspend Account' : 'Reactivate Account',
      danger: suspend,
    );
    if (reason == null) return;

    try {
      await sb.rpc('admin_set_account_status', params: {
        'p_user': userId,
        'p_status': suspend ? 'suspended' : 'active',
        'p_reason': reason,
      });
      if (mounted) showSnack(context, suspend ? 'Student account suspended' : 'Student account restored');
      _fetch();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _students.where((s) {
      if (_filter == 'all') return true;
      final details = s['details'] as Map<String, dynamic>? ?? {};
      final vStatus = details['verification_status'] as String? ?? 'unverified';
      if (_filter == 'verified') return vStatus == 'verified';
      if (_filter == 'unverified') return vStatus != 'verified';
      if (_filter == 'suspended') return s['status'] == 'suspended';
      return true;
    }).toList();

    final verifiedCount = _students.where((s) => (s['details']?['verification_status']) == 'verified').length;
    final unverifiedCount = _students.length - verifiedCount;

    return ResponsiveCenter(
      maxWidth: 1080,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Student Commuter Directory',
            subtitle: 'Validate official Laguna University student identification numbers and account status',
            action: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Refresh'),
            ),
          ),

          // Search Row
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isVeryNarrow = constraints.maxWidth < 420;
              if (isVeryNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search student or ID…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _fetch();
                                },
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _fetch(),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: _fetch,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Search Directory'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search by student name, student ID number, or email…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _fetch();
                                },
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _fetch(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    onPressed: _fetch,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Search'),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 14),

          FilterTabs<String>(
            selected: _filter,
            onSelected: (val) => setState(() => _filter = val),
            options: [
              FilterOption(value: 'all', label: 'All Students', count: _students.length),
              FilterOption(value: 'verified', label: 'Officially Verified', count: verifiedCount, icon: Icons.verified_rounded),
              FilterOption(value: 'unverified', label: 'Unverified', count: unverifiedCount, icon: Icons.help_outline_rounded),
              FilterOption(value: 'suspended', label: 'Suspended', icon: Icons.block_rounded),
            ],
          ),

          const SizedBox(height: 16),

          Expanded(
            child: _loading
                ? const LoadingView(message: 'Loading student directory…')
                : _error != null
                    ? ErrorView(error: _error!, onRetry: _fetch)
                    : filtered.isEmpty
                        ? const EmptyState(
                            icon: Icons.school_outlined,
                            title: 'No Matching Students',
                            message: 'Try clearing your search or switching filter categories.',
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (ctx, idx) {
                              final s = filtered[idx];
                              final details = s['details'] as Map<String, dynamic>? ?? {};
                              final status = s['status'] as String;
                              final vStatus = details['verification_status'] as String? ?? 'unverified';
                              final isVerified = vStatus == 'verified';

                              return AppCard(
                                padding: const EdgeInsets.all(16),
                                child: LayoutBuilder(
                                  builder: (ctx, constraints) {
                                    final isNarrow = constraints.maxWidth < 560;

                                    final headerRow = Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        AppAvatar(
                                          s['full_name'] ?? 'S',
                                          size: 44,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(s['full_name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.ink)),
                                                  Pill(
                                                    'ID: ${details['student_number'] ?? 'N/A'}',
                                                    icon: Icons.badge_outlined,
                                                    fg: AppColors.inkSecondary,
                                                    bg: AppColors.surfaceMuted,
                                                  ),
                                                  Pill(
                                                    isVerified ? 'VERIFIED' : 'UNVERIFIED',
                                                    fg: isVerified ? AppColors.primary : AppColors.inkMuted,
                                                    bg: isVerified ? AppColors.primarySoft : AppColors.surfaceMuted,
                                                    icon: isVerified ? Icons.verified_rounded : Icons.pending_outlined,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 12,
                                                runSpacing: 4,
                                                children: [
                                                  Text(
                                                    'Email: ${s['email']}',
                                                    style: const TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                                                  ),
                                                  Text(
                                                    'Mobile: ${details['contact_no'] ?? '—'}',
                                                    style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isNarrow) ...[
                                          if (!isVerified) ...[
                                            FilledButton.tonalIcon(
                                              icon: const Icon(Icons.verified_outlined, size: 16),
                                              label: const Text('Verify Student'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: AppColors.primarySoft,
                                                foregroundColor: AppColors.primary,
                                              ),
                                              onPressed: () => _verifyStudent(s['id']),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          IconButton.filledTonal(
                                            tooltip: status == 'active' ? 'Suspend student account' : 'Reactivate student account',
                                            style: IconButton.styleFrom(
                                              backgroundColor: status == 'active' ? AppColors.dangerSoft : AppColors.primarySoft,
                                              foregroundColor: status == 'active' ? AppColors.danger : AppColors.primary,
                                            ),
                                            icon: Icon(
                                              status == 'active' ? Icons.block_rounded : Icons.check_circle_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () => _toggleSuspend(s['id'], status),
                                          ),
                                        ],
                                      ],
                                    );

                                    if (!isNarrow) {
                                      return headerRow;
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        headerRow,
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          alignment: WrapAlignment.end,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            if (!isVerified)
                                              FilledButton.tonalIcon(
                                                icon: const Icon(Icons.verified_outlined, size: 16),
                                                label: const Text('Verify Student'),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: AppColors.primarySoft,
                                                  foregroundColor: AppColors.primary,
                                                ),
                                                onPressed: () => _verifyStudent(s['id']),
                                              ),
                                            TextButton.icon(
                                              onPressed: () => _toggleSuspend(s['id'], status),
                                              style: TextButton.styleFrom(
                                                foregroundColor: status == 'active' ? AppColors.danger : AppColors.primary,
                                              ),
                                              icon: Icon(status == 'active' ? Icons.block_rounded : Icons.check_circle_rounded, size: 16),
                                              label: Text(status == 'active' ? 'Suspend' : 'Reactivate'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 4: Terminals & Queue Management (Live corrections with audit log)
// ===========================================================================
class _AdminTerminalsTab extends StatefulWidget {
  const _AdminTerminalsTab();

  @override
  State<_AdminTerminalsTab> createState() => _AdminTerminalsTabState();
}

class _AdminTerminalsTabState extends State<_AdminTerminalsTab> {
  List<Terminal> _terminals = [];
  Terminal? _selected;
  List<QueueItem> _queue = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final list = await Api.terminals();
      if (!mounted) return;
      setState(() {
        _terminals = list;
        if (_selected == null && list.isNotEmpty) _selected = list.first;
      });
      if (_selected != null) {
        final q = await Api.queue(_selected!.id);
        if (!mounted) return;
        setState(() => _queue = q);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _correctEntry(QueueItem item) async {
    final countCtrl = TextEditingController(text: '${item.passengers}');
    String chosenStatus = queueStatusDb(item.status);
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.rule_folder_rounded, color: Color(0xFFD97706)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Audit Queue Entry (${item.plateNo})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: StudentColors.ink),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Text(
                  'All manual interventions are permanently timestamped and recorded in the operations audit trail.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: countCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Passenger Count (Capacity: ${item.capacity})',
                  prefixIcon: const Icon(Icons.airline_seat_recline_normal_rounded),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: chosenStatus,
                decoration: const InputDecoration(
                  labelText: 'Queue Operational Status',
                  prefixIcon: Icon(Icons.swap_horiz_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'waiting', child: Text('Waiting in Line', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'boarding', child: Text('Accepting Passengers (Bay 1)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'almost_full', child: Text('Almost Full', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'ready', child: Text('Ready to Depart', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'paused', child: Text('Temporarily Paused', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'removed', child: Text('Remove from Queue', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setDState(() => chosenStatus = v!),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Audit Justification (Required)',
                  hintText: 'e.g. Passenger disembarked, mechanical issue',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: StudentColors.inkMuted, fontWeight: FontWeight.w600)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: StudentColors.primary),
              onPressed: () {
                if (reasonCtrl.text.trim().length < 3) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Save Audit Correction'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      await sb.rpc('admin_correct_entry', params: {
        'p_entry': item.entryId,
        'p_count': int.parse(countCtrl.text.trim()),
        'p_status': chosenStatus,
        'p_reason': reasonCtrl.text.trim(),
      });
      if (mounted) showSnack(context, 'Entry corrected and permanently audited.');
      _fetch();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _toggleTerminalOpen() async {
    if (_selected == null) return;
    final nowOpen = _selected!.isOpen;
    final reason = await reasonDialog(
      context,
      title: nowOpen ? 'Close Terminal Operations Temporarily' : 'Reopen Terminal Operations',
      hint: nowOpen ? 'Reason for closing (e.g. Inclement weather, campus holiday, road maintenance)' : 'Reopening note (optional)',
      confirm: nowOpen ? 'Confirm Close Terminal' : 'Confirm Reopen Terminal',
      danger: nowOpen,
    );
    if (nowOpen && (reason == null || reason.isEmpty)) return;

    try {
      await sb.rpc('admin_set_terminal_open', params: {
        'p_terminal': _selected!.id,
        'p_open': !nowOpen,
        'p_reason': reason,
      });
      if (mounted) showSnack(context, !nowOpen ? 'Terminal reopened for service' : 'Terminal closed temporarily');
      _fetch();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      maxWidth: 1080,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Terminal Operations & Queue Supervisor',
            subtitle: 'Supervise bay order, passenger boarding counts, and audited interventions',
            action: _selected != null
                ? FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _selected!.isOpen ? AppColors.dangerSoft : AppColors.primarySoft,
                      foregroundColor: _selected!.isOpen ? AppColors.danger : AppColors.primary,
                    ),
                    icon: Icon(_selected!.isOpen ? Icons.cancel_outlined : Icons.check_circle_outline_rounded, size: 16),
                    label: Text(_selected!.isOpen ? 'Emergency Close' : 'Reopen Terminal'),
                    onPressed: _toggleTerminalOpen,
                  )
                : null,
          ),

          // Terminal Switcher Pills (Horizontally scrollable for small screens)
          if (_terminals.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _terminals.map((t) {
                  final isSel = _selected?.id == t.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () {
                        _selected = t;
                        _fetch();
                      },
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: isSel ? AppColors.primary : AppColors.border, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_rounded, size: 16, color: isSel ? Colors.white : AppColors.inkSecondary),
                            const SizedBox(width: 8),
                            Text(
                              '${t.name} (${t.code})',
                              style: TextStyle(
                                color: isSel ? Colors.white : AppColors.ink,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : t.isOpen
                                        ? AppColors.primarySoft
                                        : AppColors.dangerSoft,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                              child: Text(
                                t.isOpen ? 'OPEN' : 'CLOSED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isSel
                                      ? Colors.white
                                      : t.isOpen
                                          ? AppColors.primary
                                          : AppColors.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 20),

          Expanded(
            child: _loading
                ? const LoadingView(message: 'Querying live bay lineup…')
                : _queue.isEmpty
                    ? const EmptyState(
                        icon: Icons.electric_rickshaw_outlined,
                        title: 'Queue Bay is Currently Empty',
                        message: 'No tricycles are actively waiting in this terminal. As drivers check in, they will populate here in FIFO order.',
                      )
                    : ListView.separated(
                        itemCount: _queue.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final item = _queue[idx];
                          final isFirst = idx == 0;

                          return AppCard(
                            borderColor: isFirst ? AppColors.primary : null,
                            padding: const EdgeInsets.all(16),
                            child: LayoutBuilder(
                              builder: (ctx, constraints) {
                                final isNarrow = constraints.maxWidth < 620;

                                final positionBadge = Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isFirst ? AppColors.primary : AppColors.surfaceMuted,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: isFirst ? AppColors.primary : AppColors.border, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '#${item.position ?? idx + 1}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isFirst ? Colors.white : AppColors.ink,
                                      ),
                                    ),
                                  ),
                                );

                                final isCompactNarrow = constraints.maxWidth < 420;
                                final isUltraNarrow = constraints.maxWidth < 360;

                                final overrideButton = FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.surfaceMuted,
                                    foregroundColor: AppColors.ink,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompactNarrow ? 10 : 14,
                                      vertical: isCompactNarrow ? 6 : 8,
                                    ),
                                    visualDensity: isCompactNarrow ? VisualDensity.compact : VisualDensity.standard,
                                  ),
                                  icon: Icon(Icons.rule_folder_rounded, size: isCompactNarrow ? 14 : 16),
                                  label: Text(
                                    isCompactNarrow ? 'Override' : 'Audited Override',
                                    style: TextStyle(
                                      fontSize: isCompactNarrow ? 11.5 : 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () => _correctEntry(item),
                                );

                                if (isNarrow) {
                                  // Mobile / Narrow layout to guarantee 0 overflow
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (isUltraNarrow) ...[
                                        Row(
                                          children: [
                                            positionBadge,
                                            const SizedBox(width: 8),
                                            PlateBadge(item.plateNo, large: false, isFront: isFirst),
                                            const Spacer(),
                                            StatusChip(item.status, compact: true),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item.driverDisplay,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ] else ...[
                                        Row(
                                          children: [
                                            positionBadge,
                                            const SizedBox(width: 10),
                                            PlateBadge(item.plateNo, large: false, isFront: isFirst),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item.driverDisplay,
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            StatusChip(item.status, compact: true),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      SeatBar(
                                        filled: item.passengers,
                                        capacity: item.capacity,
                                        color: isFirst ? AppColors.primary : AppColors.inkSecondary,
                                      ),
                                      const SizedBox(height: 8),
                                      if (isUltraNarrow) ...[
                                        Text(
                                          '${item.passengers}/${item.capacity} (${item.seatsLeft} left)',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkSecondary),
                                        ),
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: overrideButton,
                                        ),
                                      ] else ...[
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                isCompactNarrow
                                                    ? '${item.passengers}/${item.capacity} (${item.seatsLeft} left)'
                                                    : '${item.passengers} / ${item.capacity} Passengers (${item.seatsLeft} left)',
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.inkSecondary),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            overrideButton,
                                          ],
                                        ),
                                      ],
                                    ],
                                  );
                                }

                                // Wide / Desktop layout
                                return Row(
                                  children: [
                                    positionBadge,
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              PlateBadge(item.plateNo, large: true, isFront: isFirst),
                                              const SizedBox(width: 10),
                                              Flexible(
                                                child: Text(
                                                  item.driverDisplay,
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.ink),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              StatusChip(item.status, compact: true),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              SizedBox(
                                                width: 160,
                                                child: SeatBar(
                                                  filled: item.passengers,
                                                  capacity: item.capacity,
                                                  color: isFirst ? AppColors.primary : AppColors.inkSecondary,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Flexible(
                                                child: Text(
                                                  '${item.passengers} / ${item.capacity} Passengers (${item.seatsLeft} seats left)',
                                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.inkSecondary),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    overrideButton,
                                  ],
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Tab 5: Reports & Analytics (Real Recorded Data Only)
// ===========================================================================
class _AdminReportsTab extends StatefulWidget {
  const _AdminReportsTab();

  @override
  State<_AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<_AdminReportsTab> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  final DateTime _to = DateTime.now();
  int _rangeDays = 7;
  late Future<Map<String, dynamic>> _reports = _load();

  Future<Map<String, dynamic>> _load() async {
    final res = await sb.rpc('admin_reports', params: {
      'p_terminal': null,
      'p_from': _from.toIso8601String().substring(0, 10),
      'p_to': _to.toIso8601String().substring(0, 10),
    });
    return Map<String, dynamic>.from(res);
  }

  void _setRange(int days) {
    setState(() {
      _rangeDays = days;
      _from = DateTime.now().subtract(Duration(days: days));
      _reports = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _reports,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Compiling transit analytics from recorded trip telemetry…');
        }
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: () => setState(() => _reports = _load()));
        }

        final d = snap.data!;
        final total = (d['total_departures'] as num).toInt();
        final byHour = (d['by_hour'] as List).cast<Map<String, dynamic>>();
        final byDriver = (d['by_driver'] as List).cast<Map<String, dynamic>>();

        final isNarrowScreen = MediaQuery.of(context).size.width < 600;
        return SingleChildScrollView(
          padding: EdgeInsets.all(isNarrowScreen ? 16 : 24),
          child: ResponsiveCenter(
            maxWidth: 1080,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Operations Analytics & Reporting',
                  subtitle: 'Derived purely from recorded trip departures and passenger records',
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RangePill(label: 'Today', selected: _rangeDays == 0, onTap: () => _setRange(0)),
                      const SizedBox(width: 6),
                      _RangePill(label: 'Last 7 Days', selected: _rangeDays == 7, onTap: () => _setRange(7)),
                      const SizedBox(width: 6),
                      _RangePill(label: 'Last 30 Days', selected: _rangeDays == 30, onTap: () => _setRange(30)),
                    ],
                  ),
                ),

                if (total == 0)
                  const EmptyState(
                    icon: Icons.analytics_outlined,
                    title: 'No Recorded Trips in Selected Period',
                    message: 'Trip statistics and departure charts will automatically appear as drivers depart the bay.',
                  )
                else ...[
                  // Dynamic, Responsive Analytics KPI Cards
                  LayoutBuilder(builder: (ctx, c) {
                    final isMobile = c.maxWidth < 620;
                    final spacing = c.maxWidth < 400 ? 10.0 : 12.0;

                    final avgPax = (d['avg_passengers'] as num?)?.toDouble() ?? 0.0;
                    final occupancyPercent = ((avgPax / 4.0) * 100).round();

                    if (isMobile) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _AnalyticsKpiCard(
                                  label: 'Completed Trips',
                                  value: '$total',
                                  icon: Icons.departure_board_rounded,
                                  color: AppColors.primary,
                                  badge: 'Departures',
                                  subtitle: 'Recorded trips',
                                ),
                              ),
                              SizedBox(width: spacing),
                              Expanded(
                                child: _AnalyticsKpiCard(
                                  label: 'Total Commuters',
                                  value: '${d['total_passengers']}',
                                  icon: Icons.groups_rounded,
                                  color: AppColors.warning,
                                  badge: 'Passengers',
                                  subtitle: 'Students transported',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacing),
                          _AnalyticsKpiCard(
                            width: c.maxWidth,
                            label: 'Average Trip Occupancy',
                            value: '${d['avg_passengers']}',
                            unit: 'pax / trip',
                            icon: Icons.airline_seat_recline_normal_rounded,
                            color: const Color(0xFF0284C7),
                            badge: '$occupancyPercent% Fill Rate',
                            subtitle: 'Capacity benchmark: 4 passengers per tricycle',
                            progress: avgPax / 4.0,
                          ),
                        ],
                      );
                    }

                    // Desktop / Tablet layout: 3 equal cards in a Row
                    return Row(
                      children: [
                        Expanded(
                          child: _AnalyticsKpiCard(
                            label: 'Total Departures',
                            value: '$total',
                            icon: Icons.departure_board_rounded,
                            color: AppColors.primary,
                            badge: 'Completed',
                            subtitle: 'Logged trip departures',
                          ),
                        ),
                        SizedBox(width: spacing),
                        Expanded(
                          child: _AnalyticsKpiCard(
                            label: 'Passengers Served',
                            value: '${d['total_passengers']}',
                            icon: Icons.groups_rounded,
                            color: AppColors.warning,
                            badge: 'Commuters',
                            subtitle: 'Total passenger volume',
                          ),
                        ),
                        SizedBox(width: spacing),
                        Expanded(
                          child: _AnalyticsKpiCard(
                            label: 'Average Occupancy',
                            value: '${d['avg_passengers']}',
                            unit: 'pax',
                            icon: Icons.airline_seat_recline_normal_rounded,
                            color: const Color(0xFF0284C7),
                            badge: '$occupancyPercent% Fill Rate',
                            subtitle: 'Cap: 4 passengers / tricycle',
                            progress: avgPax / 4.0,
                          ),
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 28),

                  // Dynamic Hourly Departure Distribution Chart
                  () {
                    Map<String, dynamic>? peakHour;
                    for (final h in byHour) {
                      if (peakHour == null || ((h['departures'] as num?)?.toDouble() ?? 0) > ((peakHour['departures'] as num?)?.toDouble() ?? 0)) {
                        peakHour = h;
                      }
                    }

                    final rawMax = byHour.fold<double>(
                      0.0,
                      (m, e) => (e['departures'] as num).toDouble() > m ? (e['departures'] as num).toDouble() : m,
                    );

                    final double maxY;
                    final double interval;
                    if (rawMax <= 4) {
                      maxY = 5;
                      interval = 1;
                    } else if (rawMax <= 10) {
                      maxY = 10;
                      interval = 2;
                    } else if (rawMax <= 20) {
                      maxY = 20;
                      interval = 5;
                    } else if (rawMax <= 40) {
                      maxY = 40;
                      interval = 10;
                    } else {
                      maxY = ((rawMax / 10).ceil() * 10).toDouble();
                      interval = maxY / 4;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: Text(
                                'Hourly Departure Distribution',
                                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.ink),
                              ),
                            ),
                            if (peakHour != null && ((peakHour['departures'] as num?)?.toInt() ?? 0) > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bolt_rounded, size: 14, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Peak: ${peakHour['hour']}:00 (${peakHour['departures']} trips)',
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Departures / Hour',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkSecondary),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(AppRadius.xs),
                                    ),
                                    child: const Text(
                                      'Tap bar for details',
                                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.inkMuted),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 230,
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: maxY,
                                    minY: 0,
                                    barTouchData: BarTouchData(
                                      enabled: true,
                                      touchTooltipData: BarTouchTooltipData(
                                        getTooltipColor: (_) => AppColors.ink,
                                        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        tooltipMargin: 8,
                                        tooltipBorderRadius: BorderRadius.circular(AppRadius.sm),
                                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                          final h = group.x;
                                          final hStr = h == 0 ? '12:00 AM' : h == 12 ? '12:00 PM' : h > 12 ? '${h - 12}:00 PM' : '$h:00 AM';
                                          return BarTooltipItem(
                                            '$hStr\n',
                                            const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                                            children: [
                                              TextSpan(
                                                text: '${rod.toY.toInt()} Departures',
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                    barGroups: byHour.map((e) {
                                      final h = (e['hour'] as num).toInt();
                                      final dep = (e['departures'] as num).toDouble();
                                      final isPeak = peakHour != null && h == (peakHour['hour'] as num).toInt() && dep > 0;
                                      return BarChartGroupData(
                                        x: h,
                                        barRods: [
                                          BarChartRodData(
                                            toY: dep,
                                            gradient: LinearGradient(
                                              colors: isPeak
                                                  ? const [Color(0xFF059669), Color(0xFF34D399)]
                                                  : const [AppColors.primary, Color(0xFF10B981)],
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                            ),
                                            width: byHour.length > 12 ? 13 : 16,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                            backDrawRodData: BackgroundBarChartRodData(
                                              show: true,
                                              toY: maxY,
                                              color: AppColors.surfaceMuted.withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 26,
                                          getTitlesWidget: (val, meta) {
                                            final h = val.toInt();
                                            final str = h == 0 ? '12A' : h == 12 ? '12P' : h > 12 ? '${h - 12}P' : '${h}A';
                                            return Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: Text(
                                                str,
                                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 28,
                                          interval: interval,
                                          getTitlesWidget: (val, meta) {
                                            if (val > maxY || val < 0) return const SizedBox.shrink();
                                            if ((val % interval).abs() > 0.001 && val != 0) return const SizedBox.shrink();
                                            return Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: Text(
                                                val.toInt().toString(),
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                                                textAlign: TextAlign.right,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: false,
                                      horizontalInterval: interval,
                                      getDrawingHorizontalLine: (_) => FlLine(
                                        color: AppColors.border.withValues(alpha: 0.7),
                                        strokeWidth: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }(),

                  const SizedBox(height: 28),
                  const Text(
                    'Driver Service Leaderboard',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.ink),
                  ),
                  const SizedBox(height: 12),

                  AppCard(
                    padding: EdgeInsets.zero,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: byDriver.take(10).length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (ctx, idx) {
                        final drv = byDriver[idx];
                        final rank = idx + 1;
                        final isTop = rank <= 3;

                        final rankBadge = Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isTop ? AppColors.warningSoft : AppColors.surfaceMuted,
                            shape: BoxShape.circle,
                            border: Border.all(color: isTop ? AppColors.warning : AppColors.border, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              '#$rank',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: isTop ? AppColors.warning : AppColors.inkSecondary,
                              ),
                            ),
                          ),
                        );

                        final statChip = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            '${drv['departures']} trips · ${drv['passengers']} passengers',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.primary),
                          ),
                        );

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: LayoutBuilder(
                            builder: (ctx, c) {
                              if (c.maxWidth < 500) {
                                // Mobile layout to prevent trailing text overflow
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        rankBadge,
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            drv['driver'],
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        PlateBadge(drv['plate_no']?.toString() ?? 'N/A'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: statChip,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  rankBadge,
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            drv['driver'],
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        PlateBadge(drv['plate_no']?.toString() ?? 'N/A'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  statChip,
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RangePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangePill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.inkSecondary,
          ),
        ),
      ),
    );
  }
}

class _AnalyticsKpiCard extends StatelessWidget {
  final double? width;
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final String badge;
  final String subtitle;
  final double? progress;

  const _AnalyticsKpiCard({
    this.width,
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
    required this.color,
    required this.badge,
    required this.subtitle,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = (width != null && width! < 190);

    return Container(
      width: width,
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 6 : 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: color, size: isCompact ? 17 : 20),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 6 : 8,
                    vertical: isCompact ? 2.5 : 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: color,
                      fontSize: isCompact ? 9.5 : 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 10 : 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: isCompact ? 24 : 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isCompact ? 11.5 : 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                backgroundColor: AppColors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 5,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: isCompact ? 10 : 11,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
