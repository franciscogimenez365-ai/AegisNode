import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/biblioteca_screen.dart';
import 'screens/descargas_screen.dart';
import 'screens/mapas_screen.dart';
import 'screens/nodo_screen.dart';
import 'screens/wiki_screen.dart';
import 'services/ble_mesh_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AegisNodeApp());
}

class AegisNodeApp extends StatelessWidget {
  const AegisNodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AegisNode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6D00),
          secondary: Color(0xFF00E676),
          surface: Color(0xFF121212),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _indiceActual = 0;
  String? _rutaBase;
  LatLng? _coordenadaObjetivo;

  @override
  void initState() {
    super.initState();
    _inicializarAlmacenamiento();
    BleMeshService.onAbrirPestanaNodo = () {
      if (mounted) {
        setState(() => _indiceActual = 0);
      }
    };
  }

  Future<void> _inicializarAlmacenamiento() async {
    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.location,
    ].request();

    Directory baseDir;
    try {
      baseDir = Directory('/storage/emulated/0/AegisNode');
      if (!await baseDir.exists()) {
        final legado = Directory('/storage/emulated/0/AegisNode');
        if (await legado.exists()) {
          baseDir = legado;
        } else {
          await baseDir.create(recursive: true);
        }
      }
    } catch (_) {
      final appDir = await getApplicationDocumentsDirectory();
      baseDir = Directory('${appDir.path}/AegisNode');
      if (!await baseDir.exists()) await baseDir.create(recursive: true);
    }

    for (final sub in ['manuales', 'mapas', 'wikis']) {
      final subDir = Directory('${baseDir.path}/$sub');
      if (!await subDir.exists()) await subDir.create(recursive: true);
    }

    if (mounted) {
      setState(() => _rutaBase = baseDir.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rutaBase == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6D00)),
        ),
      );
    }

    final pantallas = [
      NodoScreen(
        rutaBase: _rutaBase!,
        onAbrirCoordenada: (lat, lon) {
          setState(() {
            _coordenadaObjetivo = LatLng(lat, lon);
            _indiceActual = 2;
          });
        },
      ),
      BibliotecaScreen(rutaManuales: '$_rutaBase/manuales'),
      MapasScreen(
        rutaMapas: '$_rutaBase/mapas',
        coordenadaDestino: _coordenadaObjetivo,
      ),
      WikiScreen(rutaWikis: '$_rutaBase/wikis'),
      DescargasScreen(rutaBase: _rutaBase!),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AegisNode // OFFLINE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 17,
          ),
        ),
        backgroundColor: const Color(0xFF121212),
      ),
      body: IndexedStack(
        index: _indiceActual,
        children: pantallas,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceActual,
        onTap: (i) {
          setState(() => _indiceActual = i);
          if (i == 0) {
            BleMeshService.limpiarNotificaciones();
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF121212),
        selectedItemColor: const Color(0xFFFF6D00),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.hub), label: 'Nodo'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Manuales'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapas'),
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Wiki ZIM'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Preparar'),
        ],
      ),
    );
  }
}
