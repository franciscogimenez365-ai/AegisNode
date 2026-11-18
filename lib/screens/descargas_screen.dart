import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/descargas_service.dart';
import 'explorador_mapas_screen.dart';
import '../services/geo_db_service.dart';
import 'explorador_pdf_screen.dart';
import 'package:geolocator/geolocator.dart';
import '../services/enrutador_offline_service.dart';



class DescargasScreen extends StatefulWidget {
  final String rutaBase;
  const DescargasScreen({super.key, required this.rutaBase});

  @override
  State<DescargasScreen> createState() => _DescargasScreenState();
}

class _DescargasScreenState extends State<DescargasScreen> {
  final DescargasService _service = DescargasService();
  final Map<String, double> _progresos = {};
  final Map<String, CancelToken> _tokens = {};
  final TextEditingController _urlCtrl = TextEditingController();

  String _categoriaSeleccionada = 'mapas';
  String _regionGpsDetectada = 'global';
  List<RecursoOffline> _mapasDinamicos = [];
  final TextEditingController _wikiSearchCtrl = TextEditingController();
  List<RecursoOffline> _wikisBuscadas = [];
  bool _buscandoWiki = false;
bool _descargandoRedVial = false;
String _estadoRedVial = '';
double? _progresoRedVial;

Future<void> _descargarRedVialGps() async {
  if (_descargandoRedVial) return;
  setState(() {
    _descargandoRedVial = true;
    _progresoRedVial = null;
    _estadoRedVial = 'Obteniendo ubicación GPS actual...';
  });

  try {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 10));

    final ok = await EnrutadorOfflineService.descargarRedVialLocal(
      rutaMapas: '${widget.rutaBase}/mapas',
      lat: pos.latitude,
      lon: pos.longitude,
      radioKm: 45.0,
      onProgreso: (msg, prog) {
        if (mounted) {
          setState(() {
            _estadoRedVial = msg;
            _progresoRedVial = prog;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _descargandoRedVial = false;
      if (!ok) _progresoRedVial = null;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _descargandoRedVial = false;
      _progresoRedVial = null;
      _estadoRedVial = 'Error GPS/Red: $e';
    });
  }
}

  @override
  void initState() {
    super.initState();
    _detectarRegion();
  }

Future<void> _detectarRegion() async {
  final mapas = await DescargasService.obtenerMapasDinamicosPorGps();
  final lugar = await GeoDbService.detectarCiudadActualPorGps();
  if (mounted) {
    setState(() {
      _mapasDinamicos = mapas;
      _regionGpsDetectada = lugar?.ciudad ?? 'Global';
    });
  }
}
Future<void> _buscarEnKiwix(String texto) async {
  if (texto.trim().length < 2) {
    setState(() => _wikisBuscadas = []);
    return;
  }
  setState(() => _buscandoWiki = true);
  try {
    final lista = await _service.buscarPaquetesKiwix(texto);
    if (mounted) setState(() => _wikisBuscadas = lista);
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error buscando en Kiwix: $e')),
      );
    }
  } finally {
    if (mounted) setState(() => _buscandoWiki = false);
  }
}


