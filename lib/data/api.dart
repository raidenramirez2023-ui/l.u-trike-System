import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../core/ui.dart' show LiveState;
import 'models.dart';

/// Thin typed wrappers around Supabase RPCs. All queue writes go through
/// server-side functions that validate & lock – the client never writes
/// passenger counts or queue positions directly.
class Api {
  // ---------- Shared ----------
  static Future<List<Terminal>> terminals() async {
    final rows = await sb.rpc('list_terminals') as List;
    return rows.map((r) => Terminal.fromJson(r)).toList();
  }

  static Future<TerminalOverview> overview(String terminalId) async =>
      TerminalOverview.fromJson(await sb.rpc('get_terminal_overview', params: {'p_terminal': terminalId}));

  static Future<List<QueueItem>> queue(String terminalId) async {
    final rows = await sb.rpc('get_terminal_queue', params: {'p_terminal': terminalId}) as List;
    return rows.map((r) => QueueItem.fromJson(r)).toList();
  }

  static Future<void> submitReport({required String category, required String subject, required String body, String? terminalId, String? entryId}) =>
      sb.rpc('submit_report', params: {
        'p_category': category,
        'p_subject': subject,
        'p_body': body,
        'p_terminal': terminalId,
        'p_entry': entryId,
      });

  static Future<List<Report>> myReports() async {
    final rows = await sb.from('feedback_reports').select().eq('reporter_id', sb.auth.currentUser!.id).order('created_at', ascending: false);
    return rows.map(Report.fromJson).toList();
  }

  // ---------- Commuter Demand Beacon (Late-Night Signal) ----------
  static Future<Map<String, dynamic>> signalDemand(
    String terminalId,
    bool active, {
    int passengerCount = 1,
    bool isSpecial = false,
    double? pickupLat,
    double? pickupLng,
    String? pickupLabel,
    String? landmarkHint,
  }) async {
    try {
      final res = await sb.rpc('signal_commuter_demand', params: {
        'p_terminal': terminalId,
        'p_active': active,
        'p_passenger_count': passengerCount,
        'p_is_special': isSpecial,
        'p_pickup_lat': pickupLat,
        'p_pickup_lng': pickupLng,
        'p_pickup_label': pickupLabel ?? 'Gate 1 (Main Entrance)',
        'p_landmark_hint': landmarkHint,
      });
      return Map<String, dynamic>.from(res);
    } catch (_) {
      return {
        'terminal_id': terminalId,
        'user_active': active,
        'total_waiting': active ? passengerCount : 0,
        'passenger_count': passengerCount,
        'is_special': isSpecial,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'pickup_label': pickupLabel ?? 'Gate 1 (Main Entrance)',
        'landmark_hint': landmarkHint,
      };
    }
  }

  static Future<Map<String, dynamic>> getDemand(String terminalId) async {
    try {
      final res = await sb.rpc('get_commuter_demand', params: {
        'p_terminal': terminalId,
      });
      return Map<String, dynamic>.from(res);
    } catch (_) {
      return {'terminal_id': terminalId, 'user_active': false, 'total_waiting': 0};
    }
  }

  static Future<Map<String, dynamic>> respondDemand(String terminalId, {bool cancel = false}) async {
    final res = await sb.rpc('respond_commuter_demand', params: {
      'p_terminal': terminalId,
      'p_cancel': cancel,
    });
    return Map<String, dynamic>.from(res);
  }

  static Future<Map<String, dynamic>> boardDemand(int count, bool isSpecial) async {
    final res = await sb.rpc('driver_board_demand', params: {
      'p_count': count,
      'p_is_special': isSpecial,
    });
    return Map<String, dynamic>.from(res);
  }

  // ---------- Driver ----------
  static Future<DriverStatus> driverStatus() async => DriverStatus.fromJson(await sb.rpc('get_driver_status'));
  static Future<void> joinQueue() => sb.rpc('driver_join_queue');
  static Future<void> arrivedBack() => sb.rpc('driver_arrived_back');
  static Future<void> passengerDelta(int delta, int expectedVersion) =>
      sb.rpc('driver_passenger_delta', params: {'p_delta': delta, 'p_expected_version': expectedVersion});
  static Future<void> markReady() => sb.rpc('driver_mark_ready');
  static Future<void> unready() => sb.rpc('driver_unready');
  static Future<void> confirmDeparture() => sb.rpc('driver_confirm_departure');
  static Future<void> pause() => sb.rpc('driver_pause');
  static Future<void> resume() => sb.rpc('driver_resume');
  static Future<void> leaveQueue(String reason) => sb.rpc('driver_leave_queue', params: {'p_reason': reason});

