import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'location_pin_picker.dart';

/// ---------------------------------------------------------------------------
/// Laguna University Campus Landmarks & GPS Points (Brgy. Bubukal, Sta. Cruz)
/// ---------------------------------------------------------------------------
class CampusLandmark {
  final String name;
  final String shortLabel;
  final LatLng position;
  final IconData icon;

  const CampusLandmark({
    required this.name,
    required this.shortLabel,
    required this.position,
    required this.icon,
  });
}

const List<CampusLandmark> kLagunaUniversityLandmarks = [
  CampusLandmark(
    name: 'Gate 1 (Main Entrance)',
    shortLabel: 'Gate 1',
    position: LatLng(14.2575, 121.4048),
    icon: Icons.school_rounded,
  ),
  CampusLandmark(
    name: 'AV Building (Academic Hall)',
    shortLabel: 'AV Bldg',
    position: LatLng(14.2568, 121.4055),
    icon: Icons.computer_rounded,
  ),
  CampusLandmark(
    name: 'LU Rooms & Oval (Track Oval)',
    shortLabel: 'Oval & Rooms',
    position: LatLng(14.2558, 121.4042),
    icon: Icons.sports_basketball_rounded,
  ),
  CampusLandmark(
    name: 'Ramil L. Hernandez Hall (Admin)',
    shortLabel: 'Admin Bldg',
    position: LatLng(14.2565, 121.4051),
    icon: Icons.account_balance_rounded,
  ),
  CampusLandmark(
    name: 'Student Canteen & Pavilion',
    shortLabel: 'Canteen/Pavilion',
    position: LatLng(14.2570, 121.4058),
    icon: Icons.restaurant_rounded,
  ),
];

/// ---------------------------------------------------------------------------
/// Registered Laguna University Tricycle Terminal Stations
/// ---------------------------------------------------------------------------
class TerminalStationMarker {
  final String code;
  final String name;
  final LatLng position;

  const TerminalStationMarker({
    required this.code,
    required this.name,
    required this.position,
  });
}

const List<TerminalStationMarker> kLagunaUniversityTerminals = [
  TerminalStationMarker(
    code: 'GATE1',
    name: 'Gate 1 Terminal',
    position: LatLng(14.2575, 121.4048),
  ),
  TerminalStationMarker(
    code: 'AVBLDG',
    name: 'AV Building Terminal',
    position: LatLng(14.2568, 121.4055),
  ),
  TerminalStationMarker(
    code: 'OVAL',
    name: 'Oval & Rooms Terminal',
    position: LatLng(14.2558, 121.4042),
  ),
];

/// ---------------------------------------------------------------------------
/// TerminalRadarMap (Phase 1: Dynamic Interactive Live Map Interface)
/// 
/// Mobile-Responsive visual radar tracker connecting:
/// 1. Satellite Imagery (Esri World Imagery) vs Vector Streets Toggle
/// 2. Live Device GPS Geolocation with 1-Tap "Locate Me"
/// 3. Active Terminal Bay (Gate 1, AV Building, or Oval & Rooms)
/// 4. Laguna University Custom Student Pin / Landmark
/// 5. Live Animated En Route Tricycle indicator
/// ---------------------------------------------------------------------------
class TerminalRadarMap extends StatefulWidget {
  final double terminalLat;
  final double terminalLng;
  final String terminalName;
  final double? pickupLat;
  final double? pickupLng;
  final String? pickupLabel;
  final bool hasActiveIncoming;
  final String? incomingDriverName;
  final String? incomingPlateNo;
  final bool isSpecialTrip;
  final bool isDriverView;
  final int waitingCount;
  final double? height;
  final bool enablePinning;
  final void Function(LatLng position, String label)? onPinChanged;

  const TerminalRadarMap({
    super.key,
    required this.terminalLat,
    required this.terminalLng,
    required this.terminalName,
    this.pickupLat,
    this.pickupLng,
    this.pickupLabel,
    this.hasActiveIncoming = false,
    this.incomingDriverName,
    this.incomingPlateNo,
    this.isSpecialTrip = false,
    this.isDriverView = false,
    this.waitingCount = 0,
    this.height,
    this.enablePinning = false,
    this.onPinChanged,
  });

  @override
  State<TerminalRadarMap> createState() => _TerminalRadarMapState();
}

