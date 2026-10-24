import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:latlong2/latlong.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/models.dart';
import '../shared/terminal_radar_map.dart';
import '../shared/location_pin_picker.dart';

class StudentDashboardPage extends StatefulWidget {
  final String? initialTerminalId;
  final String? terminalCode;
  const StudentDashboardPage({super.key, this.initialTerminalId, this.terminalCode});

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  final _auth = AuthController.instance;
  List<Terminal> _terminals = [];
  Terminal? _selectedTerminal;
  bool _loadingTerminals = true;
  String? _terminalError;

  TerminalLiveController? _liveController;
  NotificationsController? _notifController;
  StreamSubscription<AppNotification>? _notifSub;

  @override
  void initState() {
    super.initState();
    _loadTerminals();
  }

  Future<void> _loadTerminals() async {
    setState(() {
      _loadingTerminals = true;
      _terminalError = null;
    });
    try {
      final list = await Api.terminals();
      if (!mounted) return;
      setState(() {
        _terminals = list;
        _loadingTerminals = false;
      });

      if (list.isEmpty) return;

      Terminal? matched;
      if (widget.terminalCode != null) {
        matched = list.cast<Terminal?>().firstWhere(
              (t) => t?.code.toUpperCase() == widget.terminalCode!.toUpperCase(),
              orElse: () => null,
            );
      }
      if (matched == null && widget.initialTerminalId != null) {
        matched = list.cast<Terminal?>().firstWhere(
              (t) => t?.id == widget.initialTerminalId,
              orElse: () => null,
            );
      }
      _switchTerminal(matched ?? list.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _terminalError = friendlyError(e);
        _loadingTerminals = false;
      });
    }
  }

  void _switchTerminal(Terminal terminal) {
    if (_selectedTerminal?.id == terminal.id && _liveController != null) return;

    _liveController?.dispose();
    _notifController?.dispose();
    _notifSub?.cancel();

    _selectedTerminal = terminal;

    _liveController = TerminalLiveController(terminal.id)..start();
    _notifController = NotificationsController(terminalId: terminal.id)..start();

    _notifSub = _notifController!.onNew.listen((notif) {
      if (mounted) {
        showSnack(context, '${notif.title}: ${notif.body}');
      }
    });

    setState(() {});
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _liveController?.dispose();
    _notifController?.dispose();
    super.dispose();
  }

  void _openReportDialog([QueueItem? item]) {
    if (_selectedTerminal == null) return;
    showDialog(
      context: context,
      builder: (_) => _StudentReportDialog(
        terminalId: _selectedTerminal!.id,
        item: item,
      ),
    );
  }

  void _openLostItemDialog() {
    if (_selectedTerminal == null) return;
    showDialog(
      context: context,
      builder: (_) => _LostItemReportDialog(
        terminalId: _selectedTerminal!.id,
        terminalName: _selectedTerminal!.name,
      ),
    );
  }

  void _openSafetySheet([QueueItem? item]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _StudentRideSafetySheet(
        terminal: _selectedTerminal,
        item: item,
        nextItem: _liveController?.queue
            .where((i) => i.status != QueueStatus.departed && i.status != QueueStatus.paused)
            .firstOrNull,
      ),
    );
  }

  void _openNotificationsSheet() {
    if (_notifController == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _NotificationsSheet(controller: _notifController!),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingTerminals) {
      return const Scaffold(body: LoadingView(message: 'Connecting to terminal radar…'));
    }

    if (_terminalError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Student Commute Portal')),
        body: ErrorView(error: _terminalError!, onRetry: _loadTerminals),
      );
    }

    if (_terminals.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Student Commute Portal')),
        body: const EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No Active Terminals',
          message: 'There are no active tricycle terminals configured at the moment.',
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth < 100) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final isMobile = screenWidth < 640;
    final isNarrow = screenWidth < 400;

    return Theme(
      data: buildStudentTheme(),
      child: Scaffold(
        backgroundColor: StudentColors.canvas,
        appBar: AppBar(
          backgroundColor: Colors.white,
          titleSpacing: isNarrow ? 8 : (isMobile ? 12 : 16),
          title: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isNarrow ? 140 : (isMobile ? 180 : 300)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 6 : 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: StudentColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTerminal?.id,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: StudentColors.ink, size: 18),
                  selectedItemBuilder: (ctx) {
                    return _terminals.map((t) {
                      return Row(
                        children: [
                          const Icon(Icons.place_rounded, color: StudentColors.primary, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isNarrow
                                  ? t.name.replaceAll('Laguna University ', 'LU ').replaceAll(' Terminal', '').replaceAll(' Tricycle', '')
                                  : t.name.replaceAll('Laguna University ', 'LU ').replaceAll(' Tricycle Terminal', ' Terminal'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: StudentColors.ink,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                  items: _terminals.map((t) {
                    return DropdownMenuItem<String>(
                      value: t.id,
                      child: Text(
                        t.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: StudentColors.ink),
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    final chosen = _terminals.firstWhere((t) => t.id == id);
                    _switchTerminal(chosen);
                  },
                ),
              ),
            ),
          ),
          actions: [
            if (_liveController != null && !isMobile)
              ListenableBuilder(
                listenable: _liveController!,
                builder: (ctx, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: LiveBadge(_liveController!.liveState),
                ),
              ),
            if (!isMobile) const SizedBox(width: 4),
            if (_notifController != null)
              ListenableBuilder(
                listenable: _notifController!,
                builder: (ctx, _) {
                  final unread = _notifController!.unread;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Notifications',
                        icon: const Icon(Icons.notifications_outlined, size: 21, color: StudentColors.ink),
                        onPressed: _openNotificationsSheet,
                      ),
                      if (unread > 0)
                        Positioned(
                          top: 10,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: StudentColors.danger,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (!isNarrow) ...[
              IconButton(
                tooltip: 'Campus Fare Matrix',
                icon: const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 21),
                onPressed: () => showFareMatrixSheet(context),
              ),
              IconButton(
                tooltip: 'Campus Safety & Trip SOS',
                icon: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 21),
                onPressed: () => _openSafetySheet(),
              ),
            ],
            PopupMenuButton<String>(
              tooltip: 'Profile Menu',
              color: Colors.white,
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  _auth.profile?.fullName.characters.first.toUpperCase() ?? 'S',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              onSelected: (val) {
                if (val == 'fare') {
                  showFareMatrixSheet(context);
                } else if (val == 'lost_found') {
                  _openLostItemDialog();
                } else if (val == 'feedback') {
                  _openReportDialog();
                } else if (val == 'safety') {
                  _openSafetySheet();
                } else if (val == 'signout') {
                  _auth.signOut();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_auth.profile?.fullName ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const Text('Laguna University Student', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'fare',
                  child: Row(children: [
                    Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Campus Fare Matrix', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'lost_found',
                  child: Row(children: [
                    Icon(Icons.search_rounded, size: 18, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Text('Lost & Found Inquiries', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (isNarrow)
                  const PopupMenuItem(
                    value: 'safety',
                    child: Row(children: [
                      Icon(Icons.shield_outlined, size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Campus Safety & Trip SOS', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                const PopupMenuItem(
                  value: 'feedback',
                  child: Row(children: [
                    Icon(Icons.feedback_outlined, size: 18, color: AppColors.inkSecondary),
                    SizedBox(width: 8),
                    Text('Submit Feedback / Report', style: TextStyle(color: AppColors.ink)),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'signout',
                  child: Row(children: [
                    Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
                    SizedBox(width: 8),
                    Text('Sign Out', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      body: _liveController == null
          ? const LoadingView()
          : ListenableBuilder(
              listenable: _liveController!,
              builder: (ctx, _) {
                if (_liveController!.loading && _liveController!.overview == null) {
                  return const LoadingView(message: 'Syncing live queue…');
                }

                if (_liveController!.error != null && _liveController!.overview == null) {
                  return ErrorView(
                    error: _liveController!.error!,
                    onRetry: _liveController!.refresh,
                  );
                }

                return RefreshIndicator(
                  onRefresh: _liveController!.refresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: ResponsiveCenter(
                      maxWidth: 820,
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_liveController!.isStale)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Banner2(
                                icon: Icons.access_time_rounded,
                                text: 'Queue radar is synchronizing. Information may be slightly delayed.',
                                fg: AppColors.warning,
                                bg: AppColors.warningSoft,
                                action: TextButton(
                                  onPressed: _liveController!.refresh,
                                  child: const Text('Re-sync'),
                                ),
                              ),
                            ),

                          if (_liveController!.overview != null)
                            _EnterpriseTerminalOverview(
                              overview: _liveController!.overview!,
                              lastSync: _liveController!.lastSync,
                            ),

                          if (_selectedTerminal != null) ...[
                            const SizedBox(height: 18),
                            _CommuterDemandBeaconCard(
                              terminal: _selectedTerminal!,
                            ),
                          ],

                          const SizedBox(height: 18),
                          _EnterpriseQueueSummary(
                            queue: _liveController!.queue,
                            onShareSafety: (item) => _openSafetySheet(item),
                          ),
                          const SizedBox(height: 22),

                          SectionTitle(
                            'Active Tricycle Lineup',
                            subtitle: '${_liveController!.queue.where((i) => i.status != QueueStatus.departed && i.status != QueueStatus.paused).length} vehicles in terminal queue',
                            trailing: TextButton.icon(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Refresh'),
                              onPressed: _liveController!.refresh,
                            ),
                          ),

                          if (_liveController!.queue.isEmpty)
                            const EmptyState(
                              icon: Icons.electric_rickshaw_outlined,
                              title: 'Queue is Empty',
                              message: 'No tricycles are currently in the queue at this terminal.',
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _liveController!.queue.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (ctx, idx) {
                                final item = _liveController!.queue[idx];
                                return _EnterpriseTricycleCard(
                                  item: item,
                                  onReportIssue: () => _openReportDialog(item),
                                  onShareSafety: () => _openSafetySheet(item),
                                );
                              },
                            ),

                          const SizedBox(height: 48),
                        ],
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

// ---------------------------------------------------------------------------
// Enterprise Terminal Overview Card
// ---------------------------------------------------------------------------
class _EnterpriseTerminalOverview extends StatelessWidget {
  final TerminalOverview overview;
  final DateTime? lastSync;
  const _EnterpriseTerminalOverview({required this.overview, this.lastSync});

  @override
  Widget build(BuildContext context) {
    final t = overview.terminal;
    final isOpen = overview.isOperating && t.isOpen;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.ink),
                    ),
                    if (t.locationText != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14.5, color: AppColors.inkMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              t.locationText!,
                              style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Pill(
                isOpen ? 'OPERATIONAL' : 'CLOSED',
                fg: isOpen ? AppColors.primary : AppColors.danger,
                bg: isOpen ? AppColors.primarySoft : AppColors.dangerSoft,
                icon: isOpen ? Icons.check_circle_rounded : Icons.cancel_rounded,
              ),
            ],
          ),

          if (!isOpen && t.closedReason != null) ...[
            const SizedBox(height: 14),
            Banner2(
              icon: Icons.info_outline_rounded,
              text: 'Terminal Status: ${t.closedReason}',
              fg: AppColors.danger,
              bg: AppColors.dangerSoft,
            ),
          ],

          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 18),

          LayoutBuilder(
            builder: (ctx, constraints) {
              final isSmall = constraints.maxWidth < 440;
              if (isSmall) {
                return Column(
                  children: [
                    StatTile(
                      label: 'Tricycles in Line',
                      value: '${overview.inQueue}',
                      icon: Icons.format_list_numbered_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Boarding Now',
                            value: '${overview.accepting}',
                            icon: Icons.how_to_reg_rounded,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatTile(
                            label: 'Ready to Leave',
                            value: '${overview.ready}',
                            icon: Icons.flag_rounded,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Tricycles in Line',
                      value: '${overview.inQueue}',
                      icon: Icons.format_list_numbered_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Boarding Now',
                      value: '${overview.accepting}',
                      icon: Icons.how_to_reg_rounded,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Ready to Leave',
                      value: '${overview.ready}',
                      icon: Icons.flag_rounded,
                      color: AppColors.info,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: AppColors.inkMuted),
                const SizedBox(width: 9),
                Expanded(
                  child: overview.avgIntervalSec != null
                      ? Text.rich(
                          TextSpan(
                            text: 'Pace estimate: ',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary),
                            children: [
                              TextSpan(
                                text: '~${fmtDuration(overview.avgIntervalSec!)} per departure',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                              ),
                              const TextSpan(
                                text: ' (Estimated from today\'s dispatches)',
                                style: TextStyle(color: AppColors.inkMuted, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        )
                      : const Text(
                          'Estimated wait time requires more recorded departures today.',
                          style: TextStyle(fontSize: 12, color: AppColors.inkMuted, fontWeight: FontWeight.w500),
                        ),
                ),
                if (lastSync != null)
                  Text(
                    'Synced ${timeAgo(lastSync!)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Queue Progress Visual Tracker
// ---------------------------------------------------------------------------
class _EnterpriseQueueSummary extends StatelessWidget {
  final List<QueueItem> queue;
  final void Function(QueueItem item)? onShareSafety;
  const _EnterpriseQueueSummary({required this.queue, this.onShareSafety});

  @override
  Widget build(BuildContext context) {
    final active = queue.where((i) => i.status != QueueStatus.departed && i.status != QueueStatus.paused).toList();
    if (active.isEmpty) return const SizedBox.shrink();

    final nextUp = active.first;
    final nextNeeded = nextUp.needed;

    final String ewtLabel;
    if (nextUp.status == QueueStatus.ready) {
      ewtLabel = 'Departing now';
    } else if (nextNeeded != null && nextNeeded <= 1) {
      ewtLabel = '~1-2 min est.';
    } else if (nextNeeded != null && nextNeeded <= 2) {
      ewtLabel = '~2-4 min est.';
    } else {
      ewtLabel = '~4-6 min est.';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 440;
        return Container(
          padding: EdgeInsets.all(isCompact ? 14 : 18),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighlight,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), width: 1.2),
            boxShadow: AppShadows.card,
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.departure_board_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 8),
                        PlateBadge(nextUp.plateNo, isFront: true),
                        const SizedBox(width: 6),
                        _EwtBadge(label: ewtLabel),
                        const Spacer(),
                        StatusChip(nextUp.status, compact: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      nextNeeded != null && nextNeeded > 0
                          ? 'Requires $nextNeeded more student passenger${nextNeeded > 1 ? 's' : ''} to meet departure policy'
                          : nextUp.status == QueueStatus.ready
                              ? 'Ready to depart now!'
                              : 'Currently filling seats (${nextUp.passengers}/${nextUp.capacity})',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkSecondary, fontWeight: FontWeight.w500),
                    ),
                    if (onShareSafety != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.shield_outlined, size: 15),
                          label: const Text('Share Ride Safety', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          onPressed: () => onShareSafety!(nextUp),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.departure_board_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Next Tricycle to Depart',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              PlateBadge(nextUp.plateNo, isFront: true),
                              const SizedBox(width: 8),
                              _EwtBadge(label: ewtLabel),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            nextNeeded != null && nextNeeded > 0
                                ? 'Requires $nextNeeded more student passenger${nextNeeded > 1 ? 's' : ''} to meet departure policy'
                                : nextUp.status == QueueStatus.ready
                                    ? 'Ready to depart now!'
                                    : 'Currently filling seats (${nextUp.passengers}/${nextUp.capacity})',
                            style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(nextUp.status, compact: true),
                    if (onShareSafety != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Share Ride Safety',
                        icon: const Icon(Icons.shield_outlined, size: 20, color: AppColors.primary),
                        onPressed: () => onShareSafety!(nextUp),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _EwtBadge extends StatelessWidget {
  final String label;
  const _EwtBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tricycle Queue Card
// ---------------------------------------------------------------------------
class _EnterpriseTricycleCard extends StatelessWidget {
  final QueueItem item;
  final VoidCallback onReportIssue;
  final VoidCallback? onShareSafety;
  const _EnterpriseTricycleCard({
    required this.item,
    required this.onReportIssue,
    this.onShareSafety,
  });

  @override
  Widget build(BuildContext context) {
    final isDeparted = item.status == QueueStatus.departed;
    final isBoarding = item.status == QueueStatus.boarding || item.status == QueueStatus.almostFull;

    return Container(
      decoration: BoxDecoration(
        color: isDeparted ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isBoarding ? AppColors.primary : AppColors.border,
          width: isBoarding ? 1.5 : 1,
        ),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, cardConstraints) {
          final isCompact = cardConstraints.maxWidth < 360;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact) ...[
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: item.position == 1 ? AppColors.primary : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: item.position == 1 ? AppColors.primary : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        item.position != null ? '#${item.position}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: item.position == 1 ? Colors.white : AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PlateBadge(item.plateNo, isFront: item.position == 1),
                    const Spacer(),
                    StatusChip(item.status, compact: true),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Driver ${item.driverDisplay}',
                        style: const TextStyle(color: AppColors.inkSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeAgo(item.joinedAt),
                      style: const TextStyle(color: AppColors.inkMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: item.position == 1 ? AppColors.primary : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: item.position == 1 ? AppColors.primary : AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        item.position != null ? '#${item.position}' : '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          color: item.position == 1 ? Colors.white : AppColors.ink,
                        ),
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
                              PlateBadge(item.plateNo, isFront: item.position == 1),
                              Text(
                                'Driver ${item.driverDisplay}',
                                style: const TextStyle(color: AppColors.inkSecondary, fontSize: 13.5, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Joined line ${timeAgo(item.joinedAt)}',
                            style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(item.status),
                  ],
                ),
              ],

          const SizedBox(height: 16),

          SeatBar(
            filled: item.passengers,
            capacity: item.capacity,
            color: item.status == QueueStatus.almostFull
                ? AppColors.warning
                : item.status == QueueStatus.ready
                    ? AppColors.info
                    : StudentColors.primary,
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Passengers: ${item.passengers} / ${item.capacity}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: StudentColors.ink),
              ),
              Text(
                item.seatsLeft > 0 ? '${item.seatsLeft} seat${item.seatsLeft > 1 ? 's' : ''} left' : 'Full capacity',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: item.seatsLeft <= 1 ? AppColors.warning : StudentColors.primary,
                ),
              ),
            ],
          ),

          if (item.needed != null && item.needed! > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Departure rule: Needs ${item.needed} more passenger${item.needed! > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, color: StudentColors.inkMuted, fontWeight: FontWeight.w500),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(color: StudentColors.border),
          const SizedBox(height: 6),

          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (onShareSafety != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: StudentColors.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.shield_outlined, size: 15),
                  label: const Text('Share Ride Safety', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: onShareSafety,
                ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: StudentColors.inkMuted,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.report_problem_outlined, size: 15),
                label: const Text('Report passenger discrepancy', style: TextStyle(fontSize: 12)),
                onPressed: onReportIssue,
              ),
            ],
          ),
        ],
      );
    }),
  );
  }
}

// ---------------------------------------------------------------------------
// Student Feedback / Incident Modal
// ---------------------------------------------------------------------------
class _StudentReportDialog extends StatefulWidget {
  final String terminalId;
  final QueueItem? item;
  const _StudentReportDialog({required this.terminalId, this.item});

  @override
  State<_StudentReportDialog> createState() => _StudentReportDialogState();
}

class _StudentReportDialogState extends State<_StudentReportDialog> {
  final _formKey = GlobalKey<FormState>();
  String _category = 'count_error';
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _subjectCtrl.text = 'Passenger discrepancy on Tricycle ${widget.item!.plateNo}';
      _bodyCtrl.text = 'The screen displays ${widget.item!.passengers} passenger(s), but at the terminal line: ';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Api.submitReport(
        category: _category,
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        terminalId: widget.terminalId,
        entryId: widget.item?.entryId,
      );
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, 'Report received. Sent for administrative review.');
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: StudentColors.border)),
      title: const Text('Submit Report / Feedback', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: StudentColors.ink)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reports are reviewed confidentially by Laguna University terminal administrators.',
                style: TextStyle(fontSize: 12.5, color: StudentColors.inkMuted),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                dropdownColor: Colors.white,
                items: reportCategories.entries.map((e) {
                  return DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: StudentColors.ink), overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (val) => setState(() => _category = val!),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(labelText: 'Subject'),
                validator: (v) => (v == null || v.trim().length < 3) ? 'Subject required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Details / Description'),
                validator: (v) => (v == null || v.trim().length < 5) ? 'Please provide details' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: StudentColors.inkMuted, fontWeight: FontWeight.w600)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: StudentColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Submitting…' : 'Submit Report'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications Bottom Sheet
// ---------------------------------------------------------------------------
class _NotificationsSheet extends StatelessWidget {
  final NotificationsController controller;
  const _NotificationsSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (ctx, _) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (ctx, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Terminal Notifications',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: StudentColors.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (controller.unread > 0)
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: StudentColors.primary),
                            onPressed: controller.markAllRead,
                            child: const Text('Mark all read', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: StudentColors.border),
                  Expanded(
                    child: controller.items.isEmpty
                        ? const EmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: 'No Active Notifications',
                            message: 'Real-time alerts for seat availability and departures appear here.',
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            itemCount: controller.items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, color: StudentColors.border),
                            itemBuilder: (ctx, idx) {
                              final n = controller.items[idx];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: n.read ? StudentColors.surfaceMuted : StudentColors.primarySoft,
                                  child: Icon(
                                    n.type == 'almost_full'
                                        ? Icons.event_seat_rounded
                                        : n.type == 'ready'
                                            ? Icons.flag_rounded
                                            : n.type == 'departed'
                                                ? Icons.check_circle_outline
                                                : Icons.notifications_outlined,
                                    color: n.read ? StudentColors.inkMuted : StudentColors.primary,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  n.title,
                                  style: TextStyle(
                                    fontWeight: n.read ? FontWeight.w500 : FontWeight.w800,
                                    fontSize: 14,
                                    color: StudentColors.ink,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(n.body, style: const TextStyle(fontSize: 13, color: StudentColors.inkSecondary)),
                                    const SizedBox(height: 2),
                                    Text(timeAgo(n.createdAt), style: const TextStyle(fontSize: 11, color: StudentColors.inkMuted)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Late-Night Commuter Demand Beacon
// ---------------------------------------------------------------------------
class _CommuterDemandBeaconCard extends StatefulWidget {
  final Terminal terminal;
  const _CommuterDemandBeaconCard({required this.terminal});

  @override
  State<_CommuterDemandBeaconCard> createState() => _CommuterDemandBeaconCardState();
}

class _CommuterDemandBeaconCardState extends State<_CommuterDemandBeaconCard> {
  bool _active = false;
  int _waitingCount = 0;
  bool _busy = false;
  int _selectedPax = 1;
  bool _isSpecial = false;
  double _pickupLat = 14.2575;
  double _pickupLng = 121.4048;
  String _pickupLabel = 'Gate 1 (Main Entrance)';
  String? _landmarkHint;
  String? _distanceText;
  String? _etaText;
  Map<String, dynamic>? _incomingDriver;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.terminal.lat != null && widget.terminal.lng != null) {
      _pickupLat = widget.terminal.lat!;
      _pickupLng = widget.terminal.lng!;
    }
    _recomputeDistanceAndEta(_pickupLat, _pickupLng);
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
  }

  @override
  void didUpdateWidget(covariant _CommuterDemandBeaconCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal.id != widget.terminal.id) {
      if (widget.terminal.lat != null && widget.terminal.lng != null) {
        _pickupLat = widget.terminal.lat!;
        _pickupLng = widget.terminal.lng!;
      }
      _recomputeDistanceAndEta(_pickupLat, _pickupLng);
      _fetch();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _recomputeDistanceAndEta(double lat, double lng) {
    final termLat = widget.terminal.lat ?? 14.2575;
    final termLng = widget.terminal.lng ?? 121.4048;
    final meters = const Distance().as(LengthUnit.Meter, LatLng(lat, lng), LatLng(termLat, termLng));
    final dist = meters < 1000 ? '${meters.round()}m' : '${(meters / 1000).toStringAsFixed(1)}km';
    final mins = (meters / 200).ceil().clamp(1, 30);
    _distanceText = dist;
    _etaText = '~$mins min${mins > 1 ? 's' : ''}';
  }

  Future<void> _useCurrentDeviceLocation() async {
    setState(() => _busy = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (mounted) showSnack(context, 'Location permission is required for live GPS.', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      if (!mounted) return;
      _onPickupLocationChanged(LatLng(pos.latitude, pos.longitude), 'My Exact GPS Spot');
      if (mounted) showSnack(context, '📍 Live GPS coordinates synced!');
    } catch (e) {
      if (mounted) showSnack(context, 'GPS error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetch() async {
    try {
      final res = await Api.getDemand(widget.terminal.id);
      if (!mounted) return;
      final prevIncoming = _incomingDriver;
      final newIncoming = res['incoming_driver'] != null ? Map<String, dynamic>.from(res['incoming_driver']) : null;
      setState(() {
        _waitingCount = res['total_waiting'] ?? 0;
        _active = res['user_active'] == true;
        _incomingDriver = newIncoming;
        if (res['distance_text'] != null) {
          _distanceText = res['distance_text'];
        }
        if (res['eta_text'] != null) {
          _etaText = res['eta_text'];
        }
        if (res['landmark_hint'] != null) {
          _landmarkHint = res['landmark_hint'];
        }
        if (_active) {
          _selectedPax = (res['my_passenger_count'] as num?)?.toInt() ?? _selectedPax;
          _isSpecial = res['my_is_special'] == true;
          if (res['my_pickup_label'] != null) {
            _pickupLabel = res['my_pickup_label'];
          }
          if (res['pickup_lat'] != null && res['pickup_lng'] != null) {
            _pickupLat = (res['pickup_lat'] as num).toDouble();
            _pickupLng = (res['pickup_lng'] as num).toDouble();
            _recomputeDistanceAndEta(_pickupLat, _pickupLng);
          }
        }
      });

      if (prevIncoming == null && newIncoming != null && _active && mounted) {
        showSnack(
          context,
          '🛺 Tricycle Incoming! Driver ${newIncoming['driver_name']} (${newIncoming['plate_no']}) is on the way to $_pickupLabel.',
        );
      }
    } catch (_) {}
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final target = !_active;
    try {
      final res = await Api.signalDemand(
        widget.terminal.id,
        target,
        passengerCount: _isSpecial ? 1 : _selectedPax,
        isSpecial: _isSpecial,
        pickupLat: _pickupLat,
        pickupLng: _pickupLng,
        pickupLabel: _pickupLabel,
        landmarkHint: _landmarkHint,
      );
      if (!mounted) return;
      setState(() {
        _active = res['active'] == true;
        _waitingCount = res['total_waiting'] ?? _waitingCount;
        if (res['pickup_label'] != null) {
          _pickupLabel = res['pickup_label'];
        }
        if (res['distance_text'] != null) {
          _distanceText = res['distance_text'];
        }
        if (res['eta_text'] != null) {
          _etaText = res['eta_text'];
        }
      });
      showSnack(
        context,
        target
            ? (_isSpecial
                ? '⚡ Solo / Special Trip Beacon Activated! Driver notified for pickup at $_pickupLabel.'
                : '📡 Beacon Activated for $_selectedPax passenger${_selectedPax > 1 ? 's' : ''} at $_pickupLabel!')
            : 'Beacon deactivated.',
      );
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleStudentOnboard() async {
    setState(() => _busy = true);
    try {
      await Api.signalDemand(
        widget.terminal.id,
        false,
        passengerCount: _isSpecial ? 1 : _selectedPax,
        isSpecial: _isSpecial,
        pickupLat: _pickupLat,
        pickupLng: _pickupLng,
        pickupLabel: _pickupLabel,
        landmarkHint: _landmarkHint,
      );
      if (!mounted) return;
      setState(() {
        _active = false;
        _incomingDriver = null;
        _isSpecial = false;
        _selectedPax = 1;
      });
      showSnack(
        context,
        '✅ Nakasakay na sa tricycle! Ingat sa biyahe.',
      );
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPinPicker() async {
    final termPos = LatLng(widget.terminal.lat ?? 14.2575, widget.terminal.lng ?? 121.4048);
    final result = await LocationPinPickerModal.show(
      context,
      initialPosition: LatLng(_pickupLat, _pickupLng),
      initialLabel: _pickupLabel,
      initialHint: _landmarkHint,
      terminalPosition: termPos,
      terminalName: widget.terminal.name,
    );

    if (result == null || !mounted) return;

    setState(() {
      _pickupLat = result.position.latitude;
      _pickupLng = result.position.longitude;
      _pickupLabel = result.label;
      _landmarkHint = result.hint;
      _recomputeDistanceAndEta(result.position.latitude, result.position.longitude);
    });

    if (_active) {
      try {
        await Api.signalDemand(
          widget.terminal.id,
          true,
          passengerCount: _isSpecial ? 1 : _selectedPax,
          isSpecial: _isSpecial,
          pickupLat: _pickupLat,
          pickupLng: _pickupLng,
          pickupLabel: _pickupLabel,
          landmarkHint: _landmarkHint,
        );
        if (mounted) showSnack(context, '📍 Pickup spot updated: $_pickupLabel');
      } catch (_) {}
    }
  }

  void _onPickupLocationChanged(LatLng pos, String label) async {
    setState(() {
      _pickupLat = pos.latitude;
      _pickupLng = pos.longitude;
      _pickupLabel = label;
      _recomputeDistanceAndEta(pos.latitude, pos.longitude);
    });

    if (_active) {
      try {
        await Api.signalDemand(
          widget.terminal.id,
          true,
          passengerCount: _isSpecial ? 1 : _selectedPax,
          isSpecial: _isSpecial,
          pickupLat: _pickupLat,
          pickupLng: _pickupLng,
          pickupLabel: _pickupLabel,
          landmarkHint: _landmarkHint,
        );
        if (mounted) {
          showSnack(context, '📍 Pick-up spot updated: $_pickupLabel');
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasIncoming = _incomingDriver != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasIncoming
            ? StudentColors.surfaceHighlight
            : _active
                ? (_isSpecial ? const Color(0xFFFFFBEB) : StudentColors.surfaceHighlight)
                : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasIncoming
              ? StudentColors.primary
              : _active
                  ? (_isSpecial ? const Color(0xFFF59E0B) : StudentColors.primary)
                  : StudentColors.border,
          width: hasIncoming || _active ? 1.8 : 1.0,
        ),
        boxShadow: hasIncoming || _active ? StudentShadows.primaryGlow : StudentShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, cardConstraints) {
              final isCompact = cardConstraints.maxWidth < 440;
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: hasIncoming || _active
                                ? (_isSpecial && !hasIncoming ? const Color(0xFFD97706) : StudentColors.primary)
                                : StudentColors.surfaceMuted,
                            shape: BoxShape.circle,
                            boxShadow: hasIncoming || _active ? StudentShadows.primaryGlow : null,
                          ),
                          child: Icon(
                            hasIncoming
                                ? Icons.two_wheeler_rounded
                                : _active
                                    ? (_isSpecial ? Icons.bolt_rounded : Icons.podcasts_rounded)
                                    : Icons.cell_tower_rounded,
                            color: hasIncoming || _active ? Colors.white : StudentColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      hasIncoming
                                          ? 'Tricycle Incoming!'
                                          : _active
                                              ? (_isSpecial ? 'Solo Trip: Beacon Active' : 'Beacon Active ($_selectedPax Pax)')
                                              : 'Commuter Demand Beacon',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: hasIncoming
                                            ? StudentColors.primary
                                            : _active
                                                ? (_isSpecial ? const Color(0xFFB45309) : StudentColors.primary)
                                                : StudentColors.ink,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  if (_waitingCount > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: StudentColors.primarySoft,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: StudentColors.primary),
                                      ),
                                      child: Text(
                                        '$_waitingCount waiting',
                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: StudentColors.primary),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hasIncoming
                                    ? 'A driver acknowledged your signal and is heading to the gate.'
                                    : _active
                                        ? (_isSpecial
                                            ? 'Solo/Special trip signaled. Immediate departure.'
                                            : 'Signaled for $_selectedPax passenger${_selectedPax > 1 ? 's' : ''}.')
                                        : 'Alert active drivers you are waiting for a ride.',
                                style: const TextStyle(fontSize: 11.5, color: StudentColors.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (hasIncoming) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: StudentColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: _busy ? null : _handleStudentOnboard,
                          icon: const Icon(Icons.check_circle_rounded, size: 16),
                          label: Text(
                            _busy ? '...' : 'Nakasakay na ako (Driver is Here)',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _active ? AppColors.dangerSoft : StudentColors.primary,
                            foregroundColor: _active ? AppColors.danger : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onPressed: _busy ? null : _toggle,
                          icon: Icon(
                            _active ? Icons.stop_circle_outlined : Icons.sensors_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _busy ? '...' : (_active ? 'Stop Beacon' : 'I\'m Waiting (Signal Drivers)'),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasIncoming || _active
                          ? (_isSpecial && !hasIncoming ? const Color(0xFFD97706) : StudentColors.primary)
                          : StudentColors.surfaceMuted,
                      shape: BoxShape.circle,
                      boxShadow: hasIncoming || _active ? StudentShadows.primaryGlow : null,
                    ),
                    child: Icon(
                      hasIncoming
                          ? Icons.two_wheeler_rounded
                          : _active
                              ? (_isSpecial ? Icons.bolt_rounded : Icons.podcasts_rounded)
                              : Icons.cell_tower_rounded,
                      color: hasIncoming || _active ? Colors.white : StudentColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                hasIncoming
                                    ? 'Tricycle Incoming!'
                                    : _active
                                        ? (_isSpecial ? 'Solo Trip: Beacon Active' : 'Beacon Active ($_selectedPax Pax)')
                                        : 'Commuter Demand Beacon',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: hasIncoming
                                      ? StudentColors.primary
                                      : _active
                                          ? (_isSpecial ? const Color(0xFFB45309) : StudentColors.primary)
                                          : StudentColors.ink,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (_waitingCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: StudentColors.primarySoft,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: StudentColors.primary),
                                ),
                                child: Text(
                                  '$_waitingCount waiting',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: StudentColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasIncoming
                              ? 'A driver acknowledged your signal and is heading to the gate.'
                              : _active
                                  ? (_isSpecial
                                      ? 'Solo/Special trip signaled. Drivers know you want an immediate departure.'
                                      : 'Signaled for $_selectedPax passenger${_selectedPax > 1 ? 's' : ''} at ${widget.terminal.name}.')
                                  : 'Waiting for a ride or heading out late? Alert active drivers to swing by.',
                          style: const TextStyle(fontSize: 12, color: StudentColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (hasIncoming) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: StudentColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onPressed: _busy ? null : _handleStudentOnboard,
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(
                        _busy ? '...' : 'Nakasakay na ako',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _active ? AppColors.dangerSoft : StudentColors.primary,
                        foregroundColor: _active ? AppColors.danger : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onPressed: _busy ? null : _toggle,
                      icon: Icon(
                        _active ? Icons.stop_circle_outlined : Icons.sensors_rounded,
                        size: 16,
                      ),
                      label: Text(
                        _busy ? '...' : (_active ? 'Stop' : 'I\'m Waiting'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),

          // Options strip when setting up beacon (Party Size & Solo Trip Mode)
          if (!_active && !hasIncoming) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: StudentColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StudentColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const Text(
                        'Trip Type:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StudentColors.inkMuted),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => setState(() => _isSpecial = false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: !_isSpecial ? StudentColors.primarySoft : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: !_isSpecial ? StudentColors.primary : StudentColors.border),
                              ),
                              child: Text(
                                '👥 Regular (Shared)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: !_isSpecial ? StudentColors.primary : StudentColors.inkSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _isSpecial = true),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isSpecial ? const Color(0xFFFEF3C7) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _isSpecial ? const Color(0xFFD97706) : StudentColors.border),
                              ),
                              child: Text(
                                '⚡ Solo / Special',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _isSpecial ? const Color(0xFFB45309) : StudentColors.inkSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_isSpecial)
                    const Text(
                      '⚡ Solo Trip: Aalis agad ang tricycle kahit ikaw lang mag-isa nang hindi na maghihintay mapuno ang 4 na upuan (TODA Special Fare).',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontStyle: FontStyle.italic),
                    )
                  else
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const Text(
                          'Ilan kayong sasakay?',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: StudentColors.inkSecondary),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final count in [1, 2, 3, 4])
                              InkWell(
                                onTap: () => setState(() => _selectedPax = count),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _selectedPax == count ? StudentColors.primary : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _selectedPax == count ? StudentColors.primary : StudentColors.border),
                                  ),
                                  child: Text(
                                    count == 4 ? '4 (Full)' : '$count',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: _selectedPax == count ? Colors.white : StudentColors.ink,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],

          // Campus Pickup Location & Interactive Map Radar
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_rounded, size: 20, color: StudentColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Pickup Spot: ',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: StudentColors.inkMuted),
                          ),
                          Flexible(
                            child: Text(
                              _pickupLabel,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: StudentColors.ink),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${_distanceText ?? '~120m'} from ${widget.terminal.name.replaceAll('Laguna University ', '')} • Est. Trike: ${_etaText ?? '~1-2 mins'}',
                        style: const TextStyle(fontSize: 11.5, color: StudentColors.inkSecondary, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: StudentColors.primary,
                    backgroundColor: StudentColors.primarySoft,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _openPinPicker,
                  icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
                  label: const Text(
                    'Pin / Note',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),

          if (_landmarkHint != null && _landmarkHint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.notes_rounded, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Note: $_landmarkHint',
                      style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Color(0xFFB45309)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Quick Campus Station Shortcut Chips + Live GPS ActionChip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 10),
                  child: ActionChip(
                    avatar: const Icon(Icons.my_location_rounded, size: 13, color: StudentColors.primary),
                    label: const Text(
                      'Live GPS',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StudentColors.primary),
                    ),
                    backgroundColor: StudentColors.primarySoft,
                    side: const BorderSide(color: StudentColors.primary),
                    onPressed: _busy ? null : _useCurrentDeviceLocation,
                  ),
                ),
                for (final lm in kLagunaUniversityLandmarks)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 10),
                    child: ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(
                        lm.icon,
                        size: 13,
                        color: _pickupLabel == lm.name ? Colors.white : StudentColors.inkSecondary,
                      ),
                      label: Text(
                        lm.shortLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _pickupLabel == lm.name ? Colors.white : StudentColors.ink,
                        ),
                      ),
                      selected: _pickupLabel == lm.name,
                      selectedColor: StudentColors.primary,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: _pickupLabel == lm.name ? StudentColors.primary : StudentColors.border,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          _onPickupLocationChanged(lm.position, lm.name);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),

          // En Route Driver Handshake Card
          if (hasIncoming) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StudentColors.primary, width: 1.2),
                boxShadow: StudentShadows.primaryGlow,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      PlateBadge(_incomingDriver!['plate_no'] ?? 'LU-TRIKE', isFront: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Driver: ${_incomingDriver!['driver_name'] ?? 'Assigned Driver'}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: StudentColors.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'En route to $_pickupLabel (~2-3 mins).',
                              style: const TextStyle(fontSize: 11.5, color: StudentColors.inkSecondary),
                            ),
                          ],
                        ),
                      ),
                      const Pill('EN ROUTE', fg: StudentColors.primary, bg: StudentColors.primarySoft, icon: Icons.navigation_rounded),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: StudentColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(
                        _busy ? 'Updating...' : 'Nakasakay na ako (Driver is Here)',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      onPressed: _busy ? null : _handleStudentOnboard,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Responsive Interactive Live Map Radar
          TerminalRadarMap(
            terminalLat: widget.terminal.lat ?? 14.2575,
            terminalLng: widget.terminal.lng ?? 121.4048,
            terminalName: widget.terminal.name,
            pickupLat: _pickupLat,
            pickupLng: _pickupLng,
            pickupLabel: _pickupLabel,
            enablePinning: true,
            onPinChanged: _onPickupLocationChanged,
            hasActiveIncoming: hasIncoming,
            incomingDriverName: _incomingDriver?['driver_name'],
            incomingPlateNo: _incomingDriver?['plate_no'],
            isSpecialTrip: _isSpecial || _incomingDriver?['is_special'] == true,
            waitingCount: _waitingCount,
            height: 310,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Student Ride Safety & Campus Emergency SOS Sheet
// ---------------------------------------------------------------------------
class _StudentRideSafetySheet extends StatelessWidget {
  final Terminal? terminal;
  final QueueItem? item;
  final QueueItem? nextItem;

  const _StudentRideSafetySheet({this.terminal, this.item, this.nextItem});

  @override
  Widget build(BuildContext context) {
    final activeItem = item ?? nextItem;
    final auth = AuthController.instance;
    final studentName = auth.profile?.fullName ?? 'Laguna University Student';
    final terminalName = terminal?.name ?? 'Laguna University Tricycle Terminal';
    final plate = activeItem?.plateNo ?? 'Unknown / Not yet assigned';
    final driver = activeItem != null && activeItem.driverDisplay.isNotEmpty
        ? activeItem.driverDisplay
        : 'Standby Driver';

    final shareText = '''🛡️ LU COMMUTE SAFETY SHARE
Passenger: $studentName
Terminal: $terminalName
Vehicle Plate: $plate
Driver: $driver
Timestamp: ${DateTime.now().toLocal().toString().split('.').first}
Status: Tracked via Laguna University Tricycle Commute System''';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: StudentColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: StudentColors.primarySoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: StudentColors.primary),
                      ),
                      child: const Icon(Icons.shield_rounded, color: StudentColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ride Safety & Emergency SOS',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: StudentColors.ink),
                          ),
                          Text(
                            'Share trip info with loved ones or call campus emergency responders.',
                            style: TextStyle(fontSize: 12.5, color: StudentColors.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Active Trip Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: StudentColors.border),
                    boxShadow: StudentShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'VEHICLE & RIDE TELEMETRY',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: StudentColors.inkMuted, letterSpacing: 0.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          Pill('ACTIVE COMMUTE', fg: StudentColors.primary, bg: StudentColors.primarySoft),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (activeItem != null)
                            PlateBadge(activeItem.plateNo, isFront: true)
                          else
                            const Text('No Tricycle Selected', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                driver,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: StudentColors.ink),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Terminal: $terminalName',
                        style: const TextStyle(fontSize: 12.5, color: StudentColors.inkSecondary),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: StudentColors.primary,
                          side: const BorderSide(color: StudentColors.primary),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        icon: const Icon(Icons.copy_all_rounded, size: 18),
                        label: const Text('Copy Trip Details for Family / Friends', style: TextStyle(fontWeight: FontWeight.w800)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareText));
                          showSnack(context, '📋 Trip safety details copied to clipboard!');
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),
                const Text(
                  'CAMPUS EMERGENCY HOTLINES',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: StudentColors.inkMuted, letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),

                const _HotlineTile(
                  title: 'LU Campus Security & Guard Desk',
                  phone: '(049) 501-4444',
                  uri: 'tel:0495014444',
                  color: StudentColors.primary,
                  icon: Icons.local_police_rounded,
                ),
                const SizedBox(height: 8),
                const _HotlineTile(
                  title: 'Santa Cruz Laguna Police Station',
                  phone: '(049) 501-1234',
                  uri: 'tel:0495011234',
                  color: Color(0xFFD97706),
                  icon: Icons.shield_rounded,
                ),
                const SizedBox(height: 8),
                const _HotlineTile(
                  title: 'LU University Clinic / Medical SOS',
                  phone: '0917-888-9999',
                  uri: 'tel:09178889999',
                  color: AppColors.danger,
                  icon: Icons.medical_services_rounded,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HotlineTile extends StatelessWidget {
  final String title;
  final String phone;
  final String uri;
  final Color color;
  final IconData icon;

  const _HotlineTile({
    required this.title,
    required this.phone,
    required this.uri,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudentColors.border),
        boxShadow: StudentShadows.card,
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: StudentColors.ink)),
        subtitle: Text(phone, style: const TextStyle(fontSize: 12, color: StudentColors.inkSecondary)),
        trailing: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.18),
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: const Icon(Icons.call_rounded, size: 16),
          label: const Text('Call', style: TextStyle(fontWeight: FontWeight.w800)),
          onPressed: () async {
            final u = Uri.parse(uri);
            if (await canLaunchUrl(u)) {
              await launchUrl(u);
            } else {
              if (context.mounted) {
                Clipboard.setData(ClipboardData(text: phone));
                showSnack(context, 'Emergency phone $phone copied to clipboard!');
              }
            }
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Campus Lost & Found Helper Modal
// ---------------------------------------------------------------------------
class _LostItemReportDialog extends StatefulWidget {
  final String terminalId;
  final String terminalName;
  const _LostItemReportDialog({required this.terminalId, required this.terminalName});

  @override
  State<_LostItemReportDialog> createState() => _LostItemReportDialogState();
}

class _LostItemReportDialogState extends State<_LostItemReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _itemDescCtrl = TextEditingController();
  final _approxTimeCtrl = TextEditingController();
  final _plateOrDriverCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _itemDescCtrl.dispose();
    _approxTimeCtrl.dispose();
    _plateOrDriverCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final subject = 'Lost Item Report: ${_itemDescCtrl.text.trim()}';
      final body = '''
Item Description: ${_itemDescCtrl.text.trim()}
Estimated Trip Time/Date: ${_approxTimeCtrl.text.trim().isEmpty ? 'Not specified' : _approxTimeCtrl.text.trim()}
Tricycle / Driver Details: ${_plateOrDriverCtrl.text.trim().isEmpty ? 'Unknown / Not remembered' : _plateOrDriverCtrl.text.trim()}
Student Contact Number: ${_contactPhoneCtrl.text.trim()}
Terminal Origin: ${widget.terminalName}
''';

      await Api.submitReport(
        category: 'lost_found',
        subject: subject,
        body: body,
        terminalId: widget.terminalId,
      );

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: StudentColors.border),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: StudentColors.primary, size: 24),
                SizedBox(width: 8),
                Text('Report Dispatched', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ],
            ),
            content: const Text(
              'Your lost item report has been logged and transmitted to the Terminal Dispatcher & Campus Security desk. Please visit or call the Security Guard station if urgent.',
              style: TextStyle(fontSize: 13, color: StudentColors.inkSecondary, height: 1.45),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: StudentColors.primary),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Understood'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: StudentColors.border),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: StudentColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.find_in_page_rounded, color: StudentColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Report Lost Item',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: StudentColors.ink),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StudentColors.canvas,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StudentColors.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: StudentColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Left something in a tricycle? Terminal dispatchers and campus security will cross-reference driver trip logs.',
                          style: TextStyle(fontSize: 11.5, color: StudentColors.inkSecondary, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('What was left behind? *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _itemDescCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Black backpack with LU ID, blue umbrella, wallet',
                    prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe the missing item' : null,
                ),
                const SizedBox(height: 12),
                const Text('Approximate Trip Time / Date', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _approxTimeCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Today around 2:30 PM, from LU gate to Bubukal',
                    prefixIcon: Icon(Icons.access_time_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Tricycle Plate / Driver (if remembered)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _plateOrDriverCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Plate 1234, blue body sticker',
                    prefixIcon: Icon(Icons.electric_rickshaw_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Your Contact Phone Number *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _contactPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'e.g. 09171234567',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().length < 7) ? 'Valid contact number required for retrieval' : null,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Campus Guard Desk Urgent Hotline: (049) 501-4444',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF78350F)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: StudentColors.primary),
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
