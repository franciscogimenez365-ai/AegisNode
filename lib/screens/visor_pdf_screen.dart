import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class VisorPdfScreen extends StatelessWidget {
  final String rutaArchivo;
  final String titulo;

  const VisorPdfScreen({
    super.key,
    required this.rutaArchivo,
    required this.titulo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titulo, style: const TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF121212),
      ),
      body: PdfViewer.file(
        rutaArchivo,
        params: const PdfViewerParams(
          backgroundColor: Color(0xFF000000),
        ),
      ),
    );
  }
}