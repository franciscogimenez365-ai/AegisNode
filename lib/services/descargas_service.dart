import 'dart:io';
import 'package:dio/dio.dart';
import 'generador_mbtiles.dart';
import 'geo_db_service.dart';

class RecursoOffline {
  final String id;
  final String titulo;
  final String subcategoria;
  final String descripcion;
  final String categoriaCarpeta; // 'wikis', 'mapas', 'manuales'
  final String nombreArchivoDestino;
  final String tamanoAprox;
  final String? regionGps;
  final String? kiwixQuery;
  final String? hostGithub;
  final String? pathGithub;
  final String? urlDirecta;
  final List<double>? bboxZoom; // <-- 1. AGREGA ESTA LÍNEA AQUÍ

  const RecursoOffline({
    required this.id,
    required this.titulo,
    required this.subcategoria,
    required this.descripcion,
    required this.categoriaCarpeta,
    required this.nombreArchivoDestino,
    required this.tamanoAprox,
    this.regionGps,
    this.kiwixQuery,
    this.hostGithub,
    this.pathGithub,
    this.urlDirecta,
    this.bboxZoom, // <-- 2. Y AGREGA ESTA OTRA LÍNEA EN EL CONSTRUCTOR
  });
}

class DescargasService {
  final Dio _dio = Dio(BaseOptions(
    followRedirects: true,
    maxRedirects: 8,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 20),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) PocketAEGIS/1.0',
      'Accept': '*/*',
    },
  ));


  static List<RecursoOffline> obtenerWikisDinamicasPorIdioma() {
    final lang2 = Platform.localeName.split('_').first.toLowerCase();
    final lang3 = detectarIdiomaKiwix();
    final esEspanol = lang2 == 'es';

    return [
      RecursoOffline(
        id: 'wikimed_$lang3',
        titulo: esEspanol
            ? 'WikiMed (Enciclopedia Médica)'
            : 'WikiMed (Offline Medical Encyclopedia)',
        subcategoria: esEspanol
            ? 'Medicina y Primeros Auxilios ($lang3)'
            : 'Medicine & First Aid ($lang3)',
        descripcion: esEspanol
            ? 'Enfermedades, fármacos, primeros auxilios y saneamiento.'
            : 'Diseases, medications, emergency care and sanitation.',
        categoriaCarpeta: 'wikis',
        nombreArchivoDestino: 'wikimed_$lang3.zim',
        tamanoAprox: '~450 MB',
        kiwixQuery: 'medicine_wiki',
      ),
      RecursoOffline(
        id: 'wiki_top_$lang3',
        titulo: esEspanol
            ? 'Wikipedia Esencial (Top Artículos)'
            : 'Wikipedia Essential (Top Articles)',
        subcategoria: esEspanol
            ? 'Referencia General ($lang3)'
            : 'General Reference ($lang3)',
        descripcion: esEspanol
            ? 'Artículos fundamentales de ciencia, física, química e historia.'
            : 'Core articles on science, physics, chemistry and history.',
        categoriaCarpeta: 'wikis',
        nombreArchivoDestino: 'wikipedia_${lang3}_top.zim',
        tamanoAprox: '~1.2 GB',
        kiwixQuery: 'wikipedia_top',
      ),
      RecursoOffline(
        id: 'ifixit_$lang3',
        titulo: esEspanol
            ? 'iFixit (Guías de Reparación)'
            : 'iFixit (Repair Manuals)',
        subcategoria: esEspanol
            ? 'Mantenimiento y Hardware ($lang3)'
            : 'Hardware & Equipment Repair ($lang3)',
        descripcion: esEspanol
            ? 'Manuales paso a paso para reparar electrónica, baterías y equipos.'
            : 'Step-by-step guides to fix electronics, batteries and tools.',
        categoriaCarpeta: 'wikis',
        nombreArchivoDestino: 'ifixit_$lang3.zim',
        tamanoAprox: '~1.1 GB',
        kiwixQuery: 'ifixit',
      ),
      RecursoOffline(
        id: 'wikivoyage_$lang3',
        titulo: esEspanol
            ? 'Wikivoyage (Guías de Terreno y Rutas)'
            : 'Wikivoyage (Field & Travel Guides)',
        subcategoria: esEspanol
            ? 'Navegación y Supervivencia ($lang3)'
            : 'Navigation & Regional Info ($lang3)',
        descripcion: esEspanol
            ? 'Geografía, clima, transporte, agua y seguridad por regiones.'
            : 'Geography, climate, transit and safety across regions.',
        categoriaCarpeta: 'wikis',
        nombreArchivoDestino: 'wikivoyage_$lang3.zim',
        tamanoAprox: '~250 MB',
        kiwixQuery: 'wikivoyage',
      ),
      RecursoOffline(
        id: 'wikibooks_$lang3',
        titulo: esEspanol
            ? 'Wikilibros (Manuales Prácticos)'
            : 'Wikibooks (Practical Textbooks)',
        subcategoria: esEspanol
            ? 'Educación y Oficios ($lang3)'
            : 'Technical & Practical Guides ($lang3)',
        descripcion: esEspanol
            ? 'Manuales técnicos de agricultura, cocina, química y mecánica.'
            : 'Practical manuals on agriculture, chemistry and mechanics.',
        categoriaCarpeta: 'wikis',
        nombreArchivoDestino: 'wikibooks_$lang3.zim',
        tamanoAprox: '~350 MB',
        kiwixQuery: 'wikibooks',
      ),
      RecursoOffline(
        id: 'gutenberg_$lang3',
        titulo: esEspanol
            ? 'Proyecto Gutenberg (Biblioteca Clásica)'
            : 'Project Gutenberg (Offline Library)',
        subcategoria: esEspanol
            ? 'Libros Offline ($lang3)'
            : 'Free Books Offline ($lang3)',
        descripcion: esEspanol
            ? 'Miles de libros libres para lectura sin conexión.'
            : 'Thousands of free public-domain books for offline reading.',
        categoriaCarpeta: 'wikis',
        nombreArchivoDestino: 'gutenberg_$lang3.zim',
        tamanoAprox: '~900 MB',
        kiwixQuery: 'gutenberg',
      ),
    ];
  }

  // Detecta el código de idioma de 3 letras para Kiwix (spa, eng, por, fra, ita...)
  static String detectarIdiomaKiwix() {
    final lang2 = Platform.localeName.split('_').first.toLowerCase();
    const mapaIdiomas = {
      'es': 'spa',
      'en': 'eng',
      'pt': 'por',
      'fr': 'fra',
      'it': 'ita',
      'de': 'deu',
    };
    return mapaIdiomas[lang2] ?? 'spa';
  }

  static Future<List<RecursoOffline>> obtenerMapasDinamicosPorGps() async {
    final lugar = await GeoDbService.detectarCiudadActualPorGps();
    final List<RecursoOffline> lista = [];

    if (lugar != null) {
      final bCiudad = lugar.bboxNivelCalle;
      lista.add(RecursoOffline(
        id: 'gps_ciudad_actual',
        titulo: '${lugar.ciudad} (Nivel Calle Zoom 10–17)',
        subcategoria: '${lugar.provincia}, ${lugar.pais} • Detectado por GPS',
        descripcion: 'Detalle callejero (~45x45 km) alrededor de tu ubicación actual.',
        categoriaCarpeta: 'mapas',
        nombreArchivoDestino:
            '${lugar.ciudad.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_calles.mbtiles',
        tamanoAprox: '~110–150 MB',
        regionGps: lugar.continente,
        bboxZoom: [bCiudad.first, bCiudad.elementAt(1), bCiudad.elementAt(2), bCiudad.elementAt(3), 10, 17],
      ));

      final bPais = await GeoDbService.obtenerBboxPais(lugar.pais);
      if (bPais != null) {
        lista.add(RecursoOffline(
          id: 'gps_pais_actual',
          titulo: '${lugar.pais} Completo (Rutas Zoom 5–8)',
          subcategoria: '${lugar.continente} • Cobertura Nacional',
          descripcion: 'Rutas nacionales, ciudades principales y geografía de ${lugar.pais}.',
          categoriaCarpeta: 'mapas',
          nombreArchivoDestino:
              '${lugar.pais.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_rutas.mbtiles',
          tamanoAprox: '~25–50 MB',
          regionGps: lugar.continente,
          bboxZoom: [bPais.first, bPais.elementAt(1), bPais.elementAt(2), bPais.elementAt(3), 5, 8],
        ));
      }
    }

    lista.add(const RecursoOffline(
      id: 'mapa_mundial_z0_5',
      titulo: 'Mapa Mundial Base (Zoom 0–5)',
      subcategoria: 'Cobertura Global Offline',
      descripcion: 'Todo el planeta con países, fronteras, costas y capitales.',
      categoriaCarpeta: 'mapas',
      nombreArchivoDestino: 'mundial_base.mbtiles',
      tamanoAprox: '~14 MB',
      regionGps: 'Global',
      bboxZoom: [-85.0, 85.0, -180.0, 180.0, 0, 5],
    ));

    return lista;
  }



