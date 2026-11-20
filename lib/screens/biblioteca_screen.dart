import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'visor_pdf_screen.dart';

class BibliotecaScreen extends StatefulWidget {
  final String rutaManuales;
  const BibliotecaScreen({super.key, required this.rutaManuales});

  @override
  State<BibliotecaScreen> createState() => _BibliotecaScreenState();
}

class _BibliotecaScreenState extends State<BibliotecaScreen> {
  List<File> _todosLosArchivos = [];
  List<File> _archivosFiltrados = [];
  final TextEditingController _buscadorCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarArchivos();
  }

  void _cargarArchivos() {
    final dir = Directory(widget.rutaManuales);
    if (dir.existsSync()) {
      final lista = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList();
      setState(() {
        _todosLosArchivos = lista;
        _archivosFiltrados = lista;
      });
    }
  }

  void _filtrar(String texto) {
    final query = texto.toLowerCase();
    setState(() {
      _archivosFiltrados = _todosLosArchivos.where((f) {
        final nombre = f.uri.pathSegments.last.toLowerCase();
        return nombre.contains(query);
      }).toList();
    });
  }
  Future<void> _importarPdf() async {
    final res = await FilePicker.pickFiles();
    if (res.isEmpty) return;

    final pdfsValidos = res
        .where((f) => f.path != null && f.path!.toLowerCase().endsWith('.pdf'))
        .toList();

    if (pdfsValidos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No seleccionaste archivos .pdf válidos')),
      );
      return;
    }

    int copiados = 0;
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
            title: const Text('IMPORTANDO MANUALES PDF',
                style: TextStyle(color: Color(0xFFFF6D00), fontSize: 15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Copiando $copiados de ${pdfsValidos.length} archivos...',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: copiados / pdfsValidos.length,
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

    for (final item in pdfsValidos) {
      final origen = File(item.path!);
      final nombre = origen.uri.pathSegments.last;
      final destino = File('${widget.rutaManuales}/$nombre');
      if (await destino.exists()) {
        await destino.delete();
      }
      await origen.copy(destino.path);
      copiados++;
      actualizarDialogo?.call(() {});
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _cargarArchivos();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00E676),
          content: Text(
            '✅ $copiados manual(es) PDF importados correctamente.',
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

@override
Widget build(BuildContext context) {
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12.0),
        child: TextField(
          controller: _buscadorCtrl,
          onChanged: _filtrar,
          decoration: InputDecoration(
            hintText: 'Buscar manual PDF...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.upload_file,
                      color: Color(0xFFFF6D00)),
                  tooltip: 'Importar archivo .PDF',
                  onPressed: _importarPdf,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _cargarArchivos,
                ),
              ],
            ),
            filled: true,
            fillColor: const Color(0xFF121212),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      Expanded(
        child: _archivosFiltrados.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Sin manuales PDF instalados.\nImporta un archivo desde tu teléfono para leerlo sin conexión.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _importarPdf,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Importar archivo .PDF',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                  itemCount: _archivosFiltrados.length,
                  itemBuilder: (context, index) {
                    final archivo = _archivosFiltrados[index];
                    final nombre = archivo.uri.pathSegments.last;
                    final mb = (archivo.lengthSync() / (1024 * 1024))
                        .toStringAsFixed(2);

                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf,
                          color: Color(0xFFFF6D00)),
                      title: Text(nombre),
                      subtitle: Text('$mb MB',
                          style: const TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VisorPdfScreen(
                              rutaArchivo: archivo.path,
                              titulo: nombre,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}