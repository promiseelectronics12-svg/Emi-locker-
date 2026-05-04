import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

class LocationFetchScreen extends StatefulWidget {
  final String deviceId;

  const LocationFetchScreen({super.key, required this.deviceId});

  @override
  State<LocationFetchScreen> createState() => _LocationFetchScreenState();
}

class _LocationFetchScreenState extends State<LocationFetchScreen> {
  bool _isFetching = false;
  Map<String, double>? _location;
  String? _error;

  Future<void> _fetchLocation() async {
    setState(() {
      _isFetching = true;
      _error = null;
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isFetching = false;
      _location = {
        'latitude': 23.8103 + (DateTime.now().millisecond / 1000),
        'longitude': 90.4125 + (DateTime.now().millisecond / 1000),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Location'),
        backgroundColor: AppTheme.dealerColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Device',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${widget.deviceId.substring(0, 8)}...',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: _location != null
                    ? _buildLocationView()
                    : _buildPlaceholder(),
              ),
            ),
            if (_error != null) ...[
              Card(
                color: AppTheme.errorColor.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.errorColor),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isFetching ? null : _fetchLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dealerColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _isFetching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.location_searching),
              label: Text(_isFetching ? 'Fetching...' : 'Get Current Location'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No location data',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Get Current Location" to fetch\ndevice location',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationView() {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.map,
                    size: 64,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Map View',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text('Latitude: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_location!['latitude']!.toStringAsFixed(6)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text('Longitude: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_location!['longitude']!.toStringAsFixed(6)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('Updated: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(DateTime.now().toString().substring(0, 19)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}