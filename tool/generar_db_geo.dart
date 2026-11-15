import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';

void main() async {
  stdout.writeln('1. Descargando catálogo mundial abierto de GeoNames (cities15000)...');
  final client = HttpClient();

  Future<List<int>> descargarBytes(String path) async {
    final req = await client.getUrl(Uri.https('download.geonames.org', path));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw Exception('Error HTTP ${res.statusCode} al descargar $path');
    }
    return await res.fold<List<int>>([], (a, b) => a..addAll(b));
  }

  final bytes = await descargarBytes('/export/dump/cities15000.zip');

  stdout.writeln('2. Extrayendo datos...');
  final archive = ZipDecoder().decodeBytes(bytes);
  final txtFile = archive.firstWhere((f) => f.name.endsWith('.txt'));
  final lineas = utf8.decode(txtFile.content as List<int>).split('\n');

  final lineasPaises = utf8
      .decode(await descargarBytes('/export/dump/countryInfo.txt'))
      .split('\n');

  final Map<String, Map<String, String>> infoPaises = {};
  const nombresCont = {
    'SA': 'Sudamérica',
    'NA': 'Norteamérica',
    'EU': 'Europa',
    'AS': 'Asia',
    'AF': 'África',
    'OC': 'Oceanía',
    'AN': 'Antártida',
  };

  for (final l in lineasPaises) {
    if (l.startsWith('#') || l.trim().isEmpty) continue;
    final p = l.split('\t');
    if (p.length > 8) {
      infoPaises[p.first] = {
        'nombre': p.elementAt(4),
        'continente': nombresCont[p.elementAt(8)] ?? p.elementAt(8),
      };
    }
  }

  final lineasAdmin = utf8
      .decode(await descargarBytes('/export/dump/admin1CodesASCII.txt'))
      .split('\n');

  final Map<String, String> infoAdmin1 = {};
  for (final l in lineasAdmin) {
    if (l.trim().isEmpty) continue;
    final p = l.split('\t');
    if (p.length >= 2) {
      infoAdmin1[p.first] = p.elementAt(1);
    }
  }

  stdout.writeln('3. Construyendo base de datos SQLite indexada...');
  final dbFile = File('assets/db/geografia_mundial.db');
  if (dbFile.existsSync()) dbFile.deleteSync();

  final db = sqlite3.open(dbFile.path);
  db.execute('''
    CREATE TABLE lugares (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      continente TEXT NOT NULL,
      pais TEXT NOT NULL,
      provincia TEXT NOT NULL,
      ciudad TEXT NOT NULL,
      lat REAL NOT NULL,
      lon REAL NOT NULL,
      poblacion INTEGER NOT NULL
    );
  ''');

  db.execute('BEGIN TRANSACTION;');
  final stmt = db.prepare(
      'INSERT INTO lugares (continente, pais, provincia, ciudad, lat, lon, poblacion) VALUES (?, ?, ?, ?, ?, ?, ?)');

  int count = 0;
  for (final l in lineas) {
    if (l.trim().isEmpty) continue;
    final cols = l.split('\t');
    if (cols.length < 15) continue;

    final ciudad = cols.elementAt(1);
    final lat = double.tryParse(cols.elementAt(4)) ?? 0.0;
    final lon = double.tryParse(cols.elementAt(5)) ?? 0.0;
    final codPais = cols.elementAt(8);
    final codAdmin1 = cols.elementAt(10);
    final poblacion = int.tryParse(cols.elementAt(14)) ?? 0;

    final paisData = infoPaises[codPais];
    if (paisData == null) continue;

    final continente = paisData['continente']!;
    final pais = paisData['nombre']!;
    final provincia = infoAdmin1['$codPais.$codAdmin1'] ?? 'General';

    stmt.execute([continente, pais, provincia, ciudad, lat, lon, poblacion]);
    count++;
  }
  stmt.close();
  db.execute('COMMIT;');

  db.execute('CREATE INDEX idx_jerarquia ON lugares (continente, pais, provincia);');
  db.execute('CREATE INDEX idx_ciudad ON lugares (ciudad);');
  db.execute('VACUUM;');
  db.close();
  client.close();

  final mb = (dbFile.lengthSync() / (1024 * 1024)).toStringAsFixed(2);
  stdout.writeln('¡Listo! Base SQLite creada con $count ciudades mundiales ($mb MB).');
}
