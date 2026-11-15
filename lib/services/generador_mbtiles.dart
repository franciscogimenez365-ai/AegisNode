import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class GeneradorMbtilesService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'PocketAEGIS-EmergencyApp/1.0 (https://github.com)',
      'Accept': 'image/png,image/*;q=0.8',
    },
  ));

  int _lonToTileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  int _latToTileY(double lat, int zoom) {
    final rad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) /
            2.0 *
            (1 << zoom))
        .floor();
  }

  bool _esPngValido(List<int>? bytes) {
    if (bytes == null || bytes.length < 100) return false;
    // Firma binaria oficial de archivos PNG: 89 50 4E 47
    return bytes.first == 0x89 &&
        bytes.elementAt(1) == 0x50 &&
        bytes.elementAt(2) == 0x4E &&
        bytes.elementAt(3) == 0x47;
  }
  Future<void> generarRegionMbtiles({
    required String rutaDestino,
    required String nombreMapa,
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int minZoom,
    required int maxZoom,
    required CancelToken cancelToken,
    required Function(double progreso) onProgreso,
  }) async {
    final archivoTemp = File('$rutaDestino.tmp');
    if (await archivoTemp.exists()) await archivoTemp.delete();

    final db = sqlite.sqlite3.open(archivoTemp.path);
    int mosaicosGuardados = 0;

    try {
      db.execute('''
        CREATE TABLE metadata (name text, value text);
        CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
        CREATE UNIQUE INDEX tile_index on tiles (zoom_level, tile_column, tile_row);
      ''');

      final centerLat = (minLat + maxLat) / 2;
      final centerLon = (minLon + maxLon) / 2;

      db.execute("INSERT INTO metadata VALUES ('name', '$nombreMapa');");
      db.execute("INSERT INTO metadata VALUES ('format', 'png');");
      db.execute("INSERT INTO metadata VALUES ('version', '1.3');");
      db.execute("INSERT INTO metadata VALUES ('minzoom', '$minZoom');");
      db.execute("INSERT INTO metadata VALUES ('maxzoom', '$maxZoom');");
      db.execute("INSERT INTO metadata VALUES ('center', '$centerLon,$centerLat,$minZoom');");

      final List<List<int>> cola = [];
      for (int z = minZoom; z <= maxZoom; z++) {
        final xMin = _lonToTileX(minLon, z).clamp(0, (1 << z) - 1);
        final xMax = _lonToTileX(maxLon, z).clamp(0, (1 << z) - 1);
        final yMin = _latToTileY(maxLat, z).clamp(0, (1 << z) - 1);
        final yMax = _latToTileY(minLat, z).clamp(0, (1 << z) - 1);

        for (int x = xMin; x <= xMax; x++) {
          for (int y = yMin; y <= yMax; y++) {
            cola.add([z, x, y]);
          }
        }
      }

      final stmt = db.prepare(
          'INSERT OR REPLACE INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)');

      // Descargar en lotes de 4 mosaicos simultáneos para mayor velocidad
      const int lote = 4;
      for (int i = 0; i < cola.length; i += lote) {
        if (cancelToken.isCancelled) throw Exception('Cancelado');
        final fin = (i + lote < cola.length) ? i + lote : cola.length;
        final sublista = cola.sublist(i, fin);

        await Future.wait(sublista.map((coord) async {
          final z = coord.first;
          final x = coord.elementAt(1);
          final y = coord.elementAt(2);
          final uri = Uri.https('tile.openstreetmap.org', '/$z/$x/$y.png');

          try {
            final res = await _dio.get<List<int>>(
              uri.toString(),
              options: Options(responseType: ResponseType.bytes),
              cancelToken: cancelToken,
            );
            if (_esPngValido(res.data)) {
              final tmsY = ((1 << z) - 1) - y;
              stmt.execute([z, x, tmsY, res.data!]);
              mosaicosGuardados++;
            }
          } catch (_) {}
        }));

        onProgreso(fin / cola.length);
        await Future.delayed(const Duration(milliseconds: 50));
      }
      stmt.close();
    } finally {
      db.close();
    }

    if (mosaicosGuardados == 0) {
      if (await archivoTemp.exists()) await archivoTemp.delete();
      throw Exception('No se pudieron descargar mosaicos PNG válidos. Verifica tu conexión.');
    }

    final archivoFinal = File(rutaDestino);
    if (await archivoFinal.exists()) await archivoFinal.delete();
    await archivoTemp.rename(rutaDestino);
  }
}
