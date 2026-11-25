import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/kiwix_bridge.dart';
import '../services/idioma_service.dart';

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
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
                return NavigationDecision.navigate;
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },

        ),
      );
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
    _searchCtrl.clear();
    final url = await KiwixBridge.abrirZim(archivo.path);
    if (!mounted) return;
    setState(() {
      _zimActivo = archivo;
      _urlBase = url;
      _resultados = [];
      _mostrandoBuscador = false;
    });
    if (url != null) {
      final sep = url.contains('?') ? '&' : '?';
      final urlFresca =
          '$url${sep}reload=${DateTime.now().millisecondsSinceEpoch}';
      await _webController.loadRequest(Uri.parse(urlFresca));
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

  Future<void> _importarZim() async {
    final res = await FilePicker.pickFiles();
    if (res.isEmpty) return;

    final validos = res
        .where((f) => f.path != null && f.path!.toLowerCase().endsWith('.zim'))
        .toList();

    if (validos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No seleccionaste archivos .zim válidos')),
      );
      return;
    }

    int indiceActual = 0;
    String nombreActual = '';
    double pctArchivo = 0.0;
    String detalleMb = '';
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
            title: const Text('IMPORTANDO ENCICLOPEDIAS ZIM',
                style: TextStyle(color: Color(0xFFFF6D00), fontSize: 15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Archivo ${indiceActual + 1} de ${validos.length}:\n$nombreActual\n$detalleMb',
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
      detalleMb = 'Iniciando...';
      actualizarDialogo?.call(() {});

      final destino = File('${widget.rutaWikis}/$nombreActual');
      if (await destino.exists()) {
        await destino.delete();
      }

      final totalBytes = await origen.length();
      int copiadosBytes = 0;
      final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

      final sink = destino.openWrite();
      await for (final chunk in origen.openRead()) {
        sink.add(chunk);
        copiadosBytes += chunk.length;
        pctArchivo = totalBytes > 0 ? (copiadosBytes / totalBytes) : 1.0;
        final mbCop = (copiadosBytes / (1024 * 1024)).toStringAsFixed(1);
        detalleMb =
            '$mbCop MB / $mbTotal MB (${(pctArchivo * 100).toStringAsFixed(0)}%)';
        actualizarDialogo?.call(() {});
      }
      await sink.close();
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      await _escanearZims();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00E676),
          content: Text(
            '✅ ${validos.length} enciclopedia(s) .zim importadas y listas.',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
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
            Text(IdiomaService.t('sin_zim'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              IdiomaService.t('sin_zim_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
              ),
              onPressed: _importarZim,
              icon: const Icon(Icons.upload_file),
              label: Text(IdiomaService.t('importar_zim'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _escanearZims,
              icon: const Icon(Icons.refresh),
              label: Text(IdiomaService.t('recargar_carpeta')),
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
                icon: const Icon(Icons.upload_file,
                    size: 20, color: Color(0xFFFF6D00)),
                tooltip: 'Importar archivo .ZIM',
                onPressed: _importarZim,
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
              '${IdiomaService.t('buscar_tema')} ${_zimActivo?.uri.pathSegments.last ?? "Wiki"}...',
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
