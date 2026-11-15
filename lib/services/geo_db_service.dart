import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class LugarGeo {
  final String continente;
  final String pais;
  final String provincia;
  final String ciudad;
  final double lat;
  final double lon;

  const LugarGeo({
    required this.continente,
    required this.pais,
    required this.provincia,
    required this.ciudad,
    required this.lat,
    required this.lon,
  });

  // Calcula un cuadrante de ~45x45 km alrededor de la ciudad para Zoom 10-15
  List<double> get bboxNivelCalle => [
        lat - 0.22,
        lat + 0.22,
        lon - 0.25,
        lon + 0.25,
      ];
}

class GeoDbService {
  static Database? _db;

  static Future<Database> obtenerDb() async {
    if (_db != null) return _db!;

    final dir = await getApplicationSupportDirectory();
    final dbPath = '${dir.path}/geografia_mundial.db';
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      final data = await rootBundle.load('assets/db/geografia_mundial.db');
      final bytes = data.buffer.asUint8List();
      await dbFile.writeAsBytes(bytes, flush: true);
    }

    _db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    return _db!;
  }

  // GPS Inverso 100% Offline: encuentra la ciudad más cercana en SQLite
  static Future<LugarGeo?> detectarCiudadActualPorGps() async {
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );

      final db = await obtenerDb();
      final res = db.select(
        '''
        SELECT continente, pais, provincia, ciudad, lat, lon
        FROM lugares
        ORDER BY ((lat - ?) * (lat - ?) + (lon - ?) * (lon - ?)) ASC
        LIMIT 1;
        ''',
        [pos.latitude, pos.latitude, pos.longitude, pos.longitude],
      );

      if (res.isEmpty) return null;
      final row = res.first;
      return LugarGeo(
        continente: row['continente'].toString(),
        pais: row['pais'].toString(),
        provincia: row['provincia'].toString(),
        ciudad: row['ciudad'].toString(),
        lat: (row['lat'] as num).toDouble(),
        lon: (row['lon'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
  static Future<List<String>> listarContinentes() async {
    final db = await obtenerDb();
    final res = db.select(
        'SELECT DISTINCT continente FROM lugares ORDER BY continente ASC;');
    return res.map((r) => r['continente'].toString()).toList();
  }

  static Future<List<String>> listarPaises(String continente) async {
    final db = await obtenerDb();
    final res = db.select(
      'SELECT DISTINCT pais FROM lugares WHERE continente = ? ORDER BY pais ASC;',
      [continente],
    );
    return res.map((r) => r['pais'].toString()).toList();
  }

  static Future<List<String>> listarProvincias(
      String continente, String pais) async {
    final db = await obtenerDb();
    final res = db.select(
      'SELECT DISTINCT provincia FROM lugares WHERE continente = ? AND pais = ? ORDER BY provincia ASC;',
      [continente, pais],
    );
    return res.map((r) => r['provincia'].toString()).toList();
  }

  static Future<List<LugarGeo>> listarCiudades(
      String continente, String pais, String provincia) async {
    final db = await obtenerDb();
    final res = db.select(
      '''
      SELECT continente, pais, provincia, ciudad, lat, lon
      FROM lugares
      WHERE continente = ? AND pais = ? AND provincia = ?
      ORDER BY poblacion DESC, ciudad ASC;
      ''',
      [continente, pais, provincia],
    );
    return res
        .map((r) => LugarGeo(
              continente: r['continente'].toString(),
              pais: r['pais'].toString(),
              provincia: r['provincia'].toString(),
              ciudad: r['ciudad'].toString(),
              lat: (r['lat'] as num).toDouble(),
              lon: (r['lon'] as num).toDouble(),
            ))
        .toList();
  }

  static Future<List<LugarGeo>> buscarCiudadesPorNombre(String query) async {
    if (query.trim().length < 2) return [];
    final db = await obtenerDb();
    final res = db.select(
      '''
      SELECT continente, pais, provincia, ciudad, lat, lon
      FROM lugares
      WHERE ciudad LIKE ?
      ORDER BY poblacion DESC
      LIMIT 25;
      ''',
      ['%${query.trim()}%'],
    );
    return res
        .map((r) => LugarGeo(
              continente: r['continente'].toString(),
              pais: r['pais'].toString(),
              provincia: r['provincia'].toString(),
              ciudad: r['ciudad'].toString(),
              lat: (r['lat'] as num).toDouble(),
              lon: (r['lon'] as num).toDouble(),
            ))
        .toList();
  }
    static Future<List<double>?> obtenerBboxPais(String pais) async {
    final db = await obtenerDb();
    final res = db.select(
      '''
      SELECT MIN(lat) as minLat, MAX(lat) as maxLat, MIN(lon) as minLon, MAX(lon) as maxLon
      FROM lugares
      WHERE pais = ?;
      ''',
      [pais],
    );
    if (res.isEmpty || res.first['minLat'] == null) return null;
    final row = res.first;
    return [
      (row['minLat'] as num).toDouble() - 0.5,
      (row['maxLat'] as num).toDouble() + 0.5,
      (row['minLon'] as num).toDouble() - 0.5,
      (row['maxLon'] as num).toDouble() + 0.5,
    ];
  }

}
