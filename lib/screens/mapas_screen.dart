import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:file_picker/file_picker.dart';
import '../services/mesh_chat_service.dart';
import '../services/nodo_config_service.dart';
import '../services/waypoints_service.dart';
import '../services/enrutador_offline_service.dart';
import '../services/idioma_service.dart';


class RastroGpxInfo {
  final File archivo;
  String nombre;
  final List<LatLng> puntos;
  bool visible;

  RastroGpxInfo({
    required this.archivo,
    required this.nombre,
    required this.puntos,
    this.visible = false,
  });
}
class MetaMapaMbtiles {
  final File archivo;
  final int minZoom;
  final int maxZoom;
  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  MetaMapaMbtiles({
    required this.archivo,
    required this.minZoom,
    required this.maxZoom,
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  bool contiene(LatLng p) {
    return p.longitude >= minLon &&
        p.longitude <= maxLon &&
        p.latitude >= minLat &&
        p.latitude <= maxLat;
  }
}

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
  List<MetaMapaMbtiles> _metasMapas = [];
  double _maxZoomPermitido = 16.0;
  int _maxNativeZoomActivo = 15;
  final bool _autoCambioHabilitado = true;
  String? _rutaMapaActivo;
  LatLng _ubicacionActual = const LatLng(0.0, 0.0);
  String _infoGps = IdiomaService.t('gps_espera');
  bool _gpsObtenido = false;
  bool _cargandoMapa = false;
  List<WaypointTactico> _waypoints = [];
  WaypointTactico? _destinoGuiado;
  ResultadoRuta? _rutaActiva;
  bool _grabandoRastro = false;
  final List<LatLng> _puntosRastro = [];
  List<RastroGpxInfo> _rastrosGuardados = [];
  StreamSubscription<Position>? _rastroSub;
  double _rumboBrujulaGrados = 0.0;
  static const MethodChannel _brujulaChannel =
  MethodChannel('com.emergencia.aegis_node/brujula');



  @override
  void initState() {
    super.initState();
    _escanearMapas();
    _obtenerGps();
    _cargarWaypoints();
    _cargarRastrosGpx();
  }
    Future<void> _cargarWaypoints() async {
    final lista = await WaypointsService.cargar(widget.rutaMapas);
    if (mounted) setState(() => _waypoints = lista);
    _brujulaChannel.setMethodCallHandler((call) async {
      if (call.method == 'onBrujulaActualizada' && mounted) {
        final grados = (call.arguments as num?)?.toDouble() ?? 0.0;
        setState(() => _rumboBrujulaGrados = grados);
      }
    });
    _brujulaChannel.invokeMethod('iniciarBrujula');
  }

  @override
  void didUpdateWidget(covariant MapasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coordenadaDestino != null &&
        widget.coordenadaDestino != oldWidget.coordenadaDestino) {
      _mapController.move(widget.coordenadaDestino!, 15.0);
      _iniciarGuiadoHacia(WaypointTactico(
        id: 'chat_dest',
        nombre: 'Coordenada Malla',
        tipo: 'auxilio',
        lat: widget.coordenadaDestino!.latitude,
        lon: widget.coordenadaDestino!.longitude,
      ));
    }
  }


  Future<void> _escanearMapas() async {
    final dir = Directory(widget.rutaMapas);
    if (!dir.existsSync()) return;

    final lista = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.mbtiles'))
        .toList();

    if (!mounted) return;

    if (lista.isEmpty) {
      setState(() {
        _archivosMbtiles = [];
        _metasMapas = [];
        _rutaMapaActivo = null;
        _tileProvider = null;
      });
      return;
    }

    final dirInterno = await getApplicationSupportDirectory();
    final nuevasMetas = <MetaMapaMbtiles>[];
    for (final f in lista) {
      final nombre = f.uri.pathSegments.last;
      final interno = File('${dirInterno.path}/$nombre');
      if (!await interno.exists() ||
          await interno.length() != await f.length()) {
        await f.copy(interno.path);
      }
      nuevasMetas.add(_leerMetadatosMbtiles(interno, f));
    }

    final rutaValida = _rutaMapaActivo != null &&
        lista.any((f) => f.path == _rutaMapaActivo);

    setState(() {
      _archivosMbtiles = lista;
      _metasMapas = nuevasMetas;
      if (!rutaValida) {
        _rutaMapaActivo = lista.first.path;
      }
    });

    if (!rutaValida) {
      await _cargarMbtiles(lista.first);
    }
  }

