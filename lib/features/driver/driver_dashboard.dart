import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/auth_controller.dart';
import '../../data/models.dart';
import '../shared/terminal_radar_map.dart';

class DriverDashboardPage extends StatefulWidget {
  const DriverDashboardPage({super.key});

  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> with SingleTickerProviderStateMixin {
  final _auth = AuthController.instance;
  late final TabController _tabCtrl = TabController(length: 2, vsync: this);

  DriverStatus? _status;
  bool _loading = true;
  String? _error;
  bool _actionBusy = false;
  int _commuterDemandWaiting = 0;
  bool _isMyResponse = false;
  bool _hasSpecialWaiting = false;
  double? _pickupLat;
  double? _pickupLng;
  String? _pickupLabel;
  String? _distanceText;
  String? _etaText;
  String? _landmarkHint;
  Map<String, dynamic>? _incomingDriver;
  List<QueueItem> _terminalQueue = [];

  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _loadStatus(silent: true));
  }

  @override
  void dispose() {
    _poller?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final s = await Api.driverStatus();
      int demandCount = 0;
      bool isMine = false;
      bool hasSpecial = false;
      double? pLat;
      double? pLng;
      String? pLabel;
      String? pDist;
      String? pEta;
      String? pHint;
      Map<String, dynamic>? incoming;

      List<QueueItem> qList = [];
      final termId = s.terminalJson?['id'];
      if (termId is String) {
        try {
          final res = await Future.wait([
            Api.getDemand(termId),
            Api.queue(termId),
          ]);
          final d = res[0] as Map<String, dynamic>;
          qList = res[1] as List<QueueItem>;

          demandCount = (d['total_waiting'] as num?)?.toInt() ?? 0;
          isMine = d['is_my_response'] == true;
          incoming = d['incoming_driver'] != null ? Map<String, dynamic>.from(d['incoming_driver']) : null;
          hasSpecial = d['has_special'] == true;
          pLat = (d['pickup_lat'] as num?)?.toDouble() ?? (incoming?['pickup_lat'] as num?)?.toDouble();
          pLng = (d['pickup_lng'] as num?)?.toDouble() ?? (incoming?['pickup_lng'] as num?)?.toDouble();
          pLabel = d['pickup_label'] as String? ?? incoming?['pickup_label'] as String?;
          pDist = d['distance_text'] as String?;
          pEta = d['eta_text'] as String?;
          pHint = d['landmark_hint'] as String? ?? incoming?['landmark_hint'] as String?;

          // Real-time dynamic Haversine distance and travel time calculation
          if (pLat != null && pLng != null) {
            final tLat = (s.terminalJson?['latitude'] as num?)?.toDouble() ?? 14.2575;
            final tLng = (s.terminalJson?['longitude'] as num?)?.toDouble() ?? 121.4048;
            final meters = const Distance().as(LengthUnit.Meter, LatLng(pLat, pLng), LatLng(tLat, tLng));
            pDist = meters < 1000 ? '${meters.round()}m' : '${(meters / 1000).toStringAsFixed(1)}km';
            final mins = (meters / 200).ceil().clamp(1, 30);
            pEta = '~$mins min${mins > 1 ? 's' : ''}';
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _status = s;
        _terminalQueue = qList;
        _commuterDemandWaiting = demandCount;
        _isMyResponse = isMine;
        _hasSpecialWaiting = hasSpecial;
        _incomingDriver = incoming;
        _pickupLat = pLat;
        _pickupLng = pLng;
        _pickupLabel = pLabel;
        _distanceText = pDist;
        _etaText = pEta;
        _landmarkHint = pHint;
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

  void _handleRespondDemand(bool cancel) {
    if (_status?.terminalJson?['id'] == null) return;
    if (!cancel) {
      if (_status?.entry == null) {
        showSnack(context, 'TODA Rule: Sumali muna sa terminal queue bago sumagot sa pick-up.', error: true);
        return;
      }
    }
    final termId = _status!.terminalJson!['id'] as String;
    final isSpecial = _hasSpecialWaiting;
    _executeAction(
      () => Api.respondDemand(termId, cancel: cancel),
      successMsg: cancel
          ? 'Cancelled en route signal.'
          : (isSpecial
              ? '⚡ Solo Trip Accepted! Umabante na ang pila sa terminal para kay Queue #2.'
              : '📡 En Route confirmed! Students at the gate have been notified.'),
    );
  }

  void _handleBoardDemand(int count, bool isSpecial) {
    if (_status?.entry == null) {
      showSnack(context, 'You must join the terminal queue first to board passengers.', error: true);
      return;
    }
    _executeAction(
      () => Api.boardDemand(count, isSpecial),
      successMsg: isSpecial
          ? '⚡ Special / Solo Trip Boarded! Ready for immediate departure.'
          : '✅ Boarded $count passenger${count > 1 ? 's' : ''} successfully!',
    );
  }

  Future<void> _executeAction(Future<void> Function() action, {String? successMsg}) async {
    setState(() => _actionBusy = true);
    try {
      await action();
      if (mounted && successMsg != null) showSnack(context, successMsg);
      await _loadStatus(silent: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<bool> _verifyTerminalGeofence() async {
    final t = _status?.terminalJson;
    double tLat = (t?['latitude'] as num?)?.toDouble() ?? 0;
    double tLng = (t?['longitude'] as num?)?.toDouble() ?? 0;
    if (tLat == 0 || tLng == 0) {
      final code = (t?['code'] ?? '').toString().toUpperCase();
      if (code.contains('AV')) {
        tLat = 14.2568;
        tLng = 121.4055;
      } else if (code.contains('OVAL')) {
        tLat = 14.2558;
        tLng = 121.4042;
      } else {
        // Laguna University Main Gate 1
        tLat = 14.2575;
        tLng = 121.4048;
      }
    }

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (!mounted) return true;
        final ok = await confirmDialog(
          context,
          title: 'GPS Geofence Notice',
          message: 'Naka-off ang device location (GPS). Pakisiguraduhing nasa loob ka ng Laguna University terminal bay bago pumila.',
          confirm: 'Magpatuloy',
        );
        return ok;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 4)),
      );

      final meters = const Distance().as(
        LengthUnit.Meter,
        LatLng(pos.latitude, pos.longitude),
        LatLng(tLat, tLng),
      );

      // 180m radius allows generous campus boundary & building GPS drift
      if (meters > 180) {
        final distStr = meters < 1000 ? '${meters.round()}m' : '${(meters / 1000).toStringAsFixed(1)}km';
        if (!mounted) return true;
        final ok = await confirmDialog(
          context,
          title: 'Malayo sa Terminal Bay',
          message: 'TODA Rule: Ikaw ay $distStr ang layo mula sa terminal bay (${t?['name'] ?? 'Laguna University'}).\n\nKailangang nasa loob ka ng 180m ng terminal para sumali sa aktibong pila.',
          confirm: 'Sumali Pa Rin (Override)',
          danger: true,
        );
        return ok;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  void _handleJoinQueue() async {
    final nearby = await _verifyTerminalGeofence();
    if (!nearby || !mounted) return;
    _executeAction(Api.joinQueue, successMsg: 'Joined Laguna University terminal queue');
  }

  void _handleArrivedBack() async {
    final nearby = await _verifyTerminalGeofence();
    if (!nearby || !mounted) return;
    final termId = _status?.terminalJson?['id'] as String?;
    _executeAction(
      () async {
        if (termId != null) {
          try {
            await Api.respondDemand(termId, cancel: true);
          } catch (_) {}
        }
        await Api.arrivedBack();
        if (mounted) {
          setState(() {
            _commuterDemandWaiting = 0;
            _isMyResponse = false;
            _incomingDriver = null;
            _pickupLat = null;
            _pickupLng = null;
            _pickupLabel = null;
            _hasSpecialWaiting = false;
          });
        }
      },
      successMsg: 'Naihatid na ang pasahero. Nakabalik ka na sa terminal at pumasok sa dulo ng pila.',
    );
  }

  void _handlePassengerNoShow() async {
    if (_status?.terminalJson?['id'] == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Report Passenger No-Show',
      message: 'I-report na walang nag-abang na pasahero sa pick-up spot? Ibabalik ang iyong tricycle sa aktibong rotation ng terminal.',
      confirm: 'Report No-Show',
      danger: true,
    );
    if (!ok) return;
    final termId = _status!.terminalJson!['id'] as String;
    final hasSpecialOpenTrip = _status!.openTrip != null && _status!.openTrip?['is_special'] == true;
    _executeAction(
      () async {
        await Api.respondDemand(termId, cancel: true);
        if (hasSpecialOpenTrip) {
          await Api.arrivedBack();
        }
      },
      successMsg: 'Recorded passenger no-show. Vehicle returned to active queue rotation.',
    );
  }

  void _handlePassengerDelta(int delta) async {
    if (_status?.entry == null) return;
    final curCount = _status!.passengers;
    final cap = _status!.capacity;

    if (delta == 1 && curCount >= cap) {
      showSnack(context, 'Puno na ang tricycle ($cap pasahero).', error: true);
      return;
    }
    if (delta == -1 && curCount <= 0) {
      showSnack(context, '0 na ang bilang ng pasahero.', error: true);
      return;
    }

    _executeAction(
      () => Api.passengerDelta(delta, _status!.version),
      successMsg: delta == 1 ? 'Nakasakay (+1)' : 'Bumaba (-1)',
    );
  }

  void _handleFillCapacity() async {
    if (_status?.entry == null) return;
    final curCount = _status!.passengers;
    final cap = _status!.capacity;
    final needed = cap - curCount;
    if (needed <= 0) return;

    _executeAction(
      () async {
        var curVer = _status!.version;
        for (int i = 0; i < needed; i++) {
          await Api.passengerDelta(1, curVer + i);
        }
      },
      successMsg: 'Napunuan na ang tricycle ($cap/$cap pasahero)!',
    );
  }

  void _handleMarkReady() {
    _executeAction(Api.markReady, successMsg: 'Tricycle marked ready for departure');
  }

  void _handleUnready() {
    _executeAction(Api.unready, successMsg: 'Reverted to accepting passengers');
  }

  void _handleConfirmDeparture() async {
    _executeAction(
      () async {
        if (_status?.entryStatus != QueueStatus.ready) {
          await Api.markReady();
        }
        await Api.confirmDeparture();
      },
      successMsg: 'Biyahe na! Umabante na ang susunod na driver sa pila. Drive safely.',
    );
  }

  void _handlePause() async {
    if (_status!.passengers > 0) {
      showSnack(context, 'All passengers must step off before pausing.', error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Pause Accepting Passengers',
      message: 'Pausing will make your vehicle temporarily unavailable in the queue.',
      confirm: 'Pause',
      danger: true,
    );
    if (!ok) return;
    _executeAction(Api.pause, successMsg: 'Vehicle paused in queue');
  }

  void _handleResume() {
    _executeAction(Api.resume, successMsg: 'Resumed queue position (joined at back)');
  }

  void _handleLeaveQueue() async {
    final reason = await reasonDialog(
      context,
      title: 'Leave Terminal Queue',
      hint: 'Audit reason (e.g. End of shift, mechanical check, refueling)',
      confirm: 'Leave Queue',
      danger: true,
    );
    if (reason == null || reason.isEmpty) return;
    _executeAction(() => Api.leaveQueue(reason), successMsg: 'Removed from queue');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _status == null) {
      return const Scaffold(body: LoadingView(message: 'Initializing driver cockpit…'));
    }

    if (_error != null && _status == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Driver Dispatch')),
        body: ErrorView(error: _error!, onRetry: () => _loadStatus()),
      );
    }

    final p = _status!.profile;
    final term = _status!.terminalJson;
    final entry = _status!.entry;
    final hasOpenTrip = _status!.openTrip != null;
    final hasSpecialOpenTrip = hasOpenTrip && _status!.openTrip?['is_special'] == true;

    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth < 100) {
      return const Scaffold(body: SizedBox.shrink());
    }

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
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.electric_rickshaw_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      term != null ? term['name'] : 'Laguna University Terminal',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.2, color: AppColors.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        const PulseDot(color: AppColors.primary, size: 6),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            term != null && term['is_operating'] == true ? 'DISPATCH RADAR ONLINE' : 'TERMINAL CLOSED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: term != null && term['is_operating'] == true ? AppColors.primary : AppColors.danger,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.inkMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: -0.1),
            tabs: const [
              Tab(icon: Icon(Icons.speed_rounded, size: 18), text: 'Dispatch Cockpit'),
              Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'Trip Ledger'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Sync status',
              icon: const Icon(Icons.sync_rounded, color: AppColors.ink),
              onPressed: () => _loadStatus(),
            ),
            PopupMenuButton<String>(
              tooltip: 'Account Menu',
              icon: const Icon(Icons.account_circle_outlined, color: AppColors.ink),
              color: Colors.white,
              onSelected: (val) {
                if (val == 'fare') {
                  showFareMatrixSheet(context);
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
                      Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                      Text(
                        'Tricycle: ${_status!.vehicle?['plate_no'] ?? 'N/A'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'fare',
                  child: Row(children: [
                    Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('TODA Fare Matrix', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
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
            const SizedBox(width: 8),
          ],
        ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Tab 1: Dispatch Cockpit
          RefreshIndicator(
            onRefresh: () => _loadStatus(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ResponsiveCenter(
                maxWidth: 580,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DriverIdentityHeader(status: _status!),
                    const SizedBox(height: 14),
                    TerminalRadarMap(
                      terminalLat: (_status?.terminalJson?['latitude'] as num?)?.toDouble() ?? 14.2575,
                      terminalLng: (_status?.terminalJson?['longitude'] as num?)?.toDouble() ?? 121.4048,
                      terminalName: _status?.terminalJson?['name'] ?? 'Laguna University Terminal',
                      pickupLat: _pickupLat,
                      pickupLng: _pickupLng,
                      pickupLabel: _pickupLabel,
                      hasActiveIncoming: _isMyResponse || hasOpenTrip,
                      incomingDriverName: p.fullName,
                      incomingPlateNo: _status?.vehicle?['plate_no'],
                      isSpecialTrip: _hasSpecialWaiting || _status?.openTrip?['is_special'] == true,
                      isDriverView: true,
                      waitingCount: _commuterDemandWaiting,
                      height: 290,
                    ),
                    if ((_commuterDemandWaiting > 0 || _isMyResponse) && !hasSpecialOpenTrip) ...[
                      const SizedBox(height: 14),
                      _DriverCommuterBeaconAlert(
                        waitingCount: _commuterDemandWaiting,
                        terminalName: _status!.terminalJson?['name'] ?? 'Terminal Gate',
                        pickupLat: _pickupLat,
                        pickupLng: _pickupLng,
                        pickupLabel: _pickupLabel,
                        distanceText: _distanceText,
                        etaText: _etaText,
                        landmarkHint: _landmarkHint,
                        isMyResponse: _isMyResponse,
                        hasSpecialWaiting: _hasSpecialWaiting,
                        incomingDriver: _incomingDriver,
                        inQueue: _status?.entry != null,
                        queuePosition: _status?.position,
                        currentPassengers: _status?.passengers ?? 0,
                        capacity: _status?.capacity ?? 4,
                        terminalQueue: _terminalQueue,
                        busy: _actionBusy,
                        onRespond: () => _handleRespondDemand(false),
                        onCancelResponse: () => _handleRespondDemand(true),
                        onNoShow: _handlePassengerNoShow,
                        onBoardDemand: (count, isSpecial) => _handleBoardDemand(count, isSpecial),
                      ),
                    ],
                    const SizedBox(height: 18),

                    if (hasOpenTrip)
                      _TripReturnCard(
                        openTrip: _status!.openTrip!,
                        busy: _actionBusy,
                        onArrivedBack: _handleArrivedBack,
                        onNoShow: _handlePassengerNoShow,
                        pickupLabel: _pickupLabel,
                        pickupLat: _pickupLat,
                        pickupLng: _pickupLng,
                        landmarkHint: _landmarkHint,
                      )
                    else if (entry == null)
                      _NotInQueueCard(
                        status: _status!,
                        busy: _actionBusy,
                        onJoin: _handleJoinQueue,
                      )
                    else
                      _EnterpriseQueueControls(
                        status: _status!,
                        busy: _actionBusy,
                        onAddPassenger: () => _handlePassengerDelta(1),
                        onRemovePassenger: () => _handlePassengerDelta(-1),
                        onFillCapacity: _handleFillCapacity,
                        onMarkReady: _handleMarkReady,
                        onUnready: _handleUnready,
                        onConfirmDeparture: _handleConfirmDeparture,
                        onPause: _handlePause,
                        onResume: _handleResume,
                        onLeaveQueue: _handleLeaveQueue,
                      ),

                    const SizedBox(height: 18),
                    _DriverQueueLineupCard(
                      queue: _terminalQueue,
                      myPlateNo: _status?.vehicle?['plate_no'],
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),

          // Tab 2: Activity History
          const _DriverActivityTab(),
        ],
      ),
    ),
  );
  }
}

// ---------------------------------------------------------------------------
// Enterprise Driver Identity Card
// ---------------------------------------------------------------------------
class _DriverIdentityHeader extends StatelessWidget {
  final DriverStatus status;
  const _DriverIdentityHeader({required this.status});

  @override
  Widget build(BuildContext context) {
    final v = status.vehicle;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          AppAvatar(
            status.profile.fullName.isNotEmpty ? status.profile.fullName : 'Driver',
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
                    Text(
                      status.profile.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2, color: AppColors.ink),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: const Text('VERIFIED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PlateBadge(v != null ? v['plate_no'] : 'NO-PLATE', isFront: true),
                    Pill('${v?['capacity'] ?? '—'} Passengers Cap', icon: Icons.airline_seat_recline_normal_rounded),
                  ],
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
// Live Commuter Demand Alert Banner for Driver
// ---------------------------------------------------------------------------
class _DriverCommuterBeaconAlert extends StatelessWidget {
  final int waitingCount;
  final String terminalName;
  final double? pickupLat;
  final double? pickupLng;
  final String? pickupLabel;
  final String? distanceText;
  final String? etaText;
  final String? landmarkHint;
  final bool isMyResponse;
  final bool hasSpecialWaiting;
  final Map<String, dynamic>? incomingDriver;
  final bool inQueue;
  final int? queuePosition;
  final int currentPassengers;
  final int capacity;
  final List<QueueItem> terminalQueue;
  final bool busy;
  final VoidCallback onRespond;
  final VoidCallback onCancelResponse;
  final VoidCallback onNoShow;
  final void Function(int count, bool isSpecial) onBoardDemand;

  const _DriverCommuterBeaconAlert({
    required this.waitingCount,
    required this.terminalName,
    this.pickupLat,
    this.pickupLng,
    this.pickupLabel,
    this.distanceText,
    this.etaText,
    this.landmarkHint,
    required this.isMyResponse,
    required this.hasSpecialWaiting,
    required this.incomingDriver,
    required this.inQueue,
    required this.queuePosition,
    required this.currentPassengers,
    this.capacity = 4,
    this.terminalQueue = const [],
    required this.busy,
    required this.onRespond,
    required this.onCancelResponse,
    required this.onNoShow,
    required this.onBoardDemand,
  });

  @override
  Widget build(BuildContext context) {
    final otherResponding = incomingDriver != null && !isMyResponse;
    final isSpecialTrip = incomingDriver?['is_special'] == true || (!isMyResponse && hasSpecialWaiting);
    final committedPax = (incomingDriver?['passenger_count'] as num?)?.toInt() ?? (isSpecialTrip ? 1 : waitingCount);
    final seatsLeft = (capacity - currentPassengers).clamp(0, capacity);
    final spotName = pickupLabel ?? 'Gate 1 (Main Entrance)';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMyResponse
            ? AppColors.primarySoft.withValues(alpha: 0.4)
            : isSpecialTrip
                ? const Color(0xFFFEF3C7).withValues(alpha: 0.35)
                : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isMyResponse
              ? AppColors.primary
              : isSpecialTrip
                  ? const Color(0xFFF59E0B)
                  : AppColors.border,
          width: isMyResponse ? 1.5 : 1.0,
        ),
        boxShadow: AppShadows.card,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 360;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: isMyResponse
                          ? AppColors.primary
                          : isSpecialTrip
                              ? const Color(0xFFD97706)
                              : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      isMyResponse
                          ? Icons.navigation_rounded
                          : isSpecialTrip
                              ? Icons.bolt_rounded
                              : Icons.podcasts_rounded,
                      color: (isMyResponse || isSpecialTrip) ? Colors.white : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                              isMyResponse
                                  ? (isSpecialTrip ? 'En Route (Solo Trip)' : 'En Route to Pick Up ($committedPax Pax)')
                                  : isSpecialTrip
                                      ? 'Solo / Special Trip Signaled'
                                      : '$waitingCount Commuter${waitingCount > 1 ? 's' : ''} Signaled',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: -0.2,
                                color: isMyResponse
                                    ? AppColors.primary
                                    : isSpecialTrip
                                        ? const Color(0xFFB45309)
                                        : AppColors.ink,
                              ),
                            ),
                            if (isMyResponse)
                              const Pill('COMMITTED', fg: AppColors.primary, bg: AppColors.primarySoft)
                            else if (isSpecialTrip)
                              const Pill('SOLO TRIP', fg: Color(0xFFB45309), bg: Color(0xFFFEF3C7))
                            else if (otherResponding)
                              const Pill('EN ROUTE', fg: AppColors.info, bg: AppColors.infoSoft)
                            else if (committedPax > 1)
                              Pill('👥 $committedPax PAX', fg: AppColors.primary, bg: AppColors.primarySoft)
                            else
                              const Pill('WAITING', fg: Color(0xFFB45309), bg: Color(0xFFFEF3C7)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isMyResponse
                              ? (isSpecialTrip
                                  ? 'Student waiting at $spotName. Vehicle authorized to depart immediately upon boarding.'
                                  : 'Student can see your vehicle plate on their screen. Proceed to $spotName.')
                              : isSpecialTrip
                                  ? 'Student requested Solo / Special dispatch at $spotName. Depart right away with 1 passenger.'
                                  : otherResponding
                                      ? 'Driver ${incomingDriver!['driver_name']} is heading to $spotName to pick up.'
                                      : 'Student is actively waiting at $spotName. Tap below to confirm pick-up.',
                          style: const TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Student GPS Pick-up Waypoint Box with Navigation
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 15, color: AppColors.primary),
                        const SizedBox(width: 6),
                        const Text(
                          'PINNED SPOT:',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.5),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            spotName,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pickupLat != null && pickupLng != null) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () async {
                              final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$pickupLat,$pickupLng');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.directions_rounded, size: 12, color: AppColors.primary),
                                  SizedBox(width: 3),
                                  Text(
                                    'Maps',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (distanceText != null || etaText != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.navigation_rounded, size: 13, color: AppColors.primary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Distance: ${distanceText ?? '~300m'} • ETA: ${etaText ?? '~2 mins'}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (landmarkHint != null && landmarkHint!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.notes_rounded, size: 13, color: Color(0xFFD97706)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Student Hint: "$landmarkHint"',
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFB45309)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (isMyResponse) ...[
                if (isCompact) ...[
                  Text(
                    'Confirmed at ${incomingDriver?['responded_at'] != null ? timeAgo(DateTime.parse(incomingDriver!['responded_at'])) : 'just now'}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 15),
                        label: const Text('Cancel En Route', style: TextStyle(fontSize: 12)),
                        onPressed: busy ? null : onCancelResponse,
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFD97706)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.person_off_outlined, size: 15),
                        label: const Text('No-Show', style: TextStyle(fontSize: 12)),
                        onPressed: busy ? null : onNoShow,
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Confirmed at ${incomingDriver?['responded_at'] != null ? timeAgo(DateTime.parse(incomingDriver!['responded_at'])) : 'just now'}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFD97706)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.person_off_outlined, size: 15),
                        label: const Text('Passenger No-Show', style: TextStyle(fontSize: 12)),
                        onPressed: busy ? null : onNoShow,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 15),
                        label: const Text('Cancel En Route', style: TextStyle(fontSize: 12)),
                        onPressed: busy ? null : onCancelResponse,
                      ),
                    ],
                  ),
                ],
                if (inQueue && !isSpecialTrip) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '✅ Nakasakay Na (+$committedPax Pasahero)',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                    ),
                    onPressed: busy ? null : () => onBoardDemand(committedPax, false),
                  ),
                ],
              ] else if (!otherResponding) ...[
                Builder(
                  builder: (context) {
                    String? disallowReason;
                    String? disallowBtnLabel;

                    final activeQ = terminalQueue
                        .where((i) => i.status != QueueStatus.departed && i.status != QueueStatus.paused)
                        .toList()
                      ..sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));

                    // Dynamically determine which queue position is FIRST ELIGIBLE to service this beacon:
                    int firstEligiblePos;
                    if (isSpecialTrip) {
                      // First empty tricycle in queue (0 passengers)
                      final firstEmpty = activeQ.cast<QueueItem?>().firstWhere(
                        (i) => i != null && i.passengers == 0,
                        orElse: () => null,
                      );
                      firstEligiblePos = firstEmpty?.position ?? 1;
                    } else {
                      // First tricycle in queue with enough remaining capacity for the group
                      final firstCapable = activeQ.cast<QueueItem?>().firstWhere(
                        (i) => i != null && (i.capacity - i.passengers) >= committedPax,
                        orElse: () => null,
                      );
                      firstEligiblePos = firstCapable?.position ?? 1;
                    }

                    if (!inQueue) {
                      disallowReason = 'TODA Rule: Sumali muna sa pila ng terminal para makasundo ng pasahero.';
                      disallowBtnLabel = 'Sumali Muna sa Pila';
                    } else if (isSpecialTrip) {
                      if (currentPassengers > 0) {
                        disallowReason = 'TODA Rule: Bawal ang Solo Trip dahil may $currentPassengers regular passenger ka nang nakasakay. Nakalaan ang Solo Trip sa susunod na bakanteng tricycle sa pila (Queue #$firstEligiblePos).';
                        disallowBtnLabel = 'Bawal ang Solo Trip (May Sakay Ka Na)';
                      } else if (queuePosition != null && queuePosition != firstEligiblePos) {
                        disallowReason = 'TODA Rule: Nakalaan ang Solo Trip sa naunang bakanteng tricycle sa pila (Posisyon mo: #$queuePosition, Nakalaan kay: Queue #$firstEligiblePos).';
                        disallowBtnLabel = 'Nakalaan kay Queue #$firstEligiblePos';
                      }
                    } else {
                      // Regular Shared Trip
                      if (committedPax > seatsLeft) {
                        disallowReason = 'TODA Rule: Kulang ang bakanteng upuan ($seatsLeft na lang ang bakante pero $committedPax ang sasakay). Nakalaan ang grupong ito sa susunod na tricycle na may sapat na upuan (Queue #$firstEligiblePos).';
                        disallowBtnLabel = 'Kulang ang Upuan ($committedPax Pasahero)';
                      } else if (queuePosition != null && queuePosition != firstEligiblePos) {
                        disallowReason = 'TODA Rule: Nakalaan ang pagsundo sa naunang tricycle sa pila na may sapat na upuan (Posisyon mo: #$queuePosition, Nakalaan kay: Queue #$firstEligiblePos).';
                        disallowBtnLabel = 'Nakalaan kay Queue #$firstEligiblePos';
                      }
                    }

                    if (disallowReason != null) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.inkMuted),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    disallowReason,
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.surfaceMuted,
                              foregroundColor: AppColors.inkMuted,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                            ),
                            icon: const Icon(Icons.lock_rounded, size: 18),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                disallowBtnLabel ?? 'Hindi Pwede',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            onPressed: null,
                          ),
                        ],
                      );
                    }

                    return FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isSpecialTrip ? const Color(0xFFD97706) : AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      icon: Icon(isSpecialTrip ? Icons.bolt_rounded : Icons.two_wheeler_rounded, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          busy
                              ? 'Departing terminal bay for gate...'
                              : isSpecialTrip
                                  ? '⚡ Tanggapin ang Solo Ride (Sunduin si Student)'
                                  : '👥 Papunta Na sa Gate para Sunduin',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ),
                      onPressed: busy ? null : onRespond,
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cockpit Controls (HUD Counter, Big Touch Buttons, State Transitions)
// ---------------------------------------------------------------------------
class _EnterpriseQueueControls extends StatelessWidget {
  final DriverStatus status;
  final bool busy;
  final VoidCallback onAddPassenger;
  final VoidCallback onRemovePassenger;
  final VoidCallback onFillCapacity;
  final VoidCallback onMarkReady;
  final VoidCallback onUnready;
  final VoidCallback onConfirmDeparture;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onLeaveQueue;

