import 'dart:io';
import 'package:flutter/material.dart';
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
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _cargarArchivos,
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
              ? const Center(
                  child: Text(
                    'No hay manuales PDF en /PocketAegis/manuales.\nCopia archivos allí y toca recargar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
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