    MetaMapaMbtiles _leerMetadatosMbtiles(
      File archivoInterno, File archivoOriginal) {
    int minZ = 0;
    int maxZ = 15;
    double minLon = -180.0, minLat = -85.0, maxLon = 180.0, maxLat = 85.0;

    final db = sqlite.sqlite3.open(archivoInterno.path);
    try {
      final rMin =
          db.select("SELECT value FROM metadata WHERE name = 'minzoom';");
      if (rMin.isNotEmpty) {
        minZ = int.tryParse(rMin.first['value'].toString()) ?? 0;
      }
      final rMax =
          db.select("SELECT value FROM metadata WHERE name = 'maxzoom';");
      if (rMax.isNotEmpty) {
        maxZ = int.tryParse(rMax.first['value'].toString()) ?? 15;
      }
      final rBounds =
          db.select("SELECT value FROM metadata WHERE name = 'bounds';");
      if (rBounds.isNotEmpty) {
        final b = rBounds.first['value'].toString().split(',');
        if (b.length == 4) {
          minLon = double.tryParse(b.first.trim()) ?? -180.0;
          minLat = double.tryParse(b.elementAt(1).trim()) ?? -85.0;
          maxLon = double.tryParse(b.elementAt(2).trim()) ?? 180.0;
          maxLat = double.tryParse(b.elementAt(3).trim()) ?? 85.0;
        }
      }
    } finally {
      db.close();
    }

    return MetaMapaMbtiles(
      archivo: archivoOriginal,
      minZoom: minZ,
      maxZoom: maxZ,
      minLon: minLon,
      minLat: minLat,
      maxLon: maxLon,
      maxLat: maxLat,
    );
  }

  void _evaluarCambioAutomaticoMapa(LatLng centro, double zoom) {
    if (!_autoCambioHabilitado || _metasMapas.isEmpty || _cargandoMapa) return;

    final candidatosZona =
        _metasMapas.where((m) => m.contiene(centro)).toList();
    final listaEval = candidatosZona.isNotEmpty ? candidatosZona : _metasMapas;

    int maxZDisponible = 5;
    for (final m in listaEval) {
      if (m.maxZoom > maxZDisponible) maxZDisponible = m.maxZoom;
    }
    if ((_maxZoomPermitido - maxZDisponible.toDouble()).abs() > 0.1) {
      setState(() => _maxZoomPermitido = maxZDisponible.toDouble());
    }

    final zRedondeado = zoom.round();
    final actualMeta = _metasMapas
        .where((m) => m.archivo.path == _rutaMapaActivo)
        .firstOrNull;

    final actualSirve = actualMeta != null &&
        actualMeta.contiene(centro) &&
        zRedondeado >= actualMeta.minZoom &&
        zRedondeado <= actualMeta.maxZoom;

    if (actualSirve) return;

    final mejores = listaEval
        .where((m) => zRedondeado >= m.minZoom && zRedondeado <= m.maxZoom)
        .toList()
      ..sort(
          (a, b) => (b.maxZoom - b.minZoom).compareTo(a.maxZoom - a.minZoom));

    if (mejores.isNotEmpty && mejores.first.archivo.path != _rutaMapaActivo) {
      _cargarMbtiles(
        mejores.first.archivo,
        mantenerCamara: true,
        centroPrevio: centro,
        zoomPrevio: zoom,
      );
    }
  }

