import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import 'terminal_radar_map.dart';

/// ---------------------------------------------------------------------------
/// LocationPinPickerModal (Clean Grab / Pedi-App Style Pin-Drop Sheet)
/// ---------------------------------------------------------------------------
class LocationPinPickerModal extends StatefulWidget {
  final LatLng initialPosition;
  final String initialLabel;
  final String? initialHint;
  final LatLng terminalPosition;
  final String terminalName;

  const LocationPinPickerModal({
    super.key,
    required this.initialPosition,
    required this.initialLabel,
    this.initialHint,
    required this.terminalPosition,
    required this.terminalName,
  });

  static Future<({LatLng position, String label, String? hint})?> show(
    BuildContext context, {
    required LatLng initialPosition,
    required String initialLabel,
    String? initialHint,
    required LatLng terminalPosition,
    required String terminalName,
  }) {
    return showModalBottomSheet<({LatLng position, String label, String? hint})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LocationPinPickerModal(
        initialPosition: initialPosition,
        initialLabel: initialLabel,
        initialHint: initialHint,
        terminalPosition: terminalPosition,
        terminalName: terminalName,
      ),
    );
  }

  @override
  State<LocationPinPickerModal> createState() => _LocationPinPickerModalState();
}

class _LocationPinPickerModalState extends State<LocationPinPickerModal> {
  late final MapController _mapController = MapController();
  late LatLng _currentCenter;
  late String _currentLabel;
  late final TextEditingController _hintController;

  bool _isSatellite = true;
  bool _isLocating = false;
  LatLng? _deviceGpsPos;

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialPosition;
    _currentLabel = widget.initialLabel;
    _hintController = TextEditingController(text: widget.initialHint);
  }

  @override
  void dispose() {
    _mapController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    final center = camera.center;
    String newLabel = 'Custom Spot (${center.latitude.toStringAsFixed(4)}, ${center.longitude.toStringAsFixed(4)})';

    for (final lm in kLagunaUniversityLandmarks) {
      final dLat = (center.latitude - lm.position.latitude).abs();
      final dLng = (center.longitude - lm.position.longitude).abs();
      if (dLat < 0.00035 && dLng < 0.00035) {
        newLabel = lm.name;
        break;
      }
    }

    setState(() {
      _currentCenter = center;
      _currentLabel = newLabel;
    });
  }

  void _snapToLandmark(CampusLandmark lm) {
    setState(() {
      _currentCenter = lm.position;
      _currentLabel = lm.name;
    });
    _mapController.move(lm.position, 18.0);
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
          if (mounted) showSnack(context, 'Location permission denied.', error: true);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) showSnack(context, 'Location permission permanently denied. Allow in browser settings.', error: true);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );

      final userPos = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _deviceGpsPos = userPos;
        _currentCenter = userPos;
        _currentLabel = '📍 My Live GPS Location';
      });

      _mapController.move(userPos, 18.0);
      showSnack(context, '📍 Live GPS coordinates locked!');
    } catch (e) {
      if (mounted) showSnack(context, 'GPS Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  int _calculateDistanceMeters(LatLng p1, LatLng p2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, p1, p2).round();
  }

  void _confirm() {
    final hint = _hintController.text.trim();
    Navigator.pop(
      context,
      (
        position: _currentCenter,
        label: _currentLabel,
        hint: hint.isEmpty ? null : hint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dist = _calculateDistanceMeters(widget.terminalPosition, _currentCenter);
    final walkMins = (dist / 80).ceil(); // ~80m per min walking

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
          elevation: 2,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Pin Your Pickup Location',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
          ),
          actions: [
            // Satellite Toggle
            IconButton(
              tooltip: _isSatellite ? 'Switch to Street Map' : 'Switch to Satellite View',
              icon: Icon(
                _isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
                color: _isSatellite ? const Color(0xFF38BDF8) : Colors.white,
              ),
              onPressed: () => setState(() => _isSatellite = !_isSatellite),
            ),
            // GPS Locate
            IconButton(
              tooltip: 'Locate My Real GPS Position',
              icon: _isLocating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                  : const Icon(Icons.my_location_rounded, color: Color(0xFF38BDF8)),
              onPressed: _isLocating ? null : _locateUser,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            // Interactive Map
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentCenter,
                initialZoom: 18.0,
                minZoom: 15.0,
                maxZoom: 19.0,
                onPositionChanged: _onPositionChanged,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _isSatellite
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ph.edu.lu.lutrike',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    // Terminal Bay Station
                    Marker(
                      point: widget.terminalPosition,
                      width: 100,
                      height: 50,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                            ),
                            child: Text(
                              widget.terminalName.replaceAll('Laguna University ', '').replaceAll(' Terminal', ''),
                              style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.local_parking_rounded, color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                    // Blue GPS Marker
                    if (_deviceGpsPos != null)
                      Marker(
                        point: _deviceGpsPos!,
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

            // Fixed Center Crosshair Pin (Uber/Grab Style)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 38), // align pin tip to map center
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Text(
                        _currentLabel,
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Icon(
                      Icons.location_on_rounded,
                      size: 42,
                      color: Color(0xFF2563EB),
                      shadows: [
                        Shadow(color: Colors.white, blurRadius: 4),
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Top Landmark Quick-Snap Chips
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
                        onTap: () => _snapToLandmark(lm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(lm.icon, size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                lm.shortLabel,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
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

            // Bottom Action Confirmation Card
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, -3)),
                  ],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFF0284C7),
                          radius: 18,
                          child: Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentLabel,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$dist meters from ${widget.terminalName} • Walking ~${walkMins}m',
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Landmark Hint Field
                    TextField(
                      controller: _hintController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.35),
                        hintText: 'Landmark hint for Kuya Driver (e.g. Near grandstand entrance)',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5),
                        prefixIcon: const Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                      onPressed: _confirm,
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'Set as My Exact Pickup Spot',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
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
