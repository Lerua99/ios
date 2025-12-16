import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';
import 'shelly_wizard_screen.dart';
import 'esp32_wizard_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';

class TechnicianAddClientScreen extends StatefulWidget {
  const TechnicianAddClientScreen({Key? key}) : super(key: key);

  @override
  State<TechnicianAddClientScreen> createState() => _TechnicianAddClientScreenState();
}

class _TechnicianAddClientScreenState extends State<TechnicianAddClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailConfirmController = TextEditingController(); // NOU: pentru confirmare email
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _cuiController = TextEditingController();
  final _regComController = TextEditingController();

  String _deviceType = 'shelly';
  String _clientType = 'persoana_fizica';
  bool _isSubmitting = false;
  
  // Verificare potrivire email-uri
  bool get _emailsMatch => 
    _emailController.text.isNotEmpty && 
    _emailController.text == _emailConfirmController.text;
  
  // Dropdown-uri pentru județ și oraș
  List<Map<String, dynamic>> _counties = [];
  List<String> _localities = [];
  String? _selectedCounty;
  String? _selectedCity;
  bool _isLoadingCounties = true;
  bool _isLoadingLocalities = false;
  
  // Marca automatizării
  String? _marcaAutomatizare;
  
  // Google Maps
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};
  Timer? _debounceTimer;
  bool _mapError = false; // Flag pentru eroare Maps

  @override
  void initState() {
    super.initState();
    _loadCounties();
    _requestLocationPermission();
  }
  
  // Cere permisiuni de locație
  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permisiunea de locație este necesară pentru hartă'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _emailConfirmController.dispose(); // NOU
    _phoneController.dispose();
    _addressController.dispose();
    _deviceNameController.dispose();
    _companyNameController.dispose();
    _cuiController.dispose();
    _regComController.dispose();
    _debounceTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCounties() async {
    try {
      final counties = await ApiService.getCounties();
      setState(() {
        _counties = counties;
        _isLoadingCounties = false;
      });
    } catch (e) {
      setState(() => _isLoadingCounties = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la încărcarea județelor: $e')),
        );
      }
    }
  }

  Future<void> _loadLocalities(String countyCode) async {
    setState(() {
      _isLoadingLocalities = true;
      _selectedCity = null;
      _localities = [];
    });
    
    try {
      final localities = await ApiService.getLocalities(countyCode);
      setState(() {
        _localities = localities;
        _isLoadingLocalities = false;
      });
    } catch (e) {
      setState(() => _isLoadingLocalities = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la încărcarea orașelor: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Verificare potrivire email-uri
    if (!_emailsMatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cele două adrese de email nu se potrivesc!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (_selectedCounty == null || _selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selectează județul și orașul')),
      );
      return;
    }
    
    if (_marcaAutomatizare == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selectează marca automatizării')),
      );
      return;
    }
    
    setState(() => _isSubmitting = true);
    try {
      final payload = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'client_type': _clientType,
        if (_clientType == 'persoana_juridica') 'company_name': _companyNameController.text.trim(),
        if (_clientType == 'persoana_juridica') 'cui': _cuiController.text.trim(),
        if (_clientType == 'persoana_juridica') 'reg_com': _regComController.text.trim(),
        'installation_city': _selectedCity!,
        'installation_county': _selectedCounty!,
        'device_type': _deviceType,
        if (_marcaAutomatizare != null) 'marca_automatizare': _marcaAutomatizare!,
        // Nu mai trimitem device_id; backend generează cod HOPA automat pentru Shelly
        if (_deviceNameController.text.trim().isNotEmpty) 'device_name': _deviceNameController.text.trim(),
        // Coordonate GPS din hartă
        if (_selectedLocation != null) 'latitude': _selectedLocation!.latitude,
        if (_selectedLocation != null) 'longitude': _selectedLocation!.longitude,
      };

      final resp = await ApiService.addInstallerClient(payload);
      if (!mounted) return;
      
      // Verificare eroare email duplicat
      if (resp['success'] == false && resp['message'] != null && 
          resp['message'].toString().toLowerCase().contains('email')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Aceasta adresa de email a mai fost inregistrata. Va rugam sa contactati servicul Hopa la email office@hopa.ro sau 0735232223',
              style: TextStyle(fontSize: 13),
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 8),
          ),
        );
        return;
      }
      
      final clientId = resp['data']?['client_id'] ?? 0;
      final hopaCode = resp['data']?['hopa_device_code'] ?? '';
      
      // Închide formularul IMEDIAT după salvare (înainte de wizard)
      Navigator.of(context).pop({'success': true, 'data': resp});
      
      // Pornește wizard-ul DUPĂ ce te-ai întors în listă (separat, fără a bloca salvarea)
      if (!mounted) return;
      
      if (_deviceType == 'shelly') {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ShellyWizardScreen(
            clientId: clientId is int ? clientId : null,
            hopaDeviceCode: hopaCode is String ? hopaCode : null,
            onComplete: (shellyId) {
              // Wizard finalizat, dispozitivul e configurat
            },
          ),
        ));
      } else if (_deviceType == 'esp32') {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Esp32WizardScreen(clientId: clientId is int ? clientId : 0),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adaugă Client Nou'),
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            children: [
          _buildClientType(),
          if (_clientType == 'persoana_juridica') ...[
            _buildText('Nume companie *', _companyNameController, validator: (v) => v == null || v.trim().isEmpty ? 'Obligatoriu' : null),
            Row(children: [
              Expanded(child: _buildText('CUI', _cuiController)),
              const SizedBox(width: 12),
              Expanded(child: _buildText('Reg. Com.', _regComController)),
            ]),
            const SizedBox(height: 8),
          ],
              _buildText('Nume client *', _nameController, validator: (v) => v == null || v.trim().isEmpty ? 'Obligatoriu' : null),
              _buildText('Email *', _emailController, keyboard: TextInputType.emailAddress, validator: (v) => v == null || !v.contains('@') ? 'Email invalid' : null),
              
              // CÂMP NOU: Confirmare Email cu validare vizuală
              _buildEmailConfirmField(),
              
              _buildText('Telefon *', _phoneController, keyboard: TextInputType.phone, validator: (v) => v == null || v.trim().isEmpty ? 'Obligatoriu' : null),
              
              // ORDINE CORECTĂ: Județ → Oraș → Adresă
              _buildCountyDropdown(),
              const SizedBox(height: 12),
              _buildCityDropdown(),
              const SizedBox(height: 12),
              
              _buildText(
                'Adresă instalare *', 
                _addressController, 
                validator: (v) => v == null || v.trim().isEmpty ? 'Obligatoriu' : null,
                onChanged: (value) {
                  // Debounce pentru geocoding automat
                  _debounceTimer?.cancel();
                  _debounceTimer = Timer(const Duration(seconds: 2), () {
                    _updateMapFromAddress();
                  });
                },
              ),
              
              // HARTĂ GOOGLE MAPS (după adresă)
              const SizedBox(height: 12),
              _buildGoogleMap(),
              const SizedBox(height: 12),
              
              // Marca automatizării
              _buildMarcaAutomatizareDropdown(),
              const SizedBox(height: 8),
              
              _buildText('Nume dispozitiv (opțional)', _deviceNameController),
              const SizedBox(height: 8),
              _buildDeviceType(),
              // Nu mai solicităm Shelly Device ID
              const SizedBox(height: 20),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_isSubmitting ? 'Salvez...' : 'Salvează clientul'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563eb),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText(String label, TextEditingController c, {String? Function(String?)? validator, TextInputType keyboard = TextInputType.text, Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF111827),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white54),
        ),
        style: const TextStyle(color: Colors.white),
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }
  
  // CÂMP NOU: Confirmare Email cu validare vizuală
  Widget _buildEmailConfirmField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _emailConfirmController.text.isEmpty 
              ? Colors.grey[700]! 
              : (_emailsMatch ? Colors.green : Colors.red),
            width: 2,
          ),
        ),
        child: TextFormField(
          controller: _emailConfirmController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Confirmă Email *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: const Color(0xFF111827),
            labelStyle: const TextStyle(color: Colors.white70),
            hintStyle: const TextStyle(color: Colors.white54),
            suffixIcon: _emailConfirmController.text.isNotEmpty
              ? Icon(
                  _emailsMatch ? Icons.check_circle : Icons.error,
                  color: _emailsMatch ? Colors.green : Colors.red,
                )
              : null,
          ),
          style: const TextStyle(color: Colors.white),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Obligatoriu';
            if (!v.contains('@')) return 'Email invalid';
            if (v != _emailController.text) return 'Email-urile nu se potrivesc';
            return null;
          },
          onChanged: (value) {
            setState(() {}); // Refresh pentru a actualiza culoarea border-ului
          },
        ),
      ),
    );
  }

  Widget _buildDeviceType() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tip dispozitiv', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          RadioListTile<String>(
            value: 'shelly',
            groupValue: _deviceType,
            onChanged: (v) => setState(() => _deviceType = v!),
            title: const Text('Shelly', style: TextStyle(color: Colors.white)),
            dense: true,
            activeColor: Colors.white,
            tileColor: const Color(0xFF0f172a),
          ),
          RadioListTile<String>(
            value: 'esp32',
            groupValue: _deviceType,
            onChanged: (v) => setState(() => _deviceType = v!),
            title: const Text('ESP32 (manual)', style: TextStyle(color: Colors.white)),
            dense: true,
            activeColor: Colors.white,
            tileColor: const Color(0xFF0f172a),
          ),
        ],
      ),
    );
  }

  Widget _buildClientType() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tip client', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          RadioListTile<String>(
            value: 'persoana_fizica',
            groupValue: _clientType,
            onChanged: (v) => setState(() => _clientType = v!),
            title: const Text('Persoană fizică', style: TextStyle(color: Colors.white)),
            dense: true,
            activeColor: Colors.white,
            tileColor: const Color(0xFF0f172a),
          ),
          RadioListTile<String>(
            value: 'persoana_juridica',
            groupValue: _clientType,
            onChanged: (v) => setState(() => _clientType = v!),
            title: const Text('Persoană juridică (firmă)', style: TextStyle(color: Colors.white)),
            dense: true,
            activeColor: Colors.white,
            tileColor: const Color(0xFF0f172a),
          ),
        ],
      ),
    );
  }

  Widget _buildCountyDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: _isLoadingCounties
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : DropdownButtonFormField<String>(
              value: _selectedCounty,
              decoration: const InputDecoration(
                labelText: 'Județ *',
                border: InputBorder.none,
                labelStyle: TextStyle(color: Colors.white70),
              ),
              dropdownColor: const Color(0xFF111827),
              style: const TextStyle(color: Colors.white),
              items: _counties.map((county) {
                return DropdownMenuItem<String>(
                  value: county['code'],
                  child: Text(county['name']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCounty = value;
                  _selectedCity = null;
                });
                if (value != null) {
                  _loadLocalities(value);
                }
              },
              validator: (value) => value == null ? 'Selectează județul' : null,
            ),
    );
  }

  Widget _buildCityDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: _isLoadingLocalities
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : DropdownButtonFormField<String>(
              value: _selectedCity,
              decoration: const InputDecoration(
                labelText: 'Localitate *',
                border: InputBorder.none,
                labelStyle: TextStyle(color: Colors.white70),
              ),
              dropdownColor: const Color(0xFF111827),
              style: const TextStyle(color: Colors.white),
              items: _localities.map((city) {
                return DropdownMenuItem<String>(
                  value: city,
                  child: Text(city),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedCity = value);
              },
              validator: (value) => value == null ? 'Selectează orașul' : null,
            ),
    );
  }

  Widget _buildMarcaAutomatizareDropdown() {
    // Lista completă sincronizată cu backend (X:/config/brands.php)
    final marci = [
      'BFT', 'CAME', 'FAAC', 'Nice', 'Beninca', 'Sommer', 'Hörmann', 
      'Marantec', 'Motorline', 'Roger Technology', 'Ditec', 'Gibidi', 
      'Key Automation', 'Life', 'Proteco', 'Quiko', 'RIB', 'TAU', 
      'Telcoma', 'V2', 'Altele'
    ];
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: DropdownButtonFormField<String>(
        value: _marcaAutomatizare,
        decoration: const InputDecoration(
          labelText: 'Marca Automatizării *',
          border: InputBorder.none,
          labelStyle: TextStyle(color: Colors.white70),
        ),
        dropdownColor: const Color(0xFF111827),
        style: const TextStyle(color: Colors.white),
        items: marci.map((marca) {
          return DropdownMenuItem<String>(
            value: marca,
            child: Text(marca),
          );
        }).toList(),
        onChanged: (value) {
          setState(() => _marcaAutomatizare = value);
        },
        validator: (value) => value == null ? 'Selectează marca' : null,
      ),
    );
  }
  
  // Widget Google Maps
  Widget _buildGoogleMap() {
    // Dacă Maps a dat eroare, afișează placeholder
    if (_mapError) {
      return Column(
        children: [
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[700]!, width: 2),
              color: const Color(0xFF111827),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_outlined, size: 60, color: Colors.grey[600]),
                  const SizedBox(height: 12),
                  Text(
                    'Hartă indisponibilă',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configurează Google Maps API Key',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '⚠️ Pentru hartă, configurează API Key în AndroidManifest.xml',
            style: TextStyle(fontSize: 11, color: Colors.orange[400]),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[700]!, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(45.9432, 24.9668), // Centru România
                zoom: 7,
              ),
              markers: _markers,
              onMapCreated: (controller) {
                try {
                  _mapController = controller;
                } catch (e) {
                  print('❌ Maps initialization error: $e');
                  if (mounted) {
                    setState(() => _mapError = true);
                  }
                }
              },
              onTap: (position) async {
                // Permite și selectare manuală pe hartă
                setState(() {
                  _selectedLocation = position;
                  _markers = {
                    Marker(
                      markerId: const MarkerId('client_location'),
                      position: position,
                      infoWindow: const InfoWindow(title: 'Locație Instalare'),
                    ),
                  };
                });
                
                // Geocoding invers: coordonate → adresă
                try {
                  final placemarks = await placemarkFromCoordinates(
                    position.latitude,
                    position.longitude,
                  );
                  if (placemarks.isNotEmpty) {
                    final place = placemarks.first;
                    final address = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.country ?? ''}'.trim();
                    if (address.isNotEmpty) {
                      _addressController.text = address;
                    }
                  }
                } catch (e) {
                  print('Geocoding invers error: $e');
                }
              },
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapType: MapType.normal,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '📍 Apasă pe hartă pentru a selecta locația sau introdu adresa mai sus',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  // Geocoding: Adresă → Coordonate
  Future<void> _updateMapFromAddress() async {
    final fullAddress = '${_addressController.text.trim()}, ${_selectedCity ?? ''}, ${_selectedCounty ?? ''}, România';
    
    if (_addressController.text.trim().isEmpty) return;
    
    try {
      final locations = await locationFromAddress(fullAddress);
      if (locations.isNotEmpty) {
        final location = locations.first;
        final newPosition = LatLng(location.latitude, location.longitude);
        
        setState(() {
          _selectedLocation = newPosition;
          _markers = {
            Marker(
              markerId: const MarkerId('client_location'),
              position: newPosition,
              infoWindow: InfoWindow(
                title: 'Locație Instalare',
                snippet: _addressController.text.trim(),
              ),
            ),
          };
        });
        
        // Animare cameră la locația găsită
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(newPosition, 15),
        );
        
        print('✅ Geocoding success: $fullAddress → $newPosition');
      }
    } catch (e) {
      print('⚠️ Geocoding error: $e');
      // Nu afișăm eroare utilizatorului - geocoding-ul e opțional
    }
  }
}