  Future<void> _importarMbtiles() async {
    final res = await FilePicker.pickFiles();
    if (res.isEmpty) return;

    final validos = res.where((f) {
      final p = f.path?.toLowerCase() ?? '';
      return p.endsWith('.mbtiles') || p.endsWith('.json') || p.endsWith('.gpx');
    }).toList();

    if (validos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
            content: Text(
                IdiomaService.t('imp_map_err'))),
      );
      return;
    }

    int indiceActual = 0;
    String nombreActual = '';
    double pctArchivo = 0.0;
    StateSetter? actualizarDialogo;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          actualizarDialogo = setDlg;
          return AlertDialog(
            backgroundColor: const Color(0xFF121212),
            title: Text(IdiomaService.t('imp_map_titulo'),
                style: TextStyle(color: Color(0xFFFF6D00), fontSize: 15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Archivo ${indiceActual + 1} de ${validos.length}:\n$nombreActual (${(pctArchivo * 100).toStringAsFixed(0)}%)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: pctArchivo.clamp(0.0, 1.0),
                  color: const Color(0xFF00E676),
                  backgroundColor: const Color(0xFF2A2A2A),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 80));

    for (int i = 0; i < validos.length; i++) {
      indiceActual = i;
      final origen = File(validos[i].path!);
      nombreActual = origen.uri.pathSegments.last;
      pctArchivo = 0.0;
      actualizarDialogo?.call(() {});

      final destino = File('${widget.rutaMapas}/$nombreActual');
      if (await destino.exists()) {
        await destino.delete();
      }

      final totalBytes = await origen.length();
      int copiadosBytes = 0;

      final sink = destino.openWrite();
      await for (final chunk in origen.openRead()) {
        sink.add(chunk);
        copiadosBytes += chunk.length;
        pctArchivo = totalBytes > 0 ? (copiadosBytes / totalBytes) : 1.0;
        actualizarDialogo?.call(() {});
      }
      await sink.close();
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      await _escanearMapas();
      await _cargarWaypoints();
      await _cargarRastrosGpx();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00E676),
          content: Text(
            '✅ ${validos.length} ${IdiomaService.t('imp_map_ok')}',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }


  Future<void> _cargarMbtiles(
    File archivoExterno, {
    bool mantenerCamara = false,
    LatLng? centroPrevio,
    double? zoomPrevio,
  }) async {
    if (_cargandoMapa) return;
    setState(() {
      _cargandoMapa = true;
      _rutaMapaActivo = archivoExterno.path;
    });

    try {
      final dirInterno = await getApplicationSupportDirectory();
      final nombreArchivo = archivoExterno.uri.pathSegments.last;
      final archivoInterno = File('${dirInterno.path}/$nombreArchivo');

      if (!await archivoInterno.exists() ||
          await archivoInterno.length() != await archivoExterno.length()) {
        await archivoExterno.copy(archivoInterno.path);
      }

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

        final resZoom =
            db.select("SELECT value FROM metadata WHERE name = 'minzoom';");
        if (resZoom.isNotEmpty) {
          zoomInicial =
              double.tryParse(resZoom.first['value'].toString()) ?? 1.0;
        }
        final resCenter =
            db.select("SELECT value FROM metadata WHERE name = 'center';");
        if (resCenter.isNotEmpty) {
          final partes = resCenter.first['value'].toString().split(',');
          if (partes.length >= 2) {
            final lon = double.tryParse(partes.first) ?? 0;
            final lat = double.tryParse(partes.elementAt(1)) ?? 0;
            centroInicial = LatLng(lat, lon);
            if (partes.length >= 3) {
              zoomInicial =
                  double.tryParse(partes.elementAt(2)) ?? zoomInicial;
            }
          }
        }
      } finally {
        db.close();
      }

      final meta = _leerMetadatosMbtiles(archivoInterno, archivoExterno);
      _tileProvider?.dispose();
      final provider = MbTilesTileProvider.fromPath(path: archivoInterno.path);

      if (!mounted) return;
      setState(() {
        _tileProvider = provider;
        _maxNativeZoomActivo = meta.maxZoom;
        if (_maxZoomPermitido < meta.maxZoom) {
          _maxZoomPermitido = meta.maxZoom.toDouble();
        }
        _cargandoMapa = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (mantenerCamara && centroPrevio != null && zoomPrevio != null) {
          _mapController.move(centroPrevio, zoomPrevio);
        } else {
          _mapController.move(centroInicial, zoomInicial);
        }
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

  Future<void> _crearWaypointEn(LatLng punto) async {
    final nombreCtrl = TextEditingController();
    String tipoSel = 'base';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: Text(IdiomaService.t('wp_nuevo_titulo'),
              style: const TextStyle(color: Color(0xFFFF6D00), fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: InputDecoration(
                  labelText: IdiomaService.t('wp_nombre_hint'),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: tipoSel,
                isExpanded: true,
                dropdownColor: const Color(0xFF1A1A1A),
                items: [
                  DropdownMenuItem(
                      value: 'base',
                      child: Text(IdiomaService.t('wp_tipo_base'))),
                  DropdownMenuItem(
                      value: 'agua',
                      child: Text(IdiomaService.t('wp_tipo_agua'))),
                  DropdownMenuItem(
                      value: 'peligro',
                      child: Text(IdiomaService.t('wp_tipo_peligro'))),
                  DropdownMenuItem(
                      value: 'auxilio',
                      child: Text(IdiomaService.t('wp_tipo_auxilio'))),
                ],
                onChanged: (v) {
                  if (v != null) setDlgState(() => tipoSel = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(IdiomaService.t('cancelar'),
                  style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black),
              onPressed: () async {
                final nombre = nombreCtrl.text.trim().isEmpty
                    ? 'WP ${punto.latitude.toStringAsFixed(3)}'
                    : nombreCtrl.text.trim();
                final nuevo = WaypointTactico(
                  id: '${DateTime.now().millisecondsSinceEpoch}',
                  nombre: nombre,
                  tipo: tipoSel,
                  lat: punto.latitude,
                  lon: punto.longitude,
                );
                _waypoints.add(nuevo);
                await WaypointsService.guardarLista(
                    widget.rutaMapas, _waypoints);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(IdiomaService.t('guardar')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _iniciarGuiadoHacia(WaypointTactico wp) async {
  setState(() {
    _destinoGuiado = wp;
    _rutaActiva = null;
  });
  await _obtenerGps();
  final ruta = await EnrutadorOfflineService.calcularRutaHibrida(
    rutaMapas: widget.rutaMapas,
    origen: _ubicacionActual,
    destino: LatLng(wp.lat, wp.lon),
  );
  if (mounted) setState(() => _rutaActiva = ruta);
  }
    Future<void> _cargarRastrosGpx() async {
    final dir = Directory(widget.rutaMapas);
    if (!dir.existsSync()) return;

    final archivos = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.gpx'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    final visiblesPrevios = {
      for (final r in _rastrosGuardados) r.archivo.path: r.visible
    };

    final nuevos = <RastroGpxInfo>[];
    final regName = RegExp(r'<name>(.*?)</name>');
    final regPt = RegExp(r'<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)"');

    for (final f in archivos) {
      try {
        final contenido = await f.readAsString();
        final matchName = regName.firstMatch(contenido);
        final nombre = matchName?.group(1)?.trim().isNotEmpty == true
            ? matchName!.group(1)!.trim()
            : f.uri.pathSegments.last;

        final pts = <LatLng>[];
        for (final m in regPt.allMatches(contenido)) {
          final lat = double.tryParse(m.group(1) ?? '');
          final lon = double.tryParse(m.group(2) ?? '');
          if (lat != null && lon != null) pts.add(LatLng(lat, lon));
        }

        nuevos.add(RastroGpxInfo(
          archivo: f,
          nombre: nombre,
          puntos: pts,
          visible: visiblesPrevios[f.path] ?? false,
        ));
      } catch (_) {}
    }

    if (mounted) setState(() => _rastrosGuardados = nuevos);
  }

  Future<void> _renombrarRastro(
      RastroGpxInfo rastro, VoidCallback onActualizarModal) async {
    final ctrl = TextEditingController(text: rastro.nombre);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        title:Text(IdiomaService.t('gpx_renombrar'),
            style: TextStyle(color: Color(0xFFFF6D00), fontSize: 15)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: IdiomaService.t('gpx_nuevo_nombre'),
            filled: true,
            fillColor: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:Text(IdiomaService.t('cancelar'), style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black),
            onPressed: () async {
              final nuevoNombre = ctrl.text.trim();
              if (nuevoNombre.isNotEmpty) {
                try {
                  final xml = await rastro.archivo.readAsString();
                  final actualizado = xml.contains('<name>')
                      ? xml.replaceFirst(
                          RegExp(r'<name>.*?</name>'), '<name>$nuevoNombre</name>')
                      : xml.replaceFirst(
                          '<trk>', '<trk><name>$nuevoNombre</name>');
                  await rastro.archivo.writeAsString(actualizado);
                  rastro.nombre = nuevoNombre;
                } catch (_) {}
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              onActualizarModal();
              if (mounted) setState(() {});
            },
            child:Text(IdiomaService.t('guardar')),
          ),
        ],
      ),
    );
  }

  void _abrirGestorRastros() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    IdiomaService.t('rastros_gpx'),
                    style: const TextStyle(
                      color: Color(0xFFFF6D00),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${_rastrosGuardados.length} archivos',
                    style:
                        const TextStyle(color: Colors.cyanAccent, fontSize: 12),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              if (_rastrosGuardados.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    IdiomaService.t('gpx_vacio'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _rastrosGuardados.length,
                    itemBuilder: (_, i) {
                      final r = _rastrosGuardados.elementAt(i);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Switch(
                          value: r.visible,
                          activeThumbColor: Colors.cyanAccent,
                          onChanged: (v) {
                            setModalState(() => r.visible = v);
                            setState(() {});
                            if (v && r.puntos.isNotEmpty) {
                              _mapController.move(r.puntos.first, 15.0);
                            }
                          },
                        ),
                        title: Text(
                          r.nombre,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        subtitle: Text(
                          '${r.puntos.length} ${IdiomaService.t('gpx_puntos')}',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Color(0xFFFF6D00), size: 19),
                              tooltip: 'Renombrar rastro',
                              onPressed: () =>
                                  _renombrarRastro(r, () => setModalState(() {})),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 19),
                              tooltip: 'Eliminar rastro',
                              onPressed: () async {
                                try {
                                  await r.archivo.delete();
                                } catch (_) {}
                                _rastrosGuardados.removeAt(i);
                                setModalState(() {});
                                if (mounted) setState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleGrabarRastro() async {
    if (_grabandoRastro) {
      await _rastroSub?.cancel();
      _rastroSub = null;
      setState(() => _grabandoRastro = false);
      if (_puntosRastro.length >= 2) {
        await _guardarRastroGpx();
      }
      return;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return;
    }

    setState(() {
      _puntosRastro.clear();
      _grabandoRastro = true;
    });

    _rastroSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8, // Registra un punto cada 8 metros recorridos
      ),
    ).listen((pos) {
      if (!mounted) return;
      final pt = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _ubicacionActual = pt;
        _gpsObtenido = true;
        _puntosRastro.add(pt);
        _infoGps =
            'RASTRO (${_puntosRastro.length} pts) • LAT: ${pos.latitude.toStringAsFixed(5)} | LON: ${pos.longitude.toStringAsFixed(5)}';
      });
    });
  }

  Future<void> _guardarRastroGpx() async {
    try {
      final ahora = DateTime.now();
      final sello =
          '${ahora.year}${ahora.month.toString().padLeft(2, '0')}${ahora.day.toString().padLeft(2, '0')}_${ahora.hour.toString().padLeft(2, '0')}${ahora.minute.toString().padLeft(2, '0')}';
      final sb = StringBuffer()
        ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
        ..writeln('<gpx version="1.1" creator="AegisNode">')
        ..writeln('  <trk><name>Rastro AegisNode $sello</name><trkseg>');
      for (final p in _puntosRastro) {
        sb.writeln('    <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
      }
      sb
        ..writeln('  </trkseg></trk>')
        ..writeln('</gpx>');

      final archivo = File('${widget.rutaMapas}/rastro_$sello.gpx');
      await archivo.writeAsString(sb.toString());
      await _cargarRastrosGpx();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00E676),
          content: Text(
            '✅ Rastro GPX guardado (${_puntosRastro.length} puntos): rastro_$sello.gpx',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (_) {}
  }

  void _abrirDetalleWaypoint(WaypointTactico wp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(wp.nombre,
                style: const TextStyle(
                    color: Color(0xFFFF6D00),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 4),
            Text(
                '${IdiomaService.t('wp_coords')} ${wp.lat.toStringAsFixed(6)}, ${wp.lon.toStringAsFixed(6)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Colors.black),
              icon: const Icon(Icons.alt_route),
              label:Text(IdiomaService.t('wp_guiar'),
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(ctx);
                _iniciarGuiadoHacia(wp);
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black),
              icon: const Icon(Icons.share_location),
              label:Text(IdiomaService.t('wp_transmitir'),
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                final cfg = await NodoConfigService.cargar();
                final alias =
                    cfg.alias.trim().isEmpty ? 'Explorador' : cfg.alias.trim();
                await MeshChatService.publicarMensajeLocal(
                  autor: alias,
                  texto: '📌 WAYPOINT [${wp.tipo.toUpperCase()}]: ${wp.nombre}',
                  ttlInicial: cfg.ttlMaximo,
                  gps:
                      '${wp.lat.toStringAsFixed(6)},${wp.lon.toStringAsFixed(6)}',
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Color(0xFF00E676),
                    content: Text(IdiomaService.t('wp_transmitido_ok'),
                        style: TextStyle(color: Colors.black)),
                  ),
                );
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label:Text(IdiomaService.t('wp_eliminar'),
                  style: TextStyle(color: Colors.redAccent)),
              onPressed: () async {
                _waypoints.removeWhere((item) => item.id == wp.id);
                await WaypointsService.guardarLista(widget.rutaMapas, _waypoints);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _tileProvider?.dispose();
    _brujulaChannel.invokeMethod('detenerBrujula');
    _rastroSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF121212),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.satellite_alt,
                    size: 16,
                    color: _gpsObtenido ? const Color(0xFF00E676) : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _infoGps,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.my_location, size: 19),
                    tooltip: 'Centrar GPS',
                    onPressed: () async {
                      await _obtenerGps();
                      if (_tileProvider != null && _gpsObtenido) {
                        _mapController.move(_ubicacionActual, 6.0);
                      }
                    },
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_location_alt,
                        color: Color(0xFFFF6D00), size: 20),
                    tooltip: 'Marcar Waypoint aquí',
                    onPressed: () {
                      final objetivo = _tileProvider != null
                          ? _mapController.camera.center
                          : _ubicacionActual;
                      _crearWaypointEn(objetivo);
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _grabandoRastro
                          ? Icons.stop_circle
                          : Icons.fiber_manual_record,
                      color: _grabandoRastro
                          ? Colors.redAccent
                          : Colors.cyanAccent,
                      size: 20,
                    ),
                    tooltip: _grabandoRastro
                        ? 'Detener y guardar rastro GPX'
                        : 'Grabar rastro de ruta (GPX)',
                    onPressed: _toggleGrabarRastro,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.timeline,
                        color: Colors.cyanAccent, size: 20),
                    tooltip: 'Gestionar rastros GPX guardados',
                    onPressed: _abrirGestorRastros,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.upload_file,
                        color: Color(0xFFFF6D00), size: 20),
                    tooltip: 'Importar mapa .mbtiles',
                    onPressed: _importarMbtiles,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Recargar mapas',
                    onPressed: _escanearMapas,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_destinoGuiado != null)
          Builder(
            builder: (context) {
              final distMetros = Geolocator.distanceBetween(
                _ubicacionActual.latitude,
                _ubicacionActual.longitude,
                _destinoGuiado!.lat,
                _destinoGuiado!.lon,
              );
              final rumboGrados = ((Geolocator.bearingBetween(
                            _ubicacionActual.latitude,
                            _ubicacionActual.longitude,
                            _destinoGuiado!.lat,
                            _destinoGuiado!.lon,
                          ) +
                          360) %
                      360)
                  .round();
              final distStr = distMetros >= 1000
                  ? '${(distMetros / 1000).toStringAsFixed(2)} km'
                  : '${distMetros.round()} m';
              final modoTexto = _rutaActiva == null
                  ? 'Calculando ruta...'
                  : _rutaActiva!.origenDato;

              return Container(
                color: const Color(0xFF1A1A1A),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _rutaActiva?.esPorCalles == true
                          ? Icons.alt_route
                          : Icons.explore,
                      color: const Color(0xFF00E676),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_destinoGuiado!.nombre} • $distStr • $rumboGrados°\n$modoTexto',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.redAccent, size: 18),
                      onPressed: () => setState(() {
                        _destinoGuiado = null;
                        _rutaActiva = null;
                      }),
                    ),
                  ],
                ),
              );
            },
          ),

        if (_archivosMbtiles.isNotEmpty)
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
                          Text(
                            IdiomaService.t('sin_mapas'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            IdiomaService.t('sin_mapas_desc'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _importarMbtiles,
                            icon: const Icon(Icons.upload_file),
                            label: Text(IdiomaService.t('importar_mapas'),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    )
                  : FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: const LatLng(0, 0),
                        initialZoom: 2.0,
                        minZoom: 0.0,
                        maxZoom: _maxZoomPermitido,
                        backgroundColor: const Color(0xFF000000),
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture) {
                            _evaluarCambioAutomaticoMapa(
                                camera.center, camera.zoom);
                          }
                        },
                        onLongPress: (tapPos, punto) =>
                            _crearWaypointEn(punto),
                      ),
                      children: [
                        TileLayer(
                          tileProvider: _tileProvider!,
                          maxNativeZoom: _maxNativeZoomActivo,
                          maxZoom: _maxZoomPermitido,
                        ),
                        if (_rutaActiva != null &&
                            _rutaActiva!.puntos.length >= 2)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _rutaActiva!.puntos,
                                color: _rutaActiva!.esPorCalles
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFFFF6D00),
                                strokeWidth: 4.5,
                              ),
                            ],
                          ),
                     if (_puntosRastro.length >= 2 ||
                         _rastrosGuardados.any((r) => r.visible))
                       PolylineLayer(
                         polylines: [
                           if (_puntosRastro.length >= 2)
                             Polyline(
                               points: _puntosRastro,
                               color: Colors.cyanAccent,
                               strokeWidth: 4.5,
                             ),
                           ..._rastrosGuardados
                               .where((r) => r.visible && r.puntos.length >= 2)
                               .map(
                                 (r) => Polyline(
                                   points: r.puntos,
                                   color: Colors.purpleAccent,
                                   strokeWidth: 4.0,
                                 ),
                               ),
                         ],
                       ),
                        MarkerLayer(
                          markers: [
                            if (_gpsObtenido)
                           Marker(
                             point: _ubicacionActual,
                             width: 44,
                             height: 44,
                             child: Transform.rotate(
                               angle: (_rumboBrujulaGrados + _mapController.camera.rotation) * (math.pi / 180.0),
                               child: const Icon(
                                 Icons.navigation,
                                 color: Color(0xFFFF6D00),
                                 size: 34,
                               ),
                             ),
                           ),
                            if (widget.coordenadaDestino != null)
                              Marker(
                                point: widget.coordenadaDestino!,
                                width: 44,
                                height: 44,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Color(0xFF00E676),
                                  size: 38,
                                ),
                              ),
                            ..._waypoints.map(
                              (wp) => Marker(
                                point: LatLng(wp.lat, wp.lon),
                                width: 110,
                                height: 54,
                                child: GestureDetector(
                                  onTap: () => _abrirDetalleWaypoint(wp),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: const Color(0xFFFF6D00)),
                                        ),
                                        child: Text(
                                          wp.nombre,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Icon(
                                        wp.tipo == 'peligro'
                                            ? Icons.warning_amber_rounded
                                            : wp.tipo == 'agua'
                                                ? Icons.water_drop
                                                : wp.tipo == 'auxilio'
                                                    ? Icons.local_hospital
                                                    : Icons.flag,
                                        color: wp.tipo == 'peligro'
                                            ? Colors.redAccent
                                            : const Color(0xFFFF6D00),
                                        size: 26,
                                      ),
                                    ],
                                  ),
                                ),
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
