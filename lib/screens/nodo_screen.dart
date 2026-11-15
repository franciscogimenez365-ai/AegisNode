import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/ble_mesh_service.dart';
import '../services/mesh_chat_service.dart';
import '../services/nodo_config_service.dart';
import '../services/servidor_local.dart';

class NodoScreen extends StatefulWidget {
  final String rutaBase;
  final void Function(double lat, double lon)? onAbrirCoordenada;
  const NodoScreen({super.key, required this.rutaBase, this.onAbrirCoordenada});

  @override
  State<NodoScreen> createState() => _NodoScreenState();
}

class _NodoScreenState extends State<NodoScreen> {
  final ServidorLocalService _servidorWifi = ServidorLocalService();
  final TextEditingController _msgCtrl = TextEditingController();
  NodoConfig _config = NodoConfig();
  bool _bleActivo = false;
  bool _wifiActivo = false;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    final c = await NodoConfigService.cargar();
    if (mounted) setState(() => _config = c);
  }

  Future<void> _toggleMallaBle(bool activar) async {
    if (activar) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.notification,
      ].request();

      await BleMeshService.iniciarMalla(_config);
    } else {
      await BleMeshService.detenerMalla();
    }
    if (mounted) setState(() => _bleActivo = activar);
  }

  Future<void> _togglePortalWifi(bool activar) async {
    if (activar) {
      await _servidorWifi.iniciarServidor(widget.rutaBase);
      await WakelockPlus.enable();
    } else {
      await _servidorWifi.detenerServidor();
      await WakelockPlus.disable();
    }
    if (mounted) setState(() => _wifiActivo = activar);
  }

  Future<void> _enviarMensaje() async {
    if (_config.alias.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFFF6D00),
          content: Text(
            'Configura tu indicativo o alias antes de enviar mensajes.',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      _abrirConfiguracionNodo();
      return;
    }

    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty) return;
    _msgCtrl.clear();


    String? gpsStr;
    if (_config.compartirGps) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 3)),
        );
        gpsStr =
            '${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}';
      } catch (_) {}
    }

    await MeshChatService.publicarMensajeLocal(
      autor: _config.alias,
      texto: texto,
      ttlInicial: _config.ttlMaximo,
      gps: gpsStr,
    );
  }
  void _abrirConfiguracionNodo() {
    final aliasCtrl = TextEditingController(text: _config.alias);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('CONFIGURACIÓN Y PRIVACIDAD DEL NODO',
                    style: TextStyle(
                        color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: aliasCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Indicativo / Alias de Usuario',
                    filled: true,
                    fillColor: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Rol: Nodo Maestro (Punto de Mando)'),
                  subtitle: Text(_config.esMaestro
                      ? 'Coordina red y difusión'
                      : 'Modo Repetidor / Campo (Reenvía saltos)'),
                  value: _config.esMaestro,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) => setModalState(() => _config.esMaestro = v),
                ),
                Text('Saltos máximos en Malla (TTL): ${_config.ttlMaximo}',
                    style: const TextStyle(fontSize: 13)),
                Slider(
                  value: _config.ttlMaximo.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  activeColor: const Color(0xFFFF6D00),
                  label: '${_config.ttlMaximo} saltos',
                  onChanged: (v) =>
                      setModalState(() => _config.ttlMaximo = v.toInt()),
                ),
                const Text('Perfil de Energía (Ahorro de Batería):',
                    style: TextStyle(fontSize: 13)),
                DropdownButton<PerfilEnergiaMesh>(
                  value: _config.perfilEnergia,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  items: const [
                    DropdownMenuItem(
                        value: PerfilEnergiaMesh.ultraAhorro,
                        child: Text('Ultra-Ahorro (Escucha cada 45s)')),
                    DropdownMenuItem(
                        value: PerfilEnergiaMesh.equilibrado,
                        child: Text('Equilibrado (Escucha cada 12s)')),
                    DropdownMenuItem(
                        value: PerfilEnergiaMesh.rescateActivo,
                        child: Text('Rescate Activo (Continuo)')),
                  ],
                  onChanged: (p) {
                    if (p != null) {
                      setModalState(() => _config.perfilEnergia = p);
                    }
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Activar Chat de Emergencia'),
                  value: _config.chatActivo,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) => setModalState(() => _config.chatActivo = v),
                ),
                SwitchListTile(
                  title: const Text('Compartir mi Ubicación GPS'),
                  subtitle: const Text('Adjunta coordenadas a tus mensajes'),
                  value: _config.compartirGps,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) =>
                      setModalState(() => _config.compartirGps = v),
                ),
                SwitchListTile(
                  title: const Text('Compartir Archivos en Portal Wi-Fi'),
                  value: _config.compartirArchivos,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) =>
                      setModalState(() => _config.compartirArchivos = v),
                ),
                SwitchListTile(
                  title: const Text('Notificar mensajes entrantes'),
                  subtitle: const Text('Emite alerta en segundo plano al recibir'),
                  value: _config.notificarMensajes,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) =>
                     setModalState(() => _config.notificarMensajes = v),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black),
               onPressed: () async {
                 _config.alias = aliasCtrl.text.trim();
                 await NodoConfigService.guardar(_config);
                 if (_bleActivo) {
                   await BleMeshService.detenerMalla();
                   await BleMeshService.iniciarMalla(_config);
                 }
                 if (!ctx.mounted) return;
                 Navigator.pop(ctx);
                 setState(() {});
               },
                  child: const Text('GUARDAR CONFIGURACIÓN',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF121212),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_config.alias.isEmpty ? "SIN ALIAS" : _config.alias} • ${_config.esMaestro ? "MAESTRO" : "REPETIDOR"} (TTL ${_config.ttlMaximo})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E676),
                          fontSize: 13),
                    ),
                    StreamBuilder<int>(
                      stream: BleMeshService.streamVecinos,
                      initialData: BleMeshService.cantidadNodosVecinos,
                      builder: (context, snap) {
                        final vecinos = snap.data ?? 0;
                        return Text(
                          _bleActivo
                              ? 'Malla BLE Activa • Vecinos: $vecinos'
                              : 'Malla BLE Apagada (Ahorro máximo)',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Switch(
                value: _bleActivo,
                activeThumbColor: const Color(0xFF00E676),
                onChanged: _toggleMallaBle,
              ),
              IconButton(
                icon: const Icon(Icons.tune, color: Color(0xFFFF6D00)),
                tooltip: 'Configurar Privacidad y Energía',
                onPressed: _abrirConfiguracionNodo,
              ),
            ],
          ),
        ),
        ExpansionTile(
          backgroundColor: const Color(0xFF121212),
          collapsedBackgroundColor: const Color(0xFF121212),
          leading: Icon(Icons.wifi_tethering,
              color: _wifiActivo ? const Color(0xFF00E676) : Colors.grey),
          title: const Text('Portal Web Wi-Fi (Opcional / Archivos)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          trailing: Switch(
            value: _wifiActivo,
            activeThumbColor: const Color(0xFFFF6D00),
            onChanged: _togglePortalWifi,
          ),
          children: [
            if (_wifiActivo)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(
                          data: _servidorWifi.urlAcceso, size: 130),
                    ),
                    const SizedBox(height: 6),
                    Text(_servidorWifi.urlAcceso,
                        style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
          ],
        ),
        Expanded(
          child: !_config.chatActivo
              ? const Center(
                  child: Text('Chat desactivado en Configuración del Nodo',
                      style: TextStyle(color: Colors.grey)))
              : StreamBuilder<List<MensajeMesh>>(
                  stream: MeshChatService.streamMensajes,
                  initialData: MeshChatService.mensajes,
                  builder: (context, snapshot) {
                    final msgs = snapshot.data ?? [];
                    if (msgs.isEmpty) {
                      return const Center(
                        child: Text(
                            'Sin mensajes en la malla.\nEnciende BLE o Wi-Fi para comunicarte.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey)),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs.elementAt(i);
                        return Card(
                          color: const Color(0xFF121212),
                          child: ListTile(
                            title: Row(
                              children: [
                                Text(m.autor,
                                    style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                        const Spacer(),
                                        Text(
                                          'Saltos: ${m.saltosRecorridos} | TTL: ${m.ttl}',
                                          style: const TextStyle(
                                            color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.texto),
                                if (m.gps != null)
                                  InkWell(
                                    onTap: () {
                                      final partes = m.gps!.split(',');
                                      if (partes.length == 2) {
                                        final lat = double.tryParse(partes.first.trim());
                                        final lon = double.tryParse(partes.elementAt(1).trim());
                                        if (lat != null && lon != null) {
                                          widget.onAbrirCoordenada?.call(lat, lon);
                                        }
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '📍 GPS: ${m.gps} (Tocar para ver en mapa)',
                                        style: const TextStyle(
                                          color: Color(0xFFFF6D00),
                                          fontSize: 11,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),

                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
              ),
        ),
        if (_config.chatActivo)
        Container(
          color: const Color(0xFF121212),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    onSubmitted: (_) => _enviarMensaje(),
                    decoration: const InputDecoration(
                      hintText: 'Mensaje de emergencia a la malla...',
                      border: InputBorder.none,
                    ),
                  ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFFFF6D00)),
                onPressed: _enviarMensaje,
              ),
            ],
          ),
        ),
      ],
    );
  }
}









