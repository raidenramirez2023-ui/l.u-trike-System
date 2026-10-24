import 'package:flutter/material.dart';

import '../core/theme.dart';

DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
int _i(dynamic v, [int d = 0]) => v == null ? d : (v as num).toInt();

enum UserRole { student, driver, admin }

enum AccountStatus { pending, active, suspended, rejected }

UserRole roleFrom(String s) => UserRole.values.byName(s);
AccountStatus statusFrom(String s) => AccountStatus.values.byName(s);

/// Queue states mirror the `queue_status` enum in Postgres.
enum QueueStatus { waiting, boarding, almostFull, ready, departed, paused, removed }

QueueStatus queueStatusFrom(String s) => switch (s) {
      'waiting' => QueueStatus.waiting,
      'boarding' => QueueStatus.boarding,
      'almost_full' => QueueStatus.almostFull,
      'ready' => QueueStatus.ready,
      'departed' => QueueStatus.departed,
      'paused' => QueueStatus.paused,
      _ => QueueStatus.removed,
    };

String queueStatusDb(QueueStatus s) => switch (s) {
      QueueStatus.almostFull => 'almost_full',
      _ => s.name,
    };

/// Student-facing label, colour, and icon for each status.
class StatusStyle {
  final String label;
  final Color fg;
  final Color bg;
  final IconData icon;
  const StatusStyle(this.label, this.fg, this.bg, this.icon);
}

StatusStyle styleFor(QueueStatus s) => switch (s) {
      QueueStatus.waiting =>
        const StatusStyle('Waiting in Queue', AppColors.inkSecondary, AppColors.surfaceMuted, Icons.hourglass_top_rounded),
      QueueStatus.boarding => const StatusStyle('Accepting Passengers', AppColors.primary, AppColors.primarySoft, Icons.how_to_reg_rounded),
      QueueStatus.almostFull => const StatusStyle('Almost Full', AppColors.warning, AppColors.warningSoft, Icons.event_seat_rounded),
      QueueStatus.ready => const StatusStyle('Ready to Depart', AppColors.info, AppColors.infoSoft, Icons.flag_rounded),
      QueueStatus.departed =>
        const StatusStyle('Departed', AppColors.inkMuted, AppColors.surfaceMuted, Icons.check_circle_outline_rounded),
      QueueStatus.paused => const StatusStyle('Temporarily Unavailable', AppColors.danger, AppColors.dangerSoft, Icons.pause_circle_outline_rounded),
      QueueStatus.removed => const StatusStyle('Removed', AppColors.danger, AppColors.dangerSoft, Icons.remove_circle_outline_rounded),
    };

enum DeparturePolicy { full, minThreshold, driverConfirmed }

DeparturePolicy policyFrom(String s) => switch (s) {
      'full' => DeparturePolicy.full,
      'min_threshold' => DeparturePolicy.minThreshold,
      _ => DeparturePolicy.driverConfirmed,
    };

String policyDb(DeparturePolicy p) => switch (p) {
      DeparturePolicy.full => 'full',
      DeparturePolicy.minThreshold => 'min_threshold',
      DeparturePolicy.driverConfirmed => 'driver_confirmed',
    };

String policyLabel(DeparturePolicy p, int min) => switch (p) {
      DeparturePolicy.full => 'Departs when full',
      DeparturePolicy.minThreshold => 'Departs with at least $min passenger(s)',
      DeparturePolicy.driverConfirmed => 'Driver decides departure (≥1 passenger)',
    };

class Profile {
  final String id;
  final UserRole role;
  final String fullName;
  final AccountStatus status;
  final String? statusReason;
  Profile(this.id, this.role, this.fullName, this.status, this.statusReason);
  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(j['id'], roleFrom(j['role']), j['full_name'], statusFrom(j['status']), j['status_reason']);
}

class Terminal {
  final String id, code, name;
  final String? locationText, closedReason;
  final double? lat, lng;
  final bool isOpen;
  Terminal({required this.id, required this.code, required this.name, this.locationText, this.closedReason, this.lat, this.lng, required this.isOpen});
  factory Terminal.fromJson(Map<String, dynamic> j) => Terminal(
        id: j['id'],
        code: j['code'],
        name: j['name'],
        locationText: j['location_text'],
        closedReason: j['closed_reason'],
        lat: (j['latitude'] as num?)?.toDouble(),
        lng: (j['longitude'] as num?)?.toDouble(),
        isOpen: j['is_open'] ?? true,
      );
}