static const List<RecursoOffline> catalogoManualesPdf = [];



  Future<String> resolverUrlKiwixOpds(String consulta) async {
    final idioma = detectarIdiomaKiwix();
    final Map<String, String> params =
        (consulta == 'medicine_wiki' || consulta == 'wikipedia_top')
            ? {
                'category': 'wikipedia',
                'lang': idioma,
                'count': '30',
              }
            : {
                'q': consulta,
                'lang': idioma,
                'count': '15',
              };

    final uri = Uri.https('library.kiwix.org', '/catalog/v2/entries', params);
    final response = await _dio.get<String>(uri.toString());
    final xml = response.data ?? '';

    final regex = RegExp(r'href="(https?://[^"]+\.zim)(?:\.meta4)?"');
    final enlaces = regex.allMatches(xml).map((m) => m.group(1)!).toList();

    if (enlaces.isEmpty) {
      throw Exception('No se encontró paquete activo en Kiwix para "$consulta"');
    }

    if (consulta == 'medicine_wiki') {
      final medMatch = enlaces.where((u) => u.contains('_medicine_')).toList();
      if (medMatch.isNotEmpty) return medMatch.first;
    }

    if (consulta == 'wikipedia_top') {
      final topMatch = enlaces
          .where((u) => u.contains('_top_') || u.contains('_all_nopic'))
          .toList();
      if (topMatch.isNotEmpty) return topMatch.first;
    }

    final filtrados = enlaces.where((u) => !u.contains('/ted/')).toList();
    return filtrados.isNotEmpty ? filtrados.first : enlaces.first;
  }
  Future<List<RecursoOffline>> buscarPaquetesKiwix(String consulta) async {
    if (consulta.trim().length < 2) return [];
    final idiomaLocal = detectarIdiomaKiwix();

    Future<List<RecursoOffline>> consultarConLang(String lang) async {
      final uri = Uri.https('library.kiwix.org', '/catalog/v2/entries', {
        'q': consulta.trim(),
        'lang': lang,
        'count': '15',
      });

      final response = await _dio.get<String>(uri.toString());
      final xml = response.data ?? '';

      final entryRegex = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
      final titleRegex = RegExp(r'<title>(.*?)</title>', dotAll: true);
      final summaryRegex = RegExp(r'<summary>(.*?)</summary>', dotAll: true);
      final hrefRegex = RegExp(r'href="(https?://[^"]+\.zim)(?:\.meta4)?"');

      final List<RecursoOffline> lista = [];
      for (final m in entryRegex.allMatches(xml)) {
        final bloque = m.group(1) ?? '';
        final hrefMatch = hrefRegex.firstMatch(bloque);
        if (hrefMatch == null) continue;

        final urlZim = hrefMatch.group(1)!;
        final titulo = (titleRegex.firstMatch(bloque)?.group(1) ?? 'Paquete ZIM')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        final resumen = (summaryRegex.firstMatch(bloque)?.group(1) ?? '')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        final nombreArchivo = Uri.parse(urlZim).pathSegments.last;

        lista.add(RecursoOffline(
          id: 'search_$nombreArchivo',
          titulo: titulo,
          subcategoria: 'Catálogo Kiwix ($lang)',
          descripcion: resumen.isNotEmpty ? resumen : nombreArchivo,
          categoriaCarpeta: 'wikis',
          nombreArchivoDestino: nombreArchivo,
          tamanoAprox: 'Paquete ZIM',
          urlDirecta: urlZim,
        ));
      }
      return lista;
    }

    final resultados = await consultarConLang(idiomaLocal);
    if (resultados.length < 3 && idiomaLocal != 'eng') {
      final enIngles = await consultarConLang('eng');
      resultados.addAll(enIngles);
    }
    return resultados;
  }


  Future<bool> _validarIntegridadArchivo(File archivo, String categoria) async {
    if (!await archivo.exists()) return false;
    final len = await archivo.length();
    if (len < 512) return false;

    final raf = await archivo.open();
    final headerBytes = await raf.read(16);
    await raf.close();
    final headerStr = String.fromCharCodes(headerBytes);

    if (categoria == 'mapas') {
      return headerStr.startsWith('SQLite format 3');
    } else if (categoria == 'manuales') {
      return headerStr.startsWith('%PDF');
    } else if (categoria == 'wikis') {
      return headerBytes.length >= 4 &&
          headerBytes.first == 0x5A && // Z
          headerBytes.elementAt(1) == 0x49 && // I
          headerBytes.elementAt(2) == 0x4D;   // M
    }
    return true;
  }

  Future<void> descargarRecurso({
    required RecursoOffline recurso,
    required String rutaDestino,
    required CancelToken cancelToken,
    required Function(double progreso) onProgreso,
  }) async {
    // <-- AQUÍ MISMO VA EL BLOQUE DE MAPAS:
    if (recurso.bboxZoom != null) {
      double minLat = recurso.bboxZoom!.first;
      double maxLat = recurso.bboxZoom!.elementAt(1);
      double minLon = recurso.bboxZoom!.elementAt(2);
      double maxLon = recurso.bboxZoom!.elementAt(3);
      final minZoom = recurso.bboxZoom!.elementAt(4).toInt();
      final maxZoom = recurso.bboxZoom!.elementAt(5).toInt();

      await GeneradorMbtilesService().generarRegionMbtiles(
        rutaDestino: rutaDestino,
        nombreMapa: recurso.titulo,
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
        minZoom: minZoom,
        maxZoom: maxZoom,
        cancelToken: cancelToken,
        onProgreso: onProgreso,
      );
      return;
    }


    String urlFinal = '';

    if (recurso.kiwixQuery != null) {
      urlFinal = await resolverUrlKiwixOpds(recurso.kiwixQuery!);
    } else if (recurso.hostGithub != null && recurso.pathGithub != null) {
      urlFinal = Uri.https(recurso.hostGithub!, recurso.pathGithub!).toString();
    } else if (recurso.urlDirecta != null) {
      urlFinal = recurso.urlDirecta!;
    }

    final archivoTemp = File('$rutaDestino.tmp');
    if (await archivoTemp.exists()) await archivoTemp.delete();

    await _dio.download(
      urlFinal,
      archivoTemp.path,
      cancelToken: cancelToken,
      onReceiveProgress: (recibidos, total) {
        if (total > 0) {
          onProgreso(recibidos / total);
        }
      },
    );

    final esValido =
        await _validarIntegridadArchivo(archivoTemp, recurso.categoriaCarpeta);
    if (!esValido) {
      if (await archivoTemp.exists()) await archivoTemp.delete();
      throw Exception(
          'El servidor no devolvió un archivo ${recurso.categoriaCarpeta} binario válido.');
    }

    final archivoFinal = File(rutaDestino);
    if (await archivoFinal.exists()) await archivoFinal.delete();
    await archivoTemp.rename(rutaDestino);
  }

}
