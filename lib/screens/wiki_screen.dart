import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/kiwix_bridge.dart';

class WikiScreen extends StatefulWidget {
  final String rutaWikis;
  const WikiScreen({super.key, required this.rutaWikis});

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  List<File> _archivosZim = [];
  File? _zimActivo;
  String? _urlBase;
  List<Map<String, String>> _resultados = [];
  bool _mostrandoBuscador = false;
  final TextEditingController _searchCtrl = TextEditingController();
  late final WebViewController _webController;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000));
    _escanearZims();
  }

  Future<void> _escanearZims() async {
    final dir = Directory(widget.rutaWikis);
    if (dir.existsSync()) {
      final lista = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.zim'))
          .toList();
      if (!mounted) return;
      setState(() => _archivosZim = lista);
      if (lista.isNotEmpty) {
        final seleccion = (_zimActivo != null &&
                lista.any((f) => f.path == _zimActivo!.path))
            ? _zimActivo!
            : lista.first;
        await _seleccionarZim(seleccion);
      }
    }
  }

  Future<void> _seleccionarZim(File archivo) async {
    final url = await KiwixBridge.abrirZim(archivo.path);
    if (!mounted) return;
    setState(() {
      _zimActivo = archivo;
      _urlBase = url;
      _resultados = [];
      _mostrandoBuscador = false;
    });
    if (url != null) {
      await _webController.loadRequest(Uri.parse(url));
    }
  }

  Future<void> _buscar(String texto) async {
    if (texto.trim().isEmpty) {
      setState(() {
        _resultados = [];
        _mostrandoBuscador = false;
      });
      return;
    }
    if (_urlBase == null) return;
    final lista = await KiwixBridge.buscarSugerencias(texto);
    if (!mounted) return;
    setState(() {
      _resultados = lista;
      _mostrandoBuscador = true;
    });
  }

  Future<void> _abrirRuta(String path) async {
    if (_urlBase == null) return;
    final limpio = path.startsWith('/') ? path.substring(1) : path;
    await _webController.loadRequest(Uri.parse('$_urlBase$limpio'));
    if (!mounted) return;
    setState(() => _mostrandoBuscador = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_archivosZim.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.public_off, size: 64, color: Color(0xFFFF6D00)),
            const SizedBox(height: 16),
            const Text('Sin archivos .ZIM instalados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Descarga paquetes en la pestaña Preparar o colócalos en:\n${widget.rutaWikis}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _escanearZims,
              icon: const Icon(Icons.refresh),
              label: const Text('Recargar carpeta'),
            )
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.storage, size: 18, color: Color(0xFFFF6D00)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _zimActivo?.path,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF121212),
                  items: _archivosZim.map((f) {
                    return DropdownMenuItem<String>(
                      value: f.path,
                      child: Text(f.uri.pathSegments.last),
                    );
                  }).toList(),
                  onChanged: (path) {
                    if (path != null) {
                      final elegido =
                          _archivosZim.firstWhere((f) => f.path == path);
                      _seleccionarZim(elegido);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.home, size: 20, color: Color(0xFF00E676)),
                tooltip: 'Ir a portada',
                onPressed: () {
                  if (_urlBase != null) {
                    _webController.loadRequest(Uri.parse(_urlBase!));
                    setState(() => _mostrandoBuscador = false);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _escanearZims,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _buscar,
            decoration: InputDecoration(
              hintText:
                  'Buscar tema en ${_zimActivo?.uri.pathSegments.last ?? "Wiki"}...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _buscar('');
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
        Expanded(
          child: _mostrandoBuscador
              ? ListView.builder(
                  itemCount: _resultados.length,
                  itemBuilder: (context, i) {
                    final item = _resultados.elementAt(i);
                    return ListTile(
                      leading:
                          const Icon(Icons.article, color: Color(0xFF00E676)),
                      title: Text(item['title'] ?? ''),
                      onTap: () => _abrirRuta(item['path'] ?? ''),
                    );
                  },
                )
              : WebViewWidget(controller: _webController),
        ),
      ],
    );
  }
}
