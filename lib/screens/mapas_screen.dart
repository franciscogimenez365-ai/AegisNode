import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;


class MapasScreen extends StatefulWidget {
  final String rutaMapas;
  final LatLng? coordenadaDestino;
  const MapasScreen({super.key, required this.rutaMapas, this.coordenadaDestino});

  @override
  State<MapasScreen> createState() => _MapasScreenState();
}

class _MapasScreenState extends State<MapasScreen> {
  final MapController _mapController = MapController();
  MbTilesTileProvider? _tileProvider;
  List<File> _archivosMbtiles = [];
  String? _rutaMapaActivo;
  LatLng _ubicacionActual = const LatLng(-34.7056, -58.2578);
  String _infoGps = 'GPS en espera';
  bool _gpsObtenido = false;
  bool _cargandoMapa = false;

  @override
  void initState() {
    super.initState();
    _escanearMapas();
    _obtenerGps();
  }
  @override
  void didUpdateWidget(covariant MapasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coordenadaDestino != null &&
        widget.coordenadaDestino != oldWidget.coordenadaDestino) {
      _mapController.move(widget.coordenadaDestino!, 15.0);
    }
  }

  Future<void> _escanearMapas() async {
    final dir = Directory(widget.rutaMapas);
    if (dir.existsSync()) {
      final lista = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mbtiles'))
          .toList();

      if (!mounted) return;
      setState(() {
        _archivosMbtiles = lista;
      });

      if (lista.isNotEmpty && _rutaMapaActivo == null) {
        await _cargarMbtiles(lista.first);
      }
    }
  }

  Future<void> _cargarMbtiles(File archivoExterno) async {
    if (_cargandoMapa) return;
    setState(() {
      _cargandoMapa = true;
      _rutaMapaActivo = archivoExterno.path;
    });

    try {
      // 1. Copiar a directorio interno nativo (ext4/f2fs) para evitar bloqueo FUSE
      final dirInterno = await getApplicationSupportDirectory();
      final nombreArchivo = archivoExterno.uri.pathSegments.last;
      final archivoInterno = File('${dirInterno.path}/$nombreArchivo');

      if (!await archivoInterno.exists() ||
          await archivoInterno.length() != await archivoExterno.length()) {
        await archivoExterno.copy(archivoInterno.path);
      }

      // 2. Normalizar tabla metadata y leer minzoom/center si existen
      final db = sqlite.sqlite3.open(archivoInterno.path);
      double zoomInicial = 1.0;
      LatLng centroInicial = const LatLng(0, 0);

      try {
        db.execute(
            "INSERT OR IGNORE INTO metadata (name, value) VALUES ('format', 'png');");
        db.execute(
            "INSERT OR IGNORE INTO metadata (name, value) VALUES ('name', '$nombreArchivo');");
        db.execute(
            "INSERT OR REPLACE INTO metadata (name, value) VALUES ('version', '1.3');");

        final resZoom = db.select("SELECT value FROM metadata WHERE name = 'minzoom';");
        if (resZoom.isNotEmpty) {
          zoomInicial = double.tryParse(resZoom.first['value'].toString()) ?? 1.0;
        }
        final resCenter = db.select("SELECT value FROM metadata WHERE name = 'center';");
        if (resCenter.isNotEmpty) {
          final partes = resCenter.first['value'].toString().split(',');
          if (partes.length >= 2) {
            final lon = double.tryParse(partes.first) ?? 0;
            final lat = double.tryParse(partes.elementAt(1)) ?? 0;
            centroInicial = LatLng(lat, lon);
            if (partes.length >= 3) {
              zoomInicial = double.tryParse(partes.elementAt(2)) ?? zoomInicial;
            }
          }
        }
      } finally {
        db.close();
      }

      _tileProvider?.dispose();
      final provider = MbTilesTileProvider.fromPath(path: archivoInterno.path);

      if (!mounted) return;
      setState(() {
        _tileProvider = provider;
        _cargandoMapa = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(centroInicial, zoomInicial);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoMapa = false;
        _infoGps = 'Error abriendo mapa: $e';
      });
    }
  }


  Future<void> _obtenerGps() async {
    if (!mounted) return;
    setState(() => _infoGps = 'Buscando satélites...');
    try {
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (!mounted) return;

      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        setState(() => _infoGps = 'Permiso GPS denegado');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      final nuevaPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _ubicacionActual = nuevaPos;
        _gpsObtenido = true;
        _infoGps =
            'LAT: ${pos.latitude.toStringAsFixed(5)} | LON: ${pos.longitude.toStringAsFixed(5)} | ALT: ${pos.altitude.toStringAsFixed(0)}m';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _infoGps = 'Error GPS: $e');
    }
  }
  @override
  void dispose() {
    _tileProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF121212),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.satellite_alt,
                size: 18,
                color: _gpsObtenido ? const Color(0xFF00E676) : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _infoGps,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.my_location, size: 20),
                tooltip: 'Centrar GPS',
                onPressed: () async {
                  await _obtenerGps();
                  if (_tileProvider != null && _gpsObtenido) {
                    _mapController.move(_ubicacionActual, 6.0);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Recargar mapas',
                onPressed: _escanearMapas,
              ),
            ],
          ),
        ),
        if (_archivosMbtiles.length > 1)
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButton<String>(
              value: _rutaMapaActivo,
              isExpanded: true,
              dropdownColor: const Color(0xFF121212),
              items: _archivosMbtiles.map((f) {
                return DropdownMenuItem<String>(
                  value: f.path,
                  child: Text(f.uri.pathSegments.last),
                );
              }).toList(),
              onChanged: (path) {
                if (path != null) {
                  final elegido =
                      _archivosMbtiles.firstWhere((f) => f.path == path);
                  _cargarMbtiles(elegido);
                }
              },
            ),
          ),
        Expanded(
          child: _cargandoMapa
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6D00)),
                )
              : _tileProvider == null
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.map_outlined,
                              size: 64, color: Color(0xFFFF6D00)),
                          const SizedBox(height: 16),
                          const Text(
                            'Sin mapas offline cargados',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Descarga mapas en la pestaña Preparar o copia archivos .mbtiles en:\n${widget.rutaMapas}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : FlutterMap(
                      mapController: _mapController,
                      options: const MapOptions(
                        initialCenter: LatLng(0, 0),
                        initialZoom: 2.0,
                        minZoom: 0.0,
                        maxZoom: 18.0,
                        backgroundColor: Color(0xFF000000),
                      ),
                      children: [
                        TileLayer(
                          tileProvider: _tileProvider!,
                        ),
                        if (_gpsObtenido)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _ubicacionActual,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.navigation,
                                  color: Color(0xFFFF6D00),
                                  size: 32,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}