class TerminalSettings {
  final DeparturePolicy policy;
  final int minPassengers, almostFullOffset, staleAfterSec, longQueueThreshold, minTripsForEstimate;
  final Map<String, dynamic>? operatingHours;
  TerminalSettings.fromJson(Map<String, dynamic> j)
      : policy = policyFrom(j['departure_policy']),
        minPassengers = _i(j['min_passengers'], 1),
        almostFullOffset = _i(j['almost_full_offset'], 1),
        staleAfterSec = _i(j['stale_after_sec'], 300),
        longQueueThreshold = _i(j['long_queue_threshold'], 10),
        minTripsForEstimate = _i(j['min_trips_for_estimate'], 5),
        operatingHours = j['operating_hours'] as Map<String, dynamic>?;
}

class TerminalOverview {
  final Terminal terminal;
  final TerminalSettings settings;
  final bool isOperating;
  final int inQueue, accepting, ready, departuresToday, sampleSize;
  final int? avgIntervalSec;
  final DateTime? lastUpdated;
  final DateTime serverTime;
  TerminalOverview.fromJson(Map<String, dynamic> j)
      : terminal = Terminal.fromJson(j['terminal']),
        settings = TerminalSettings.fromJson(j['settings']),
        isOperating = j['is_operating'] == true,
        inQueue = _i(j['in_queue']),
        accepting = _i(j['accepting']),
        ready = _i(j['ready']),
        departuresToday = _i(j['departures_today']),
        sampleSize = _i(j['estimate_sample_size']),
        avgIntervalSec = j['avg_departure_interval_sec'] == null ? null : _i(j['avg_departure_interval_sec']),
        lastUpdated = _dt(j['last_updated']),
        serverTime = _dt(j['server_time'])!;
}

class QueueItem {
  final String entryId;
  final int? position;
  final QueueStatus status;
  final int passengers, capacity, seatsLeft, version;
  final int? needed;
  final String driverDisplay, plateNo;
  final DateTime joinedAt, updatedAt;
  QueueItem.fromJson(Map<String, dynamic> j)
      : entryId = j['entry_id'],
        position = j['queue_position'] == null ? null : _i(j['queue_position']),
        status = queueStatusFrom(j['status']),
        passengers = _i(j['passenger_count']),
        capacity = _i(j['capacity']),
        seatsLeft = _i(j['seats_left']),
        needed = j['needed_to_depart'] == null ? null : _i(j['needed_to_depart']),
        driverDisplay = j['driver_display'] ?? '',
        plateNo = j['plate_no'] ?? '',
        joinedAt = _dt(j['joined_at'])!,
        updatedAt = _dt(j['updated_at'])!,
        version = _i(j['version']);
}

class AppNotification {
  final int id;
  final String type, title, body;
  final DateTime createdAt;
  final bool read;
  AppNotification(this.id, this.type, this.title, this.body, this.createdAt, this.read);
}

class DriverStatus {
  final Profile profile;
  final Map<String, dynamic>? vehicle, terminalJson, entry, openTrip, verification, driver;
  final TerminalSettings? settings;
  DriverStatus.fromJson(Map<String, dynamic> j)
      : profile = Profile(j['profile']['id'], UserRole.driver, j['profile']['full_name'],
            statusFrom(j['profile']['status']), j['profile']['status_reason']),
        vehicle = j['vehicle'],
        terminalJson = j['terminal'],
        entry = j['entry'],
        openTrip = j['open_trip'],
        verification = j['verification'],
        driver = j['driver'],
        settings = j['settings'] == null ? null : TerminalSettings.fromJson(j['settings']);

  QueueStatus? get entryStatus => entry == null ? null : queueStatusFrom(entry!['status']);
  int get passengers => _i(entry?['passenger_count']);
  int get capacity => _i(entry?['capacity_snapshot'] ?? vehicle?['capacity']);
  int? get position => entry?['position'] == null ? null : _i(entry!['position']);
  int? get needed => entry?['needed'] == null ? null : _i(entry!['needed']);
  bool get policySatisfied => entry?['policy_satisfied'] == true;
  bool get isSpecial => entry?['is_special'] == true;
  int get version => _i(entry?['version']);
  bool get terminalOperating => terminalJson?['is_operating'] == true;
}

class Report {
  final String id, category, subject, body, status;
  final String? adminNotes, terminalId;
  final bool sensitive;
  final DateTime createdAt;
  Report.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        category = j['category'],
        subject = j['subject'],
        body = j['body'],
        status = j['status'],
        adminNotes = j['admin_notes'],
        terminalId = j['terminal_id'],
        sensitive = j['is_sensitive'] == true,
        createdAt = _dt(j['created_at'])!;
}

const reportCategories = {
  'feedback': 'Driver / terminal feedback',
  'queue_concern': 'Queue-related concern',
  'count_error': 'Incorrect passenger count',
  'safety': 'Safety concern',
  'lost_found': 'Lost and found',
  'incident': 'Terminal incident',
};