  static Future<List<Map<String, dynamic>>> driverActivity({int limit = 100}) async =>
      List<Map<String, dynamic>>.from(await sb
          .from('queue_activity')
          .select('action, details, created_at, terminals(name)')
          .eq('driver_id', sb.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(limit));

  static Future<List<Map<String, dynamic>>> driverTrips({int limit = 50}) async => List<Map<String, dynamic>>.from(await sb
      .from('trips')
      .select()
      .eq('driver_id', sb.auth.currentUser!.id)
      .order('departed_at', ascending: false)
      .limit(limit));
}

/// Live terminal state for students (and admin monitor).
///
/// * Subscribes to Postgres changes for the terminal's queue rows, terminal
///   row and settings row.
/// * Every change triggers a debounced re-fetch from the trusted RPCs (so
///   positions are always server-computed).
/// * Exposes an honest [liveState]; after reconnection it re-syncs.
/// * [isStale] turns true when data is older than the terminal's
///   configured `stale_after_sec`.
class TerminalLiveController extends ChangeNotifier {
  final String terminalId;
  TerminalLiveController(this.terminalId);

  TerminalOverview? overview;
  List<QueueItem> queue = const [];
  Object? error;
  bool loading = true;
  LiveState liveState = LiveState.connecting;
  DateTime? lastSync;

  RealtimeChannel? _channel;
  Timer? _debounce, _ticker, _poll;
  bool _disposed = false;

  bool get isStale {
    if (lastSync == null) return false;
    final limit = overview?.settings.staleAfterSec ?? 300;
    return DateTime.now().difference(lastSync!).inSeconds > limit;
  }

  void start() {
    refresh();
    _subscribe();
    // Re-render "updated x ago" & stale state.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _notify());
    // Safety net when realtime is down: poll every 30 s.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (liveState != LiveState.live) refresh();
    });
  }

  void _subscribe() {
    _channel = sb
        .channel('terminal:$terminalId:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'terminal_queue_entries',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'terminal_id', value: terminalId),
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'terminals',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: terminalId),
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'terminal_settings',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'terminal_id', value: terminalId),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe((status, err) {
      final wasLive = liveState == LiveState.live;
      liveState = switch (status) {
        RealtimeSubscribeStatus.subscribed => LiveState.live,
        RealtimeSubscribeStatus.channelError || RealtimeSubscribeStatus.timedOut || RealtimeSubscribeStatus.closed => LiveState.offline,
      };
      // Re-sync after (re)connecting – we may have missed events.
      if (!wasLive && liveState == LiveState.live) refresh();
      _notify();
    });
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([Api.overview(terminalId), Api.queue(terminalId)]);
      overview = results[0] as TerminalOverview;
      queue = results[1] as List<QueueItem>;
      error = null;
      lastSync = DateTime.now();
    } catch (e) {
      error = e;
      if (overview != null) liveState = LiveState.offline;
    } finally {
      loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _ticker?.cancel();
    _poll?.cancel();
    if (_channel != null) sb.removeChannel(_channel!);
    super.dispose();
  }
}

/// In-app notifications (broadcasts for the user's audience + direct ones),
/// filtered client-side by the student's preferences.
class NotificationsController extends ChangeNotifier {
  final String? terminalId;
  final Map<String, bool> prefs;
  NotificationsController({this.terminalId, this.prefs = const {}});

  List<AppNotification> items = [];
  bool loading = true;
  Object? error;
  RealtimeChannel? _channel;
  bool _disposed = false;
  final _newEvents = StreamController<AppNotification>.broadcast();
  Stream<AppNotification> get onNew => _newEvents.stream;

  int get unread => items.where((n) => !n.read).length;

  bool _wanted(String type) => prefs[type] ?? true;

  void start() {
    load();
    _channel = sb
        .channel('notif:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (p) {
            final r = p.newRecord;
            final relevant = r['user_id'] == sb.auth.currentUser?.id || terminalId == null || r['terminal_id'] == terminalId;
            if (!relevant || !_wanted(r['type'] as String)) return;
            final n = AppNotification((r['id'] as num).toInt(), r['type'], r['title'], r['body'],
                DateTime.parse(r['created_at']).toLocal(), false);
            items = [n, ...items];
            _newEvents.add(n);
            _notify();
          },
        )
        .subscribe();
  }

  Future<void> load() async {
    try {
      final uid = sb.auth.currentUser!.id;
      var q = sb.from('notifications').select('id, type, title, body, created_at, terminal_id, user_id, notification_reads(user_id)');
      if (terminalId != null) {
        q = q.or('user_id.eq.$uid,terminal_id.eq.$terminalId');
      }
      final rows = await q.order('created_at', ascending: false).limit(60);
      items = rows
          .where((r) => _wanted(r['type'] as String))
          .map((r) => AppNotification(
                (r['id'] as num).toInt(),
                r['type'],
                r['title'],
                r['body'],
                DateTime.parse(r['created_at']).toLocal(),
                (r['notification_reads'] as List).isNotEmpty,
              ))
          .toList();
      error = null;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> markAllRead() async {
    final uid = sb.auth.currentUser!.id;
    final unreadIds = items.where((n) => !n.read).map((n) => n.id).toList();
    if (unreadIds.isEmpty) return;
    await sb.from('notification_reads').upsert(
          unreadIds.map((id) => {'notification_id': id, 'user_id': uid}).toList(),
          ignoreDuplicates: true,
        );
    items = items.map((n) => AppNotification(n.id, n.type, n.title, n.body, n.createdAt, true)).toList();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _newEvents.close();
    if (_channel != null) sb.removeChannel(_channel!);
    super.dispose();
  }
}
