import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeofenceEditorScreen extends StatefulWidget {
  const GeofenceEditorScreen({super.key});

  @override
  State<GeofenceEditorScreen> createState() => _GeofenceEditorScreenState();
}

class _GeofenceEditorScreenState extends State<GeofenceEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController();

  bool _isLoading = false;
  String? _clockNo;

  @override
  void initState() {
    super.initState();
    _loadCurrentGeofence();
  }

  Future<void> _loadCurrentGeofence() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    _clockNo = prefs.getString('loggedInClockNo');

    final doc = await FirebaseFirestore.instance
        .collection('settings')
        .doc('geofence')
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      _latController.text = (data['latitude'] ?? -29.923493321252604).toString();
      _lngController.text = (data['longitude'] ?? 31.003267644258845).toString();
      _radiusController.text = (data['radius'] ?? 500).toString();
    } else {
      // Default values
      _latController.text = '-29.923493321252604';
      _lngController.text = '31.003267644258845';
      _radiusController.text = '500';
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveGeofence() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final lat = double.parse(_latController.text);
      final lng = double.parse(_lngController.text);
      final radius = double.parse(_radiusController.text);

      await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence')
          .set({
        'latitude': lat,
        'longitude': lng,
        'radius': radius,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _clockNo,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Geofence updated successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Geofence')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _latController,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        if (double.tryParse(value) == null) return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _lngController,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        if (double.tryParse(value) == null) return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _radiusController,
                      decoration: const InputDecoration(
                        labelText: 'Radius (meters)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        final radius = double.tryParse(value);
                        if (radius == null || radius <= 0) return 'Must be greater than 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _saveGeofence,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Geofence'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This location will be used for all employee geofence checks.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }
}