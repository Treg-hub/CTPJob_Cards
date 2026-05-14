import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeofenceEditorScreen extends StatefulWidget {
  const GeofenceEditorScreen({super.key});

  @override
  State<GeofenceEditorScreen> createState() => _GeofenceEditorScreenState();
}

class _GeofenceEditorScreenState extends State<GeofenceEditorScreen> {
  static const LatLng _defaultCentre = LatLng(-29.923493321252604, 31.003267644258845);
  static const double _defaultRadius = 500;
  static const double _minRadius = 50;
  static const double _maxRadius = 5000;

  final MapController _mapController = MapController();
  StreamSubscription<MapEvent>? _mapEventSub;
  LatLng _centre = _defaultCentre;
  double _radius = _defaultRadius;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _clockNo;
  bool _showAdvanced = false;

  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentGeofence();
    _mapEventSub = _mapController.mapEventStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadCurrentGeofence() async {
    final prefs = await SharedPreferences.getInstance();
    _clockNo = prefs.getString('loggedInClockNo');

    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('geofence')
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      _centre = LatLng(
        (data['latitude'] as num?)?.toDouble() ?? _defaultCentre.latitude,
        (data['longitude'] as num?)?.toDouble() ?? _defaultCentre.longitude,
      );
      _radius = (data['radius'] as num?)?.toDouble() ?? _defaultRadius;
    }

    _syncTextControllers();
    if (mounted) setState(() => _isLoading = false);
  }

  void _syncTextControllers() {
    _latController.text = _centre.latitude.toStringAsFixed(6);
    _lngController.text = _centre.longitude.toStringAsFixed(6);
    _radiusController.text = _radius.toStringAsFixed(0);
  }

  Future<void> _saveGeofence() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('geofence').set({
        'latitude': _centre.latitude,
        'longitude': _centre.longitude,
        'radius': _radius,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _clockNo,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geofence updated'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (result == LocationPermission.denied || result == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission required')),
            );
          }
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _centre = LatLng(pos.latitude, pos.longitude);
        _syncTextControllers();
      });
      _mapController.move(_centre, _mapController.camera.zoom);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  Offset _latLngToOffset(MapCamera camera, LatLng latLng) {
    final p = camera.latLngToScreenPoint(latLng);
    return Offset(p.x, p.y);
  }

  LatLng _offsetToLatLng(MapCamera camera, Offset offset) {
    return camera.pointToLatLng(math.Point<double>(offset.dx, offset.dy));
  }

  void _onCentreDrag(DragUpdateDetails details, Size mapSize) {
    final camera = _mapController.camera;
    final centrePoint = _latLngToOffset(camera, _centre);
    final newScreenPoint = Offset(
      centrePoint.dx + details.delta.dx,
      centrePoint.dy + details.delta.dy,
    );
    final newLatLng = _offsetToLatLng(camera, newScreenPoint);
    setState(() {
      _centre = newLatLng;
      _syncTextControllers();
    });
  }

  void _onEdgeDrag(DragUpdateDetails details) {
    final camera = _mapController.camera;
    final centrePoint = _latLngToOffset(camera, _centre);
    final edgeScreen = Offset(
      centrePoint.dx + _radiusPixels(camera) + details.delta.dx,
      centrePoint.dy,
    );
    final edgeLatLng = _offsetToLatLng(camera, edgeScreen);
    final newRadius = const Distance().as(LengthUnit.Meter, _centre, edgeLatLng);
    setState(() {
      _radius = newRadius.clamp(_minRadius, _maxRadius);
      _syncTextControllers();
    });
  }

  double _radiusPixels(MapCamera camera) {
    final centrePx = _latLngToOffset(camera, _centre);
    final edgeLatLng = const Distance().offset(_centre, _radius, 90);
    final edgePx = _latLngToOffset(camera, edgeLatLng);
    return (edgePx - centrePx).distance;
  }

  void _applyManualInput() {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);
    final rad = double.tryParse(_radiusController.text);
    if (lat == null || lng == null || rad == null || rad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid values'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _centre = LatLng(lat, lng);
      _radius = rad.clamp(_minRadius, _maxRadius);
    });
    _mapController.move(_centre, _mapController.camera.zoom);
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
    _mapController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Geofence')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Geofence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Use my current location',
            onPressed: _useCurrentLocation,
          ),
          IconButton(
            icon: Icon(_showAdvanced ? Icons.tune : Icons.tune_outlined),
            tooltip: 'Manual entry',
            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMap()),
          if (_showAdvanced) _buildManualInputs(),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _centre,
                initialZoom: 16,
                minZoom: 4,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ctp.jobcards',
                  maxNativeZoom: 19,
                ),
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _centre,
                      radius: _radius,
                      useRadiusInMeter: true,
                      color: const Color(0xFFFF8C42).withValues(alpha: 51),
                      borderColor: const Color(0xFFFF8C42),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              ],
            ),
            // Draggable centre marker (always at the centre of the circle)
            _buildDraggableCentre(size),
            // Draggable radius edge handle (east of centre)
            _buildDraggableEdge(size),
            // Helper banner
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 230),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Drag the orange pin to move the centre. Drag the white handle on the edge to resize.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDraggableCentre(Size size) {
    final pos = _latLngToOffset(_mapController.camera, _centre);
    return Positioned(
      left: pos.dx - 18,
      top: pos.dy - 36,
      child: GestureDetector(
        onPanUpdate: (d) => _onCentreDrag(d, size),
        child: const Icon(Icons.location_pin, size: 36, color: Color(0xFFFF8C42)),
      ),
    );
  }

  Widget _buildDraggableEdge(Size size) {
    final camera = _mapController.camera;
    final centrePx = _latLngToOffset(camera, _centre);
    final radiusPx = _radiusPixels(camera);
    final edge = Offset(centrePx.dx + radiusPx, centrePx.dy);
    return Positioned(
      left: edge.dx - 14,
      top: edge.dy - 14,
      child: GestureDetector(
        onPanUpdate: _onEdgeDrag,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFF8C42), width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: const Icon(Icons.open_with, size: 16, color: Color(0xFFFF8C42)),
        ),
      ),
    );
  }

  Widget _buildManualInputs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  decoration: const InputDecoration(labelText: 'Latitude', isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lngController,
                  decoration: const InputDecoration(labelText: 'Longitude', isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _radiusController,
                  decoration: const InputDecoration(labelText: 'Radius (m)', isDense: true),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _applyManualInput,
                icon: const Icon(Icons.check),
                label: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 30), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.radio_button_unchecked, size: 18, color: Color(0xFFFF8C42)),
              const SizedBox(width: 8),
              Text('Radius: ${_radius.toStringAsFixed(0)} m',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Centre: ${_centre.latitude.toStringAsFixed(4)}, ${_centre.longitude.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          Slider(
            value: _radius.clamp(_minRadius, _maxRadius),
            min: _minRadius,
            max: _maxRadius,
            divisions: 99,
            label: '${_radius.toStringAsFixed(0)} m',
            onChanged: (v) => setState(() {
              _radius = v;
              _syncTextControllers();
            }),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveGeofence,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Geofence'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8C42),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