List<RecursoOffline> _obtenerCatalogoFiltrado() {
  if (_categoriaSeleccionada == 'wikis') {
    if (_wikiSearchCtrl.text.trim().length >= 2) {
      return _wikisBuscadas;
    }
    return DescargasService.obtenerWikisDinamicasPorIdioma();
  } else if (_categoriaSeleccionada == 'manuales') {
    return [];
  } else {
    return _mapasDinamicos;
  }
}





  Future<void> _iniciarDescarga(RecursoOffline recurso) async {
    final destino =
        '${widget.rutaBase}/${recurso.categoriaCarpeta}/${recurso.nombreArchivoDestino}';
    final token = CancelToken();

    setState(() {
      _tokens[recurso.id] = token;
      _progresos[recurso.id] = 0.01;
    });

    try {
      await _service.descargarRecurso(
        recurso: recurso,
        rutaDestino: destino,
        cancelToken: token,
        onProgreso: (p) {
          if (mounted) setState(() => _progresos[recurso.id] = p);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Instalado: ${recurso.titulo}')),
        );
      }
    } catch (e) {
      final fueCancelado = e is DioException && CancelToken.isCancel(e);
      if (mounted && !fueCancelado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error: ${e.toString().replaceAll("Exception: ", "")}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _descargarUrlPersonalizada() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || !url.startsWith('http')) return;
    final nombre = Uri.parse(url).pathSegments.isNotEmpty
        ? Uri.parse(url).pathSegments.last
        : 'recurso_${DateTime.now().millisecondsSinceEpoch}.dat';

    final custom = RecursoOffline(
      id: 'custom_$nombre',
      titulo: nombre,
      subcategoria: 'Importado por URL',
      descripcion: 'Descarga directa',
      categoriaCarpeta: _categoriaSeleccionada,
      nombreArchivoDestino: nombre,
      tamanoAprox: '',
      urlDirecta: url,
    );
    _iniciarDescarga(custom);
    _urlCtrl.clear();
  }
  @override
  Widget build(BuildContext context) {
    final listaActual = _obtenerCatalogoFiltrado();
    final etiquetasCategoria = {
      'mapas': 'SUGERENCIAS DE MAPAS (SEGÚN TU GPS: ${_regionGpsDetectada.toUpperCase()})',
      'wikis': 'ENCICLOPEDIAS ZIM',
      'manuales': 'MANUALES TÉCNICOS Y DE EMERGENCIA (PDF)',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('SELECCIONA EL TIPO DE RECURSO A PREPARAR',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: _categoriaSeleccionada,
                underline: const SizedBox(),
                dropdownColor: const Color(0xFF121212),
                items: const [
                  DropdownMenuItem(value: 'mapas', child: Text('Mapas')),
                  DropdownMenuItem(value: 'wikis', child: Text('Wikis ZIM')),
                  DropdownMenuItem(value: 'manuales', child: Text('Manuales PDF')),
                ],
                onChanged: (v) => setState(() => _categoriaSeleccionada = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  hintText: 'URL directa opcional...',
                  filled: true,
                  fillColor: const Color(0xFF121212),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.download, color: Color(0xFFFF6D00)),
              tooltip: 'Descargar URL personalizada',
              onPressed: _descargarUrlPersonalizada,
            ),
          ],
        ),
        const Divider(height: 28),
        Text(etiquetasCategoria[_categoriaSeleccionada]!,
            style: const TextStyle(
                color: Color(0xFFFF6D00),
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (_categoriaSeleccionada == 'mapas') ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.account_tree),
            label: const Text(
              'EXPLORAR POR CONTINENTE / PAÍS / PROVINCIA / CIUDAD',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExploradorMapasScreen(
                    rutaMapas: '${widget.rutaBase}/mapas',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF121212),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'RED VIAL OFFLINE (RUTAS POR CALLES)',
                    style: TextStyle(
                      color: Color(0xFFFF6D00),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,                      
                    ),
                  ),
                  if (_descargandoRedVial) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progresoRedVial,
                      color: const Color(0xFF00E676),
                      backgroundColor: const Color(0xFF222222),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Text(
                    'Descarga las calles y caminos (45 km alrededor de tu GPS) para calcular rutas esquina por esquina sin Internet.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  if (_estadoRedVial.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _estadoRedVial,
                      style: const TextStyle(
                          color: Color(0xFF00E676), fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                    ),
                    onPressed:
                        _descargandoRedVial ? null : _descargarRedVialGps,
                    icon: const Icon(Icons.alt_route),
                    label: Text(
                      _descargandoRedVial
                          ? 'DESCARGANDO CALLES (45 KM)...'
                          : 'DESCARGAR RED VIAL (45 KM)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

                if (_categoriaSeleccionada == 'manuales') ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.manage_search),
            label: const Text(
              'BUSCAR MANUALES LIBRES EN BASE MUNDIAL (PDF)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExploradorPdfScreen(
                    rutaManuales: '${widget.rutaBase}/manuales',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
             if (_categoriaSeleccionada == 'wikis') ...[
       TextField(
         controller: _wikiSearchCtrl,
         onSubmitted: _buscarEnKiwix,
         decoration: InputDecoration(
           hintText: 'Buscar tema en catálogo Kiwix (ej. electrónica, física)...',
           prefixIcon: const Icon(Icons.search),
           suffixIcon: _wikiSearchCtrl.text.isNotEmpty
               ? IconButton(
                   icon: const Icon(Icons.clear),
                   onPressed: () {
                     _wikiSearchCtrl.clear();
                     setState(() => _wikisBuscadas = []);
                   },
                 )
               : IconButton(
                   icon: const Icon(Icons.arrow_forward,
                       color: Color(0xFFFF6D00)),
                   onPressed: () => _buscarEnKiwix(_wikiSearchCtrl.text),
                 ),
           filled: true,
           fillColor: const Color(0xFF121212),
           border: OutlineInputBorder(
               borderRadius: BorderRadius.circular(10),
               borderSide: BorderSide.none),
         ),
       ),
       if (_buscandoWiki) ...[
         const SizedBox(height: 8),
         const LinearProgressIndicator(color: Color(0xFFFF6D00)),
       ],
       const SizedBox(height: 12),
     ],

        ...listaActual.map((item) {
          final archivoLocal = File(
              '${widget.rutaBase}/${item.categoriaCarpeta}/${item.nombreArchivoDestino}');
          final yaExiste = archivoLocal.existsSync();
          final progreso = _progresos[item.id];
          final esRecomendadoGps = _categoriaSeleccionada == 'mapas' &&
              item.regionGps == _regionGpsDetectada &&
              _regionGpsDetectada != 'global';

          return Card(
            color: const Color(0xFF121212),
            shape: esRecomendadoGps
                ? RoundedRectangleBorder(
                    side: const BorderSide(color: Color(0xFF00E676), width: 1),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Row(
                children: [
                  Expanded(
                    child: Text(item.titulo,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (esRecomendadoGps)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('TU ZONA GPS',
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
                  Text(item.subcategoria,
                      style: const TextStyle(
                          color: Color(0xFFFF6D00), fontSize: 12)),
                  const SizedBox(height: 2),
                  Text('${item.descripcion} (${item.tamanoAprox})'),
                  if (progreso != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progreso,
                      color: const Color(0xFF00E676),
                    ),
                    Text('${(progreso * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 11)),
                  ]
                ],
              ),
              trailing: progreso != null
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () => _tokens[item.id]?.cancel(),
                    )
                  : IconButton(
                      icon: Icon(
                        yaExiste ? Icons.check_circle : Icons.cloud_download,
                        color: yaExiste
                            ? const Color(0xFF00E676)
                            : const Color(0xFFFF6D00),
                      ),
                      onPressed: () => _iniciarDescarga(item),
                    ),
            ),
          );
        }),
      ],
    );
  }
}
