import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/geo_db_service.dart';
import '../services/generador_mbtiles.dart';
import '../services/idioma_service.dart';

class ExploradorMapasScreen extends StatefulWidget {
  final String rutaMapas;
  const ExploradorMapasScreen({super.key, required this.rutaMapas});

  @override
  State<ExploradorMapasScreen> createState() => _ExploradorMapasScreenState();
}

class _ExploradorMapasScreenState extends State<ExploradorMapasScreen> {
  String? _continenteSel;
  String? _paisSel;
  String? _provinciaSel;

  List<String> _nombresNivel = [];
  List<LugarGeo> _ciudadesNivel = [];
  LugarGeo? _lugarGpsActual;

  bool _cargando = true;
  final TextEditingController _buscadorCtrl = TextEditingController();
  final Map<String, double> _progresos = {};
  final Map<String, CancelToken> _tokens = {};

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final gps = await GeoDbService.detectarCiudadActualPorGps();
    if (mounted) setState(() => _lugarGpsActual = gps);
    await _cargarNivelActual();
  }

  Future<void> _cargarNivelActual() async {
    setState(() => _cargando = true);
    try {
      if (_buscadorCtrl.text.trim().length >= 2) {
        final res =
            await GeoDbService.buscarCiudadesPorNombre(_buscadorCtrl.text);
        if (!mounted) return;
        setState(() {
          _ciudadesNivel = res;
          _nombresNivel = [];
        });
      } else if (_continenteSel == null) {
        final lista = await GeoDbService.listarContinentes();
        if (!mounted) return;
        setState(() {
          _nombresNivel = lista;
          _ciudadesNivel = [];
        });
      } else if (_paisSel == null) {
        final lista = await GeoDbService.listarPaises(_continenteSel!);
        if (!mounted) return;
        setState(() {
          _nombresNivel = lista;
          _ciudadesNivel = [];
        });
      } else if (_provinciaSel == null) {
        final lista =
            await GeoDbService.listarProvincias(_continenteSel!, _paisSel!);
        if (!mounted) return;
        setState(() {
          _nombresNivel = lista;
          _ciudadesNivel = [];
        });
      } else {
        final lista = await GeoDbService.listarCiudades(
            _continenteSel!, _paisSel!, _provinciaSel!);
        if (!mounted) return;
        setState(() {
          _ciudadesNivel = lista;
          _nombresNivel = [];
        });
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _subirNivel() {
    if (_provinciaSel != null) {
      _provinciaSel = null;
    } else if (_paisSel != null) {
      _paisSel = null;
    } else if (_continenteSel != null) {
      _continenteSel = null;
    }
    _cargarNivelActual();
  }

  Future<void> _descargarCiudad(LugarGeo lugar, {bool esMundial = false}) async {
    final id = esMundial ? 'mundial_base' : '${lugar.pais}_${lugar.ciudad}';
    final nombreArchivo = esMundial
        ? 'mundial_base.mbtiles'
        : '${lugar.ciudad.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_calles.mbtiles';
    final rutaDestino = '${widget.rutaMapas}/$nombreArchivo';
    final token = CancelToken();

    setState(() {
      _tokens[id] = token;
      _progresos[id] = 0.01;
    });

    try {
      final b = esMundial
          ? [-85.0, 85.0, -180.0, 180.0]
          : lugar.bboxNivelCalle;
      await GeneradorMbtilesService().generarRegionMbtiles(
        rutaDestino: rutaDestino,
        nombreMapa: esMundial
            ? 'Mapa Mundial Base (Zoom 0-5)'
            : '${lugar.ciudad}, ${lugar.pais}',
        minLat: b.first,
        maxLat: b.elementAt(1),
        minLon: b.elementAt(2),
        maxLon: b.elementAt(3),
        minZoom: esMundial ? 0 : 10,
        maxZoom: esMundial ? 5 : 15,
        cancelToken: token,
        onProgreso: (p) {
          if (mounted) setState(() => _progresos[id] = p);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Instalado: $nombreArchivo')),
        );
      }
    } catch (e) {
      if (mounted && !token.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _progresos.remove(id);
          _tokens.remove(id);
        });
      }
    }
  }
  Widget _tarjetaCiudad(LugarGeo lugar, {bool destacadaGps = false}) {
    final id = '${lugar.pais}_${lugar.ciudad}';
    final nombreArchivo =
        '${lugar.ciudad.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_calles.mbtiles';
    final yaExiste = File('${widget.rutaMapas}/$nombreArchivo').existsSync();
    final progreso = _progresos[id];

    return Card(
      color: const Color(0xFF121212),
      shape: destacadaGps
          ? RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFF00E676), width: 1.2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(lugar.ciudad,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (destacadaGps)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(IdiomaService.t('exp_mapas_tu_gps'),
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${lugar.provincia}, ${lugar.pais} • ${IdiomaService.t('exp_mapas_calle')}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (progreso != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: progreso, color: const Color(0xFF00E676)),
              Text('${(progreso * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11)),
            ],
          ],
        ),
        trailing: progreso != null
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: () => _tokens[id]?.cancel(),
              )
            : IconButton(
                icon: Icon(
                  yaExiste ? Icons.check_circle : Icons.download,
                  color: yaExiste
                      ? const Color(0xFF00E676)
                      : const Color(0xFFFF6D00),
                ),
                onPressed: () => _descargarCiudad(lugar),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final migas = [
      'Mundo',
      ?_continenteSel,
      ?_paisSel,
      ?_provinciaSel,
    ].join(' > ');


    return Scaffold(
      appBar: AppBar(
        title:Text(IdiomaService.t('exp_mapas_titulo'),
            style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF121212),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _buscadorCtrl,
              onChanged: (_) => _cargarNivelActual(),
              decoration: InputDecoration(
                hintText: IdiomaService.t('exp_mapas_hint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscadorCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscadorCtrl.clear();
                          _cargarNivelActual();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF121212),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_buscadorCtrl.text.trim().length < 2)
            Container(
              color: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  if (_continenteSel != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Color(0xFFFF6D00)),
                      onPressed: _subirNivel,
                    ),
                  Expanded(
                    child: Text(migas,
                        style: const TextStyle(
                            color: Color(0xFF00E676), fontSize: 12)),
                  ),
                ],
              ),
            ),
          if (_cargando)
            const LinearProgressIndicator(color: Color(0xFFFF6D00)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_continenteSel == null &&
                    _buscadorCtrl.text.trim().length < 2) ...[
                  if (_lugarGpsActual != null)
                    _tarjetaCiudad(_lugarGpsActual!, destacadaGps: true),
                  Card(
                    color: const Color(0xFF121212),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.public,
                          color: Color(0xFFFF6D00)),
                      title:Text(IdiomaService.t('exp_mapas_mundial'),
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle:Text(
                          IdiomaService.t('exp_mapas_mundial_sub')),
                      trailing: _progresos['mundial_base'] != null
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: const Icon(Icons.download,
                                  color: Color(0xFFFF6D00)),
                              onPressed: () => _descargarCiudad(
                                const LugarGeo(
                                    continente: '',
                                    pais: '',
                                    provincia: '',
                                    ciudad: 'Mundo',
                                    lat: 0,
                                    lon: 0),
                                esMundial: true,
                              ),
                            ),
                    ),
                  ),
                ],
                ..._nombresNivel.map((nombre) => Card(
                      color: const Color(0xFF121212),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.folder,
                            color: Color(0xFFFF6D00)),
                        title: Text(nombre,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (_continenteSel == null) {
                            _continenteSel = nombre;
                          } else if (_paisSel == null) {
                            _paisSel = nombre;
                          } else {
                            _provinciaSel = nombre;
                          }
                          _cargarNivelActual();
                        },
                      ),
                    )),
                ..._ciudadesNivel.map((c) => _tarjetaCiudad(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