class _TerminalRadarMapState extends State<TerminalRadarMap>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController = MapController();
  late AnimationController _animController;
  late Animation<double> _trikeProgress;

  late LatLng _terminalPos;
  late LatLng _pickupPos;
  late String _currentPickupLabel;
  late List<LatLng> _routePoints;

  bool _isSatellite = true;
  bool _isLocating = false;
  LatLng? _myCurrentGpsPos;

  // Live Realtime Angkas-style Tracking State
  RealtimeChannel? _trackingChannel;
  LatLng? _remoteDriverPos;
  double _remoteBearing = 0.0;
  double? _remoteRemMeters;
  bool _remoteArrived = false;
  Timer? _driverBroadcastTimer;

  @override
  void initState() {
    super.initState();
    _initCoordinates();

    // 18 seconds realistic drive progression along campus driveways
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );

    _trikeProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    if (widget.hasActiveIncoming) {
      _animController.forward(from: 0.0);
    }

    _initRealtimeTracking();
  }

  void _initRealtimeTracking() {
    try {
      final termKey = '${widget.terminalLat.toStringAsFixed(3)}_${widget.terminalLng.toStringAsFixed(3)}';
      _trackingChannel = sb.channel('trike_tracking_$termKey');

      _trackingChannel!.onBroadcast(
        event: 'driver_gps_tick',
        callback: (payload) {
          if (!mounted) return;
          // If viewing as student, receive live driver location updates
          if (!widget.isDriverView && payload['lat'] != null && payload['lng'] != null) {
            final lat = (payload['lat'] as num).toDouble();
            final lng = (payload['lng'] as num).toDouble();
            final b = (payload['bearing'] as num?)?.toDouble() ?? 0.0;
            final rem = (payload['rem'] as num?)?.toDouble() ?? 0.0;
            final arr = payload['arrived'] == true;

            setState(() {
              _remoteDriverPos = LatLng(lat, lng);
              _remoteBearing = b;
              _remoteRemMeters = rem;
              _remoteArrived = arr;
            });
          }
        },
      ).subscribe();

      if (widget.isDriverView && widget.hasActiveIncoming) {
        _startDriverBroadcaster();
      }
    } catch (_) {}
  }

  void _startDriverBroadcaster() {
    _driverBroadcastTimer?.cancel();
    _driverBroadcastTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted || !widget.hasActiveIncoming || _trackingChannel == null) return;
      final state = _getVehicleState(_trikeProgress.value);
      try {
        _trackingChannel!.sendBroadcastMessage(
          event: 'driver_gps_tick',
          payload: {
            'lat': state.pos.latitude,
            'lng': state.pos.longitude,
            'bearing': state.bearing,
            'rem': state.remainingMeters,
            'arrived': state.hasArrived,
            'plate': widget.incomingPlateNo ?? 'LU-TRIKE',
            'driver': widget.incomingDriverName ?? 'Kuya Driver',
          },
        );
      } catch (_) {}
    });
  }

  void _initCoordinates() {
    // Laguna University default base in Brgy. Bubukal
    final baseLat = widget.terminalLat != 0 ? widget.terminalLat : 14.2575;
    final baseLng = widget.terminalLng != 0 ? widget.terminalLng : 121.4048;
    _terminalPos = LatLng(baseLat, baseLng);

    // Student Pinned Location (defaults to Gate 1 if not specified)
    if (widget.pickupLat != null && widget.pickupLng != null && widget.pickupLat != 0 && widget.pickupLng != 0) {
      _pickupPos = LatLng(widget.pickupLat!, widget.pickupLng!);
    } else {
      _pickupPos = const LatLng(14.2575, 121.4048);
    }
    _currentPickupLabel = widget.pickupLabel ?? 'Gate 1 (Main Entrance)';

    _buildRoutePoints();
  }

  void _buildRoutePoints() {
    final points = <LatLng>[_terminalPos];

    // Laguna University campus road junction waypoints
    final isDestNearOval = _pickupPos.latitude < 14.2562;
    final isDestNearAV = _pickupPos.longitude > 121.4052;
    final isDestNearGate = _pickupPos.latitude > 14.2572;

    if (isDestNearGate) {
      points.add(const LatLng(14.2573, 121.4050));
    } else if (isDestNearOval) {
      points.add(const LatLng(14.2572, 121.4050));
      points.add(const LatLng(14.2565, 121.4048));
      points.add(const LatLng(14.2561, 121.4045));
    } else if (isDestNearAV) {
      points.add(const LatLng(14.2573, 121.4050));
      points.add(const LatLng(14.2569, 121.4053));
    } else {
      points.add(const LatLng(14.2568, 121.4053));
    }

    points.add(_pickupPos);
    _routePoints = points;
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final dLat = to.latitude - from.latitude;
    final dLng = to.longitude - from.longitude;
    return atan2(dLng, dLat);
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const double r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * (pi / 180.0);
    final dLng = (b.longitude - a.longitude) * (pi / 180.0);
    final lat1 = a.latitude * (pi / 180.0);
    final lat2 = b.latitude * (pi / 180.0);

    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return r * c;
  }

  ({LatLng pos, double bearing, double remainingMeters, bool hasArrived}) _getVehicleState(double t) {
    if (_remoteDriverPos != null && !widget.isDriverView) {
      return (
        pos: _remoteDriverPos!,
        bearing: _remoteBearing,
        remainingMeters: _remoteRemMeters ?? 0.0,
        hasArrived: _remoteArrived,
      );
    }

    if (_routePoints.length < 2) {
      return (pos: _terminalPos, bearing: 0.0, remainingMeters: 0, hasArrived: true);
    }

    double totalMeters = 0;
    final distances = <double>[];
    for (int i = 0; i < _routePoints.length - 1; i++) {
      final d = _distanceMeters(_routePoints[i], _routePoints[i + 1]);
      distances.add(d);
      totalMeters += d;
    }

    if (t <= 0) {
      final b = _calculateBearing(_routePoints[0], _routePoints[1]);
      return (pos: _routePoints.first, bearing: b, remainingMeters: totalMeters, hasArrived: false);
    }
    if (t >= 1.0) {
      final b = _calculateBearing(_routePoints[_routePoints.length - 2], _routePoints.last);
      return (pos: _routePoints.last, bearing: b, remainingMeters: 0, hasArrived: true);
    }

    final targetDist = totalMeters * t;
    double accumulated = 0;
    for (int i = 0; i < distances.length; i++) {
      if (accumulated + distances[i] >= targetDist) {
        final segmentDist = distances[i];
        final distInSegment = targetDist - accumulated;
        final localT = segmentDist > 0 ? (distInSegment / segmentDist) : 0.0;
        final p1 = _routePoints[i];
        final p2 = _routePoints[i + 1];

        final lat = p1.latitude + (p2.latitude - p1.latitude) * localT;
        final lng = p1.longitude + (p2.longitude - p1.longitude) * localT;
        final bearing = _calculateBearing(p1, p2);
        final rem = (totalMeters - targetDist).clamp(0.0, totalMeters);

        return (pos: LatLng(lat, lng), bearing: bearing, remainingMeters: rem, hasArrived: rem < 10);
      }
      accumulated += distances[i];
    }

    return (pos: _routePoints.last, bearing: 0.0, remainingMeters: 0, hasArrived: true);
  }

  @override
  void didUpdateWidget(TerminalRadarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool shouldRebuildRoute = false;

    if (widget.pickupLat != oldWidget.pickupLat ||
        widget.pickupLng != oldWidget.pickupLng ||
        widget.pickupLabel != oldWidget.pickupLabel) {
      if (widget.pickupLat != null && widget.pickupLng != null && widget.pickupLat != 0 && widget.pickupLng != 0) {
        _pickupPos = LatLng(widget.pickupLat!, widget.pickupLng!);
      }
      _currentPickupLabel = widget.pickupLabel ?? _currentPickupLabel;
      shouldRebuildRoute = true;
    }

    if (widget.terminalLat != oldWidget.terminalLat || widget.terminalLng != oldWidget.terminalLng) {
      final baseLat = widget.terminalLat != 0 ? widget.terminalLat : 14.2575;
      final baseLng = widget.terminalLng != 0 ? widget.terminalLng : 121.4048;
      _terminalPos = LatLng(baseLat, baseLng);
      shouldRebuildRoute = true;
    }

    if (shouldRebuildRoute) {
      _buildRoutePoints();
    }

    if (widget.hasActiveIncoming != oldWidget.hasActiveIncoming) {
      if (widget.hasActiveIncoming) {
        _animController.forward(from: 0.0);
        _startDriverBroadcaster();
      } else {
        _animController.stop();
        _animController.reset();
        _driverBroadcastTimer?.cancel();
        _remoteDriverPos = null;
        _remoteArrived = false;
      }
    }
  }

  @override
  void dispose() {
    _driverBroadcastTimer?.cancel();
    _trackingChannel?.unsubscribe();
    _animController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (!widget.enablePinning) return;

    String chosenLabel = 'Custom Spot (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
    for (final lm in kLagunaUniversityLandmarks) {
      final dLat = (point.latitude - lm.position.latitude).abs();
      final dLng = (point.longitude - lm.position.longitude).abs();
      if (dLat < 0.0004 && dLng < 0.0004) {
        chosenLabel = lm.name;
        break;
      }
    }

    setState(() {
      _pickupPos = point;
      _currentPickupLabel = chosenLabel;
      _buildRoutePoints();
    });

    widget.onPinChanged?.call(point, chosenLabel);
  }

  Future<void> _locateUser() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) showSnack(context, 'Please enable device location services (GPS).', error: true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) showSnack(context, 'Location permission was denied.', error: true);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, 'Location permissions are permanently denied. Please allow in browser.', error: true);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final userPos = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _myCurrentGpsPos = userPos;
        _pickupPos = userPos;
        _currentPickupLabel = '📍 My Live GPS Location';
        _buildRoutePoints();
      });

      _mapController.move(userPos, 17.5);
      widget.onPinChanged?.call(userPos, '📍 My Live GPS Location');

      showSnack(context, '📍 Exact GPS position locked! Pin updated.');
    } catch (e) {
      if (mounted) showSnack(context, 'GPS Locate: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _recenterCampus() {
    final centerLat = (_terminalPos.latitude + _pickupPos.latitude) / 2;
    final centerLng = (_terminalPos.longitude + _pickupPos.longitude) / 2;
    _mapController.move(LatLng(centerLat, centerLng), 17.0);
  }

  String _cleanPickupTitle(String raw) {
    var clean = raw.replaceAll('📍', '').trim();
    if (clean.toLowerCase().contains('my live gps location')) {
      return 'My GPS Location';
    }
    if (clean.length > 22) {
      return '${clean.substring(0, 20)}…';
    }
    return clean;
  }

  void _openFullScreenMap(BuildContext context) async {
    if (widget.enablePinning) {
      final res = await LocationPinPickerModal.show(
        context,
        initialPosition: _pickupPos,
        initialLabel: _currentPickupLabel,
        terminalPosition: _terminalPos,
        terminalName: widget.terminalName,
      );
      if (res != null && mounted) {
        setState(() {
          _pickupPos = res.position;
          _currentPickupLabel = res.label;
          _buildRoutePoints();
        });
        widget.onPinChanged?.call(res.position, res.label);
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FullScreenRadarModal(
        activeTerminalPos: _terminalPos,
        activeTerminalName: widget.terminalName,
        pickupPos: _pickupPos,
        pickupLabel: _currentPickupLabel,
        routePoints: _routePoints,
        hasActiveIncoming: widget.hasActiveIncoming,
        incomingDriverName: widget.incomingDriverName,
        incomingPlateNo: widget.incomingPlateNo,
        isSpecialTrip: widget.isSpecialTrip,
        isDriverView: widget.isDriverView,
        enablePinning: widget.enablePinning,
        isSatelliteInitial: _isSatellite,
        onPinChanged: (pos, label) {
          setState(() {
            _pickupPos = pos;
            _currentPickupLabel = label;
            _buildRoutePoints();
          });
          widget.onPinChanged?.call(pos, label);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final centerLat = (_terminalPos.latitude + _pickupPos.latitude) / 2;
    final centerLng = (_terminalPos.longitude + _pickupPos.longitude) / 2;
    final screenH = MediaQuery.sizeOf(context).height;
    final effectiveHeight = widget.height ?? (screenH * 0.38).clamp(290.0, 420.0);
    final cleanPickup = _cleanPickupTitle(_currentPickupLabel);

    return Container(
      height: effectiveHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.hasActiveIncoming
              ? (widget.isSpecialTrip ? AppColors.accent : AppColors.primary)
              : Colors.white.withValues(alpha: 0.15),
          width: widget.hasActiveIncoming ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // FlutterMap Tile Canvas
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(centerLat, centerLng),
              initialZoom: 17.0,
              minZoom: 14.5,
              maxZoom: 19.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
              onTap: widget.enablePinning ? _handleMapTap : null,
            ),
            children: [
              // 🛰️ High-Resolution Esri World Satellite vs 🗺️ OpenStreetMap Vector
              TileLayer(
                urlTemplate: _isSatellite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ph.edu.lu.lutrike',
                maxZoom: 19,
              ),
              // Only draw route line when an incoming driver is en route
              if (widget.hasActiveIncoming)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4.5,
                      color: widget.isSpecialTrip
                          ? AppColors.accent
                          : const Color(0xFF10B981),
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Other Laguna University Tricycle Terminal Stations
                  for (final t in kLagunaUniversityTerminals)
                    if ((t.position.latitude - _terminalPos.latitude).abs() > 0.0002 ||
                        (t.position.longitude - _terminalPos.longitude).abs() > 0.0002)
                      Marker(
                        point: t.position,
                        width: 86,
                        height: 38,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                t.name.replaceAll('Laguna University ', '').replaceAll(' Terminal', ''),
                                style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.two_wheeler_rounded, size: 14, color: Colors.white70),
                          ],
                        ),
                      ),

                  // ACTIVE Terminal Bay Marker
                  Marker(
                    point: _terminalPos,
                    width: 104,
                    height: 54,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: [
                              BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 6),
                            ],
                          ),
                          child: Text(
                            widget.terminalName.replaceAll('Laguna University ', ''),
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 1),
                        _buildPin(
                          icon: Icons.local_parking_rounded,
                          color: AppColors.primary,
                          tooltip: widget.terminalName,
                        ),
                      ],
                    ),
                  ),

                  // Pinned Pick-up Spot Marker
                  Marker(
                    point: _pickupPos,
                    width: 124,
                    height: 60,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: widget.isSpecialTrip
                                ? AppColors.accent
                                : (widget.isDriverView ? const Color(0xFF0F766E) : const Color(0xFF2563EB)),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: (widget.isSpecialTrip ? AppColors.accent : const Color(0xFF2563EB)).withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Text(
                            widget.isDriverView
                                ? '🎯 $cleanPickup'
                                : (widget.waitingCount > 0
                                    ? (widget.isSpecialTrip ? '⚡ SOLO • $cleanPickup' : '👥 ${widget.waitingCount} PAX • $cleanPickup')
                                    : '📍 $cleanPickup'),
                            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 1),
                        _buildPin(
                          icon: Icons.person_pin_circle_rounded,
                          color: widget.isSpecialTrip
                              ? AppColors.accent
                              : (widget.isDriverView ? const Color(0xFF0F766E) : const Color(0xFF2563EB)),
                          tooltip: cleanPickup,
                        ),
                      ],
                    ),
                  ),

                  // Live User Device GPS Blue Dot
                  if (_myCurrentGpsPos != null)
                    Marker(
                      point: _myCurrentGpsPos!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Color(0xFF0284C7), blurRadius: 8, spreadRadius: 2),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              // Live Animated Tricycle Marker
              // Live Animated Tricycle Marker (Angkas/Grab Style Dynamic Tracking)
              if (widget.hasActiveIncoming)
                AnimatedBuilder(
                  animation: _trikeProgress,
                  builder: (ctx, _) {
                    final vehicle = _getVehicleState(_trikeProgress.value);
                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: vehicle.pos,
                          width: 140,
                          height: 72,
                          alignment: Alignment.center,
                          child: _buildTricycleMarker(
                            plate: widget.incomingPlateNo ?? 'LU-TRIKE',
                            isSpecial: widget.isSpecialTrip,
                            bearing: vehicle.bearing,
                            remainingMeters: vehicle.remainingMeters,
                            hasArrived: vehicle.hasArrived,
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),

          // Top-Left Floating Info Pill (Stops cleanly before right toolbar)
          Positioned(
            top: 10,
            left: 10,
            right: 58,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.hasActiveIncoming
                          ? (widget.isSpecialTrip ? Icons.bolt_rounded : Icons.two_wheeler_rounded)
                          : widget.waitingCount > 0
                              ? (widget.isSpecialTrip ? Icons.bolt_rounded : Icons.sensors_rounded)
                              : Icons.place_rounded,
                      size: 15,
                      color: widget.hasActiveIncoming
                          ? (widget.isSpecialTrip ? AppColors.accent : const Color(0xFF10B981))
                          : widget.waitingCount > 0
                              ? (widget.isSpecialTrip ? AppColors.accent : AppColors.danger)
                              : const Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.hasActiveIncoming
                            ? (widget.isDriverView
                                ? 'En Route to $cleanPickup'
                                : 'Driver ${widget.incomingDriverName ?? 'Incoming'} (${widget.incomingPlateNo ?? ''}) • En Route')
                            : (widget.waitingCount > 0
                                ? (widget.isSpecialTrip ? '⚡ Solo Beacon Active' : '👥 ${widget.waitingCount} Waiting')
                                : (widget.enablePinning ? '📍 Pinned: $cleanPickup' : 'LU Campus • $cleanPickup')),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right-Side Modern Compact Toolbar (Positioned at top-right without overlapping)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🛰️ Satellite vs 🗺️ Streets Toggle
                  InkWell(
                    onTap: () => setState(() => _isSatellite = !_isSatellite),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        _isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
                        size: 18,
                        color: _isSatellite ? const Color(0xFF38BDF8) : Colors.white,
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                  // 🎯 Live Device GPS Locate Me Button
                  InkWell(
                    onTap: _isLocating ? null : _locateUser,
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: _isLocating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                            )
                          : const Icon(Icons.my_location_rounded, size: 18, color: Color(0xFF38BDF8)),
                    ),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                  // 🛺 Replay Drive Simulation (Angkas-style replay)
                  if (widget.hasActiveIncoming) ...[
                    InkWell(
                      onTap: () {
                        _animController.forward(from: 0.0);
                        showSnack(context, '🛺 Trike drive simulation started!');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 19,
                          color: widget.isSpecialTrip ? AppColors.accent : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                  ],
                  // 🏫 Recenter Campus Button
                  InkWell(
                    onTap: _recenterCampus,
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: const Icon(Icons.school_rounded, size: 18, color: Colors.white70),
                    ),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                  // ⛶ Full Screen Expand / Drag Pin Modal
                  InkWell(
                    onTap: () => _openFullScreenMap(context),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: const Icon(Icons.fullscreen_rounded, size: 19, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Quick Legend / Status Badge
          Positioned(
            bottom: 8,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isSatellite ? Icons.satellite_alt_rounded : Icons.layers_rounded,
                    color: const Color(0xFF38BDF8),
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isSatellite ? 'SATELLITE' : 'STREETS',
                    style: const TextStyle(fontSize: 9, color: Color(0xFF38BDF8), fontWeight: FontWeight.w900, letterSpacing: 0.3),
                  ),
                  if (widget.enablePinning) ...[
                    const SizedBox(width: 6),
                    const Text(
                      '• Tap map to set pin',
                      style: TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPin({required IconData icon, required Color color, required String tooltip}) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _buildTricycleMarker({
    required String plate,
    required bool isSpecial,
    required double bearing,
    required double remainingMeters,
    required bool hasArrived,
  }) {
    final remM = remainingMeters.round();
    final remSecs = (remM / 4.2).round(); // ~15km/h speed
    final remMins = (remSecs / 60).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live Angkas/Grab dynamic ETA & proximity pill above vehicle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: hasArrived
                ? const Color(0xFF059669) // Emerald arrived
                : (isSpecial ? AppColors.accent : const Color(0xFF0F172A)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasArrived ? Icons.check_circle_rounded : Icons.two_wheeler_rounded,
                size: 11,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                hasArrived
                    ? 'ARRIVED AT PICKUP!'
                    : '$plate • ${remM}m (~${remMins}m)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        // Vehicle icon with live Bearing rotation & pulsing radar glow
        Stack(
          alignment: Alignment.center,
          children: [
            // Pulse wave when active
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (hasArrived
                        ? const Color(0xFF10B981)
                        : (isSpecial ? AppColors.accent : const Color(0xFF10B981)))
                    .withValues(alpha: 0.28),
              ),
            ),
            // Rotated Vehicle Body (Faces road direction like Angkas/Grab)
            Transform.rotate(
              angle: bearing,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSpecial ? AppColors.accent : const Color(0xFF10B981),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: (isSpecial ? AppColors.accent : const Color(0xFF10B981)).withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Full-Screen Interactive Radar Modal for Mobile Phones
/// ---------------------------------------------------------------------------
class _FullScreenRadarModal extends StatefulWidget {
  final LatLng activeTerminalPos;
  final String activeTerminalName;
  final LatLng pickupPos;
  final String pickupLabel;
  final List<LatLng> routePoints;
  final bool hasActiveIncoming;
  final String? incomingDriverName;
  final String? incomingPlateNo;
  final bool isSpecialTrip;
  final bool isDriverView;
  final bool enablePinning;
  final bool isSatelliteInitial;
  final void Function(LatLng pos, String label)? onPinChanged;

  const _FullScreenRadarModal({
    required this.activeTerminalPos,
    required this.activeTerminalName,
    required this.pickupPos,
    required this.pickupLabel,
    required this.routePoints,
    required this.hasActiveIncoming,
    this.incomingDriverName,
    this.incomingPlateNo,
    required this.isSpecialTrip,
    required this.isDriverView,
    this.enablePinning = false,
    this.isSatelliteInitial = true,
    this.onPinChanged,
  });

  @override
  State<_FullScreenRadarModal> createState() => _FullScreenRadarModalState();
}

class _FullScreenRadarModalState extends State<_FullScreenRadarModal> {
  late final MapController _modalMapController = MapController();
  late LatLng _currentPickup;
  late String _currentLabel;
  late List<LatLng> _currentRoute;
  late bool _isSatellite;
  bool _isLocating = false;
  LatLng? _gpsPos;

  @override
  void initState() {
    super.initState();
    _currentPickup = widget.pickupPos;
    _currentLabel = widget.pickupLabel;
    _currentRoute = List.from(widget.routePoints);
    _isSatellite = widget.isSatelliteInitial;
  }

  @override
  void dispose() {
    _modalMapController.dispose();
    super.dispose();
  }

  void _selectLandmark(CampusLandmark lm) {
    setState(() {
      _currentPickup = lm.position;
      _currentLabel = lm.name;
      final midLat = (widget.activeTerminalPos.latitude + lm.position.latitude) / 2;
      final midLng = (widget.activeTerminalPos.longitude + lm.position.longitude) / 2 + 0.0002;
      _currentRoute = [widget.activeTerminalPos, LatLng(midLat, midLng), lm.position];
    });
    widget.onPinChanged?.call(lm.position, lm.name);
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    if (!widget.enablePinning) return;
    String chosen = 'Custom Spot (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
    for (final lm in kLagunaUniversityLandmarks) {
      final dLat = (point.latitude - lm.position.latitude).abs();
      final dLng = (point.longitude - lm.position.longitude).abs();
      if (dLat < 0.0004 && dLng < 0.0004) {
        chosen = lm.name;
        break;
      }
    }
    setState(() {
      _currentPickup = point;
      _currentLabel = chosen;
      final midLat = (widget.activeTerminalPos.latitude + point.latitude) / 2;
      final midLng = (widget.activeTerminalPos.longitude + point.longitude) / 2 + 0.0002;
      _currentRoute = [widget.activeTerminalPos, LatLng(midLat, midLng), point];
    });
    widget.onPinChanged?.call(point, chosen);
  }

  Future<void> _locateUser() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) showSnack(context, 'Please enable device location services (GPS).', error: true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) showSnack(context, 'Location permission was denied.', error: true);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, 'Location permissions are permanently denied.', error: true);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final userPos = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _gpsPos = userPos;
        _currentPickup = userPos;
        _currentLabel = '📍 My Live GPS Location';
        final midLat = (widget.activeTerminalPos.latitude + userPos.latitude) / 2;
        final midLng = (widget.activeTerminalPos.longitude + userPos.longitude) / 2 + 0.0002;
        _currentRoute = [widget.activeTerminalPos, LatLng(midLat, midLng), userPos];
      });

      _modalMapController.move(userPos, 18.0);
      widget.onPinChanged?.call(userPos, '📍 My Live GPS Location');

      showSnack(context, '📍 Exact GPS location detected! Pin updated.');
    } catch (e) {
      if (mounted) showSnack(context, 'GPS Locate: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centerLat = (widget.activeTerminalPos.latitude + _currentPickup.latitude) / 2;
    final centerLng = (widget.activeTerminalPos.longitude + _currentPickup.longitude) / 2;

    final isMobile = MediaQuery.sizeOf(context).width < 500;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.isSpecialTrip ? '⚡ Solo Radar' : 'LU Campus Radar',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            // Satellite Toggle in Modal
            IconButton(
              tooltip: _isSatellite ? 'Switch to Street Map' : 'Switch to Satellite View',
              icon: Icon(
                _isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
                color: _isSatellite ? const Color(0xFF38BDF8) : Colors.white,
              ),
              onPressed: () => setState(() => _isSatellite = !_isSatellite),
            ),
            // GPS Locate in Modal
            IconButton(
              tooltip: 'Locate My Real GPS Position',
              icon: _isLocating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                    )
                  : const Icon(Icons.my_location_rounded, color: Color(0xFF38BDF8)),
              onPressed: _isLocating ? null : _locateUser,
            ),
            if (!isMobile)
              Container(
                margin: const EdgeInsets.only(right: 14, left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _isSatellite ? const Color(0xFF0369A1) : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PulseDot(
                      color: _isSatellite ? const Color(0xFF38BDF8) : AppColors.primary,
                      size: 6,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isSatellite ? 'SATELLITE' : 'STREETS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _isSatellite ? Colors.white : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            if (isMobile) const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _modalMapController,
              options: MapOptions(
                initialCenter: LatLng(centerLat, centerLng),
                initialZoom: 17.5,
                minZoom: 14.5,
                maxZoom: 19.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
                ),
                onTap: widget.enablePinning ? _handleTap : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: _isSatellite
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ph.edu.lu.lutrike',
                  maxZoom: 19,
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _currentRoute,
                      strokeWidth: 6.0,
                      color: widget.isSpecialTrip ? AppColors.accent : const Color(0xFF10B981),
                      borderColor: Colors.white,
                      borderStrokeWidth: 2.2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // All Laguna University Tricycle Terminal Stations
                    for (final t in kLagunaUniversityTerminals)
                      if ((t.position.latitude - widget.activeTerminalPos.latitude).abs() > 0.0002 ||
                          (t.position.longitude - widget.activeTerminalPos.longitude).abs() > 0.0002)
                        Marker(
                          point: t.position,
                          width: 90,
                          height: 42,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: Text(
                                  t.name.replaceAll('Laguna University ', '').replaceAll(' Terminal', ''),
                                  style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.two_wheeler_rounded, size: 16, color: Colors.white70),
                            ],
                          ),
                        ),

                    // Active Terminal Marker
                    Marker(
                      point: widget.activeTerminalPos,
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 10),
                          ],
                        ),
                        child: const Icon(Icons.local_parking_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                    // Pinned Pick-up Marker
                    Marker(
                      point: _currentPickup,
                      width: 140,
                      height: 64,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: widget.isSpecialTrip
                                  ? AppColors.accent
                                  : (widget.isDriverView ? const Color(0xFF0F766E) : const Color(0xFF2563EB)),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white, width: 1.2),
                            ),
                            child: Text(
                              _currentLabel,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: widget.isSpecialTrip
                                  ? AppColors.accent
                                  : (widget.isDriverView ? const Color(0xFF0F766E) : const Color(0xFF2563EB)),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 10),
                              ],
                            ),
                            child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 22),
                          ),
                        ],
                      ),
                    ),
                    // Blue GPS Marker
                    if (_gpsPos != null)
                      Marker(
                        point: _gpsPos!,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(color: Color(0xFF0284C7), blurRadius: 8, spreadRadius: 2),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Top Landmark Quick-Select Chips
            if (widget.enablePinning)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kLagunaUniversityLandmarks.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final lm = kLagunaUniversityLandmarks[idx];
                      final isSelected = _currentLabel == lm.name;
                      return Material(
                        color: isSelected ? const Color(0xFF2563EB) : Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        elevation: 3,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _selectLandmark(lm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  lm.icon,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  lm.shortLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Floating Route Info Card
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 14),
                  ],
                  border: Border.all(
                    color: widget.isSpecialTrip ? AppColors.accent : Colors.white.withValues(alpha: 0.2),
                    width: widget.isSpecialTrip ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: widget.isSpecialTrip ? AppColors.accentSoft : AppColors.primarySoft,
                          radius: 20,
                          child: Icon(
                            widget.isSpecialTrip ? Icons.bolt_rounded : Icons.electric_rickshaw_rounded,
                            color: widget.isSpecialTrip ? AppColors.accent : AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isSpecialTrip
                                    ? 'Solo Trip Dispatch (${widget.activeTerminalName})'
                                    : '${widget.activeTerminalName} ↔ Pick-up Spot',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.hasActiveIncoming
                                    ? 'Driver ${widget.incomingDriverName ?? 'Assigned'} (${widget.incomingPlateNo ?? ''}) • Heading to $_currentLabel'
                                    : 'Station: ${widget.activeTerminalName} • Pick-up: $_currentLabel',
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
