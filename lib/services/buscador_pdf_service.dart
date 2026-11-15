import 'dart:io';
import 'package:dio/dio.dart';

class ManualPdfRemoto {
  final String identifier;
  final String titulo;
  final String autor;
  final String urlPdfDirecta;

  const ManualPdfRemoto({
    required this.identifier,
    required this.titulo,
    required this.autor,
    required this.urlPdfDirecta,
  });
}

class BuscadorPdfService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'User-Agent': 'AegisNode-OfflineApp/1.0 (https://github.com)',
      'Accept': 'application/json',
    },
  ));

  static String _detectarIdiomaIso3() {
    final lang2 = Platform.localeName.split('_').first.toLowerCase();
    const mapa = {
      'es': 'spa',
      'en': 'eng',
      'pt': 'por',
      'fr': 'fra',
      'it': 'ita',
      'de': 'deu',
    };
    return mapa[lang2] ?? 'spa';
  }

  static Future<List<ManualPdfRemoto>> buscarManualesPdf(String consulta) async {
    if (consulta.trim().length < 2) return [];
    final idioma = _detectarIdiomaIso3();

    // Consulta la API abierta de Internet Archive filtrando solo documentos con PDF disponible
    final querySql =
        '(${consulta.trim()}) AND mediatype:(texts) AND format:(Text PDF) AND language:($idioma OR eng)';


    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': querySql,
      'fl[]': ['identifier', 'title', 'creator'],
      'sort[]': 'downloads desc',
      'rows': '20',
      'output': 'json',
    });

    final res = await _dio.get<Map<String, dynamic>>(uri.toString());
    final responseObj = res.data?['response'] as Map<String, dynamic>?;
    final docs = (responseObj?['docs'] as List<dynamic>?) ?? [];

    final List<ManualPdfRemoto> resultados = [];
    for (final d in docs) {
      final map = d as Map<String, dynamic>;
      final id = map['identifier']?.toString() ?? '';
      if (id.isEmpty) continue;

      final tituloRaw = map['title'];
      final titulo = tituloRaw is List
          ? tituloRaw.join(' ')
          : (tituloRaw?.toString() ?? id);

      final creatorRaw = map['creator'];
      final autor = creatorRaw is List
          ? creatorRaw.join(', ')
          : (creatorRaw?.toString() ?? 'Dominio Público / Archivo Abierto');

      // Resolvemos el nombre exacto del archivo .pdf dentro de la metadata del ítem
      final urlPdf = await _resolverArchivoPdfDeItem(id);
      if (urlPdf != null) {
        resultados.add(ManualPdfRemoto(
          identifier: id,
          titulo: titulo,
          autor: autor,
          urlPdfDirecta: urlPdf,
        ));
      }
      if (resultados.length >= 10) break;
    }

    return resultados;
  }

  static Future<String?> _resolverArchivoPdfDeItem(String identifier) async {
    try {
      final metaUri = Uri.https('archive.org', '/metadata/$identifier/files');
      final res = await _dio.get<Map<String, dynamic>>(metaUri.toString());
      final files = (res.data?['result'] as List<dynamic>?) ?? [];

      for (final f in files) {
        final fileMap = f as Map<String, dynamic>;
        final name = fileMap['name']?.toString() ?? '';
        if (name.toLowerCase().endsWith('.pdf')) {
          return Uri.https('archive.org', '/download/$identifier/$name')
              .toString();
        }
      }
    } catch (_) {}
    return null;
  }
}
