import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GeofenceEditorScreen extends StatefulWidget {
  const GeofenceEditorScreen({super.key});

  @override
  State<GeofenceEditorScreen> createState() => _GeofenceEditorScreenState();
}

class _GeofenceEditorScreenState extends State<GeofenceEditorScreen> {
  GoogleMapController? _mapController;
  LatLng _center = const LatLng(-29.929164495077, 31.011167505895127);
  double _radius = 100.0;
  bool _isLoading = true;
  bool _isSaving = false;

  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentGeofence();
  }

  Future<void> _loadCurrentGeofence() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _center = LatLng(
            data['latitude']?.toDouble() ?? _center.latitude,
            data['longitude']?.toDouble() ?? _center.longitude,
          );
          _radius = data['radius']?.toDouble() ?? 100.0;
        });
      }
    } catch (e) {
      debugPrint('Error loading geofence: $e');
    } finally {
      _updateMapElements();
      setState(() => _isLoading = false);
    }
  }

  void _updateMapElements() {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('geofence_center'),
          position: _center,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() {
              _center = newPosition;
            });
            _updateMapElements();
          },
        ),
      };

      _circles = {
        Circle(
          circleId: const CircleId('geofence_radius'),
          center: _center,
          radius: _radius,
          fillColor: Colors.blue.withOpacity(0.2),
          strokeColor: Colors.blue,
          strokeWidth: 2,
        ),
      };
    });
  }

  Future<void> _saveGeofence() async {
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence')
          .set({
        'latitude': _center.latitude,
        'longitude': _center.longitude,
        'radius': _radius,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Geofence updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving geofence: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Geofence'),
        backgroundColor: const Color(0xFFFF8C42),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: 16,
              ),
              markers: _markers,
              circles: _circles,
              onMapCreated: (controller) {
                _mapController = controller;
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Coordinates
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Lat: ${_center.latitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'Lng: ${_center.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Radius Slider
                Row(
                  children: [
                    const Text('Radius: '),
                    Expanded(
                      child: Slider(
                        value: _radius,
                        min: 10,
                        max: 1000,
                        divisions: 99,
                        label: '${_radius.round()} m',
                        onChanged: (value) {
                          setState(() {
                            _radius = value;
                          });
                          _updateMapElements();
                        },
                      ),
                    ),
                    Text('${_radius.round()} m'),
                  ],
                ),
                const SizedBox(height: 16),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveGeofence,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C42),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Save Geofence Changes',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}