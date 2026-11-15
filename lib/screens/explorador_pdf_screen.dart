import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/buscador_pdf_service.dart';
import '../services/descargas_service.dart';

class ExploradorPdfScreen extends StatefulWidget {
  final String rutaManuales;
  const ExploradorPdfScreen({super.key, required this.rutaManuales});

  @override
  State<ExploradorPdfScreen> createState() => _ExploradorPdfScreenState();
}

class _ExploradorPdfScreenState extends State<ExploradorPdfScreen> {
  final TextEditingController _buscadorCtrl = TextEditingController();
  final DescargasService _descargasService = DescargasService();

  List<ManualPdfRemoto> _resultados = [];
  bool _buscando = false;
  final Map<String, double> _progresos = {};
  final Map<String, CancelToken> _tokens = {};

  static const List<String> _temasRapidos = [
    'primeros auxilios',
    'supervivencia',
    'agua potable',
    'energia solar',
    'radio comunicaciones',
  ];

  @override
  void initState() {
    super.initState();
    _ejecutarBusqueda('primeros auxilios');
  }

  Future<void> _ejecutarBusqueda(String consulta) async {
    _buscadorCtrl.text = consulta;
    setState(() => _buscando = true);
    try {
      final lista = await BuscadorPdfService.buscarManualesPdf(consulta);
      if (mounted) setState(() => _resultados = lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error consultando catálogo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _descargarManual(ManualPdfRemoto manual) async {
    final nombreArchivo =
        '${manual.identifier.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.pdf';
    final destino = '${widget.rutaManuales}/$nombreArchivo';
    final token = CancelToken();

    setState(() {
      _tokens[manual.identifier] = token;
      _progresos[manual.identifier] = 0.01;
    });

    try {
      final recurso = RecursoOffline(
        id: manual.identifier,
        titulo: manual.titulo,
        subcategoria: manual.autor,
        descripcion: '',
        categoriaCarpeta: 'manuales',
        nombreArchivoDestino: nombreArchivo,
        tamanoAprox: '',
        urlDirecta: manual.urlPdfDirecta,
      );

      await _descargasService.descargarRecurso(
        recurso: recurso,
        rutaDestino: destino,
        cancelToken: token,
        onProgreso: (p) {
          if (mounted) setState(() => _progresos[manual.identifier] = p);
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Manual guardado: $nombreArchivo')),
        );
      }
    } catch (e) {
      if (mounted && !token.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error descargando PDF: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _progresos.remove(manual.identifier);
          _tokens.remove(manual.identifier);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscador Mundial de Manuales PDF',
            style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF121212),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscadorCtrl,
                    onSubmitted: _ejecutarBusqueda,
                    decoration: InputDecoration(
                      hintText: 'Ej. primeros auxilios, supervivencia, solar...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFF121212),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => _ejecutarBusqueda(_buscadorCtrl.text),
                  child: const Text('Buscar'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _temasRapidos.map((tema) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: const Color(0xFF1A1A1A),
                    label: Text(tema, style: const TextStyle(fontSize: 12)),
                    onPressed: () => _ejecutarBusqueda(tema),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          if (_buscando)
            const LinearProgressIndicator(color: Color(0xFFFF6D00)),
          Expanded(
            child: _resultados.isEmpty && !_buscando
                ? const Center(
                    child: Text('Escribe un tema técnico o de emergencia',
                        style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _resultados.length,
                    itemBuilder: (context, index) {
                      final manual = _resultados.elementAt(index);
                      final nombreArchivo =
                          '${manual.identifier.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.pdf';
                      final yaExiste =
                          File('${widget.rutaManuales}/$nombreArchivo')
                              .existsSync();
                      final progreso = _progresos[manual.identifier];

                      return Card(
                        color: const Color(0xFF121212),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(manual.titulo,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(manual.autor,
                                  style: const TextStyle(
                                      color: Color(0xFFFF6D00), fontSize: 12)),
                              if (progreso != null) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                    value: progreso,
                                    color: const Color(0xFF00E676)),
                                Text('${(progreso * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ],
                          ),
                          trailing: progreso != null
                              ? IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.redAccent),
                                  onPressed: () =>
                                      _tokens[manual.identifier]?.cancel(),
                                )
                              : IconButton(
                                  icon: Icon(
                                    yaExiste
                                        ? Icons.check_circle
                                        : Icons.download,
                                    color: yaExiste
                                        ? const Color(0xFF00E676)
                                        : const Color(0xFFFF6D00),
                                  ),
                                  onPressed: () => _descargarManual(manual),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