  const _EnterpriseQueueControls({
    required this.status,
    required this.busy,
    required this.onAddPassenger,
    required this.onRemovePassenger,
    required this.onFillCapacity,
    required this.onMarkReady,
    required this.onUnready,
    required this.onConfirmDeparture,
    required this.onPause,
    required this.onResume,
    required this.onLeaveQueue,
  });

  @override
  Widget build(BuildContext context) {
    final entryStatus = status.entryStatus ?? QueueStatus.waiting;
    final pos = status.position;
    final count = status.passengers;
    final cap = status.capacity;
    final seatsLeft = cap - count;
    final isBoarding = entryStatus == QueueStatus.boarding || entryStatus == QueueStatus.almostFull;
    final isReady = entryStatus == QueueStatus.ready;
    final isPaused = entryStatus == QueueStatus.paused;
    final isWaiting = entryStatus == QueueStatus.waiting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.isSpecial)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt_rounded, color: Color(0xFFD97706), size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOLO / SPECIAL TRIP ACTIVE',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFB45309), letterSpacing: 0.3),
                      ),
                      Text(
                        'Authorized for immediate departure with 1 passenger. No need to wait for 4 passengers.',
                        style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // HUD Gauge Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: status.isSpecial
                  ? const Color(0xFFF59E0B)
                  : isBoarding
                      ? AppColors.primary
                      : isReady
                          ? const Color(0xFF2563EB)
                          : isPaused
                              ? AppColors.danger
                              : AppColors.border,
              width: (isBoarding || status.isSpecial) ? 1.5 : 1.0,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: pos == 1 ? AppColors.primary : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: pos == 1 ? AppColors.primary : AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (pos == 1) const PulseDot(color: Colors.white, size: 6),
                        if (pos == 1) const SizedBox(width: 6),
                        Text(
                          pos != null ? 'QUEUE #$pos' : 'PAUSED',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.5,
                            color: pos == 1 ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (status.isSpecial)
                        const Pill('SOLO DISPATCH', fg: Color(0xFFB45309), bg: Color(0xFFFEF3C7)),
                      StatusChip(entryStatus),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Digital HUD Counter
              LayoutBuilder(
                builder: (context, hudConstraints) {
                  final isCompact = hudConstraints.maxWidth < 360;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: isCompact ? 56 : 68,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                          color: status.isSpecial
                              ? const Color(0xFFD97706)
                              : isReady
                                  ? const Color(0xFF2563EB)
                                  : count >= cap
                                      ? AppColors.primary
                                      : AppColors.ink,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        status.isSpecial ? ' (Solo)' : ' / $cap',
                        style: TextStyle(
                          fontSize: isCompact ? 20 : (status.isSpecial ? 22 : 28),
                          fontWeight: FontWeight.w600,
                          color: status.isSpecial ? const Color(0xFFD97706) : AppColors.inkMuted,
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  status.isSpecial
                      ? 'SOLO / SPECIAL TRIP IN PROGRESS'
                      : seatsLeft > 0
                          ? '$seatsLeft SEAT${seatsLeft > 1 ? 'S' : ''} REMAINING'
                          : 'VEHICLE CAPACITY REACHED',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: status.isSpecial
                        ? const Color(0xFFD97706)
                        : seatsLeft <= 1
                            ? const Color(0xFFD97706)
                            : AppColors.primary,
                  ),
                ),
              ),

              const SizedBox(height: 18),
              SeatBar(
                filled: count,
                capacity: cap,
                color: status.isSpecial
                    ? const Color(0xFFD97706)
                    : isReady
                        ? const Color(0xFF2563EB)
                        : count >= cap
                            ? AppColors.primary
                            : AppColors.primary,
              ),

              if (status.isSpecial) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt_rounded, color: Color(0xFFD97706), size: 16),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Solo dispatch authorized • Depart whenever ready',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (status.needed != null && status.needed! > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Terminal policy requires ${status.needed} more passenger(s) before departure',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkSecondary, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Action Tap Controls
        if (isBoarding || isReady) ...[
          Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Bawas (-1)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    onPressed: (busy || count <= 0) ? null : onRemovePassenger,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    icon: const Icon(Icons.add_circle_rounded, size: 20),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Sakay (+1)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    onPressed: (busy || count >= cap) ? null : onAddPassenger,
                  ),
                ),
              ),
              if (seatsLeft > 1) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 54,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primarySoft,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    icon: const Icon(Icons.groups_rounded, size: 18),
                    label: const Text('Punuin', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    onPressed: busy ? null : onFillCapacity,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Streamlined 1-Tap Departure Button
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: status.policySatisfied
                    ? const Color(0xFF16A34A)
                    : AppColors.surfaceMuted,
                foregroundColor: status.policySatisfied
                    ? Colors.white
                    : AppColors.inkMuted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              icon: Icon(
                status.policySatisfied ? Icons.rocket_launch_rounded : Icons.lock_outline_rounded,
                size: 20,
              ),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  busy
                      ? 'Nagpoproseso…'
                      : status.policySatisfied
                          ? '🚀 Puno Na! Biyahe Na (Depart Now)'
                          : 'Kulang pa ng ${status.needed ?? seatsLeft} pasahero para bumyahe',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: status.policySatisfied ? -0.2 : 0,
                  ),
                ),
              ),
              onPressed: (busy || !status.policySatisfied) ? null : onConfirmDeparture,
            ),
          ),
        ],

        if (isWaiting)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_top_rounded, color: AppColors.primary, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You are queued. When the front vehicle departs, your tricycle will automatically advance to board passengers.',
                    style: TextStyle(fontSize: 13, color: AppColors.inkSecondary, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

        if (isPaused)
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: Text(busy ? 'Resuming…' : 'Resume Queue Position (Back of Queue)', style: const TextStyle(fontWeight: FontWeight.w700)),
              onPressed: busy ? null : onResume,
            ),
          ),

        const SizedBox(height: 20),
        const Divider(color: AppColors.border),
        const SizedBox(height: 10),

        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (!isPaused && !isReady)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFD97706)),
                icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
                label: const Text('Pause Accepting', style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: busy ? null : onPause,
              ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: const Icon(Icons.exit_to_app_rounded, size: 18),
              label: const Text('Leave Queue', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: busy ? null : onLeaveQueue,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Card: Arrived Back from Departed Trip
// ---------------------------------------------------------------------------
class _TripReturnCard extends StatelessWidget {
  final Map<String, dynamic> openTrip;
  final bool busy;
  final VoidCallback onArrivedBack;
  final VoidCallback? onNoShow;
  final String? pickupLabel;
  final double? pickupLat;
  final double? pickupLng;
  final String? landmarkHint;

  const _TripReturnCard({
    required this.openTrip,
    required this.busy,
    required this.onArrivedBack,
    this.onNoShow,
    this.pickupLabel,
    this.pickupLat,
    this.pickupLng,
    this.landmarkHint,
  });

  @override
  Widget build(BuildContext context) {
    final isSpecial = openTrip['is_special'] == true;
    final departedAt = DateTime.parse(openTrip['departed_at']).toLocal();
    final spotName = pickupLabel ?? 'Campus Gate (Pickup Spot)';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isSpecial ? const Color(0xFFF59E0B) : AppColors.primary,
          width: 1.5,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSpecial ? const Color(0xFFFEF3C7) : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              isSpecial ? Icons.bolt_rounded : Icons.navigation_rounded,
              color: isSpecial ? const Color(0xFFD97706) : AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isSpecial ? 'Solo Pick-Up In Progress' : 'Kasalukuyang Bumabyahe (Trip in Transit)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            isSpecial
                ? 'Umalis ka na sa terminal bay ${timeAgo(departedAt)}. Umabante na ang susunod na driver (Queue #2) sa terminal.'
                : 'Umalis ${timeAgo(departedAt)} kasama ang ${openTrip['passenger_count']} Laguna University passenger(s). Pagkahatid, i-tap sa ibaba pagbalik sa terminal.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkSecondary, fontSize: 13, height: 1.4),
          ),
          if (isSpecial) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      const Text(
                        'PICKUP SPOT:',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.5),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          spotName,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pickupLat != null && pickupLng != null) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () async {
                            final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$pickupLat,$pickupLng');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.directions_rounded, size: 12, color: AppColors.primary),
                                SizedBox(width: 3),
                                Text(
                                  'Maps',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (landmarkHint != null && landmarkHint!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.notes_rounded, size: 13, color: Color(0xFFD97706)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Student Note: "$landmarkHint"',
                            style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Color(0xFFB45309)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: isSpecial ? const Color(0xFFD97706) : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              icon: Icon(isSpecial ? Icons.check_circle_outline_rounded : Icons.arrow_circle_down_rounded, size: 20),
              label: Text(
                busy
                    ? 'Updating status…'
                    : (isSpecial
                        ? 'Naihatid na / Bumalik sa Terminal'
                        : '🏁 Naihatid na / Nakabalik na sa Terminal'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onPressed: busy ? null : onArrivedBack,
            ),
          ),
          if (isSpecial && onNoShow != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD97706),
                  side: const BorderSide(color: Color(0xFFD97706)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                icon: const Icon(Icons.person_off_outlined, size: 18),
                label: const Text('Walang Sumakay (Passenger No-Show)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: busy ? null : onNoShow,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card: Not In Queue
// ---------------------------------------------------------------------------
class _NotInQueueCard extends StatelessWidget {
  final DriverStatus status;
  final bool busy;
  final VoidCallback onJoin;
  const _NotInQueueCard({required this.status, required this.busy, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final operating = status.terminalOperating;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.hourglass_empty_rounded, size: 32, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 16),
          const Text(
            'Vehicle Not Queued',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            operating
                ? 'Join your assigned Laguna University terminal queue to enter the active dispatch rotation.'
                : 'Terminal is currently closed or outside scheduled hours.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: Text(busy ? 'Entering queue…' : 'Join Terminal Queue', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              onPressed: (!operating || busy) ? null : onJoin,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Driver Activity Ledger
// ---------------------------------------------------------------------------
class _DriverActivityTab extends StatefulWidget {
  const _DriverActivityTab();

  @override
  State<_DriverActivityTab> createState() => _DriverActivityTabState();
}

class _DriverActivityTabState extends State<_DriverActivityTab> {
  late Future<List<Map<String, dynamic>>> _activity = Api.driverActivity();
  late Future<List<Map<String, dynamic>>> _trips = Api.driverTrips();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([_activity, _trips]),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Loading trip records…');
        }
        if (snap.hasError) {
          return ErrorView(
            error: snap.error!,
            onRetry: () => setState(() {
              _activity = Api.driverActivity();
              _trips = Api.driverTrips();
            }),
          );
        }

        final data = snap.data as List<dynamic>;
        final activities = data[0] as List<Map<String, dynamic>>;
        final trips = data[1] as List<Map<String, dynamic>>;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _activity = Api.driverActivity();
              _trips = Api.driverTrips();
            });
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ResponsiveCenter(
              maxWidth: 700,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle('Today\'s Departed Trips', subtitle: '${trips.length} verified trip records'),
                  if (trips.isEmpty)
                    const EmptyState(
                      icon: Icons.route_outlined,
                      title: 'No Completed Trips Yet',
                      message: 'Trips will be logged here as you complete passenger departures.',
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: trips.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (ctx, idx) {
                        final tr = trips[idx];
                        final dep = DateTime.parse(tr['departed_at']).toLocal();
                        final ret = tr['returned_at'] != null ? DateTime.parse(tr['returned_at']).toLocal() : null;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: AppColors.border),
                            boxShadow: AppShadows.card,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                ),
                                child: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${tr['passenger_count']} Passengers Served',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Departed ${fmtDateTime(dep)} · Queue wait: ${fmtDuration(tr['wait_seconds'])}',
                                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                                    ),
                                    if (ret != null)
                                      Text(
                                        'Returned ${fmtTime(ret)}',
                                        style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 24),
                  SectionTitle('Audit Activity Ledger', subtitle: 'Immutable log of driver events'),

                  if (activities.isEmpty)
                    const EmptyState(
                      icon: Icons.list_alt_rounded,
                      title: 'No Events Recorded',
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppShadows.card,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: activities.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (ctx, idx) {
                          final act = activities[idx];
                          final ts = DateTime.parse(act['created_at']).toLocal();
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            title: Text(
                              act['action'].toString().replaceAll('_', ' ').toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.3, color: AppColors.ink),
                            ),
                            subtitle: Text(
                              act['details'] != null ? act['details'].toString() : 'State update',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                            ),
                            trailing: Text(timeAgo(ts), style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Live Terminal Queue Lineup Card (TODA Pila Roster)
// ---------------------------------------------------------------------------
class _DriverQueueLineupCard extends StatelessWidget {
  final List<QueueItem> queue;
  final String? myPlateNo;

  const _DriverQueueLineupCard({
    required this.queue,
    this.myPlateNo,
  });

  @override
  Widget build(BuildContext context) {
    // Only active tricycles in the bay (boarding, waiting, ready, paused).
    final activeQueue = queue.where((item) =>
      item.position != null &&
      item.status != QueueStatus.departed &&
      item.status != QueueStatus.removed
    ).toList();

    activeQueue.sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));

    final departedCount = queue.where((item) => item.status == QueueStatus.departed).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(Icons.format_list_numbered_rounded, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Terminal Queue Lineup',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        'FIFO Rotation • ${activeQueue.length} Active Tricycle${activeQueue.length == 1 ? '' : 's'} in Bay',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulseDot(color: AppColors.primary, size: 5),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          if (activeQueue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.electric_rickshaw_outlined, size: 36, color: AppColors.inkMuted.withValues(alpha: 0.6)),
                  const SizedBox(height: 10),
                  const Text(
                    'Walang Tricycle sa Pila',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pindutin ang "Join Terminal Queue" para ikaw ang maging unang sasakay (Queue #1).',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeQueue.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
              itemBuilder: (ctx, idx) {
                final item = activeQueue[idx];
                final pos = item.position ?? (idx + 1);
                final isMe = myPlateNo != null && item.plateNo.trim().toUpperCase() == myPlateNo!.trim().toUpperCase();
                final isFront = pos == 1;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: isMe ? AppColors.primarySoft.withValues(alpha: 0.35) : Colors.transparent,
                  child: Row(
                    children: [
                      // Position Badge
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isFront
                              ? AppColors.primary
                              : (isMe ? AppColors.primarySoft : AppColors.surfaceMuted),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: isFront
                                ? AppColors.primary
                                : (isMe ? AppColors.primary : AppColors.border),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '#$pos',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: isFront ? Colors.white : (isMe ? AppColors.primary : AppColors.ink),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Tricycle & Driver Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  item.driverDisplay.isNotEmpty ? item.driverDisplay : 'Tricycle Driver',
                                  style: TextStyle(
                                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w600,
                                    fontSize: 13,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (isMe)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(AppRadius.xs),
                                    ),
                                    child: const Text(
                                      'IKAW',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                PlateBadge(item.plateNo.isNotEmpty ? item.plateNo : 'LU-TRIKE', isFront: isFront),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatQueueStatus(item),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _statusColor(item.status),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Passengers Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isFront ? AppColors.primarySoft : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_alt_rounded,
                              size: 13,
                              color: isFront ? AppColors.primary : AppColors.inkMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${item.passengers}/${item.capacity}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isFront ? AppColors.primary : AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Bottom Info Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 14, color: AppColors.inkMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    departedCount > 0
                        ? 'Kapag umalis si #1, kusa nang aabante ang kasunod. ($departedCount tricycle ang naka-depart kamakailan)'
                        : 'Kapag nag-depart si #1, kusa nang aabante ang kasunod bilang bagong #1.',
                    style: const TextStyle(fontSize: 11, color: AppColors.inkMuted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatQueueStatus(QueueItem item) {
    switch (item.status) {
      case QueueStatus.boarding:
        return item.passengers >= item.capacity ? 'Full (Ready)' : 'Boarding (${item.seatsLeft} left)';
      case QueueStatus.almostFull:
        return 'Almost Full (${item.seatsLeft} seat left)';
      case QueueStatus.ready:
        return 'Ready to Depart';
      case QueueStatus.paused:
        return 'Paused';
      case QueueStatus.waiting:
      default:
        return 'Naghihintay sa Pila';
    }
  }

  Color _statusColor(QueueStatus status) {
    switch (status) {
      case QueueStatus.boarding:
      case QueueStatus.almostFull:
        return const Color(0xFFD97706);
      case QueueStatus.ready:
        return AppColors.primary;
      case QueueStatus.paused:
        return AppColors.danger;
      case QueueStatus.waiting:
      default:
        return AppColors.inkMuted;
    }
  }
}
