import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
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
  bool _sosActivo = false;
  bool _verCanalPrivado = false;
  Timer? _timerSos;
  static const MethodChannel _sysChannel =
      MethodChannel('com.emergencia.aegis_node/kiwix');


  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }
    @override
  void dispose() {
    _timerSos?.cancel();
    _msgCtrl.dispose();
    super.dispose();
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
      esPrivado: _verCanalPrivado && _config.claveGrupo.trim().isNotEmpty,
      claveGrupo: _config.claveGrupo,
    );
  }
  Future<void> _activarODetenerSos() async {
    if (_sosActivo) {
      _timerSos?.cancel();
      setState(() => _sosActivo = false);
      MeshChatService.publicarAvisoSistema('Baliza SOS desactivada.');
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() => _sosActivo = true);

    // Si la Malla BLE estaba apagada, la encendemos automáticamente
    if (!_bleActivo) {
      await _toggleMallaBle(true);
    }

    await _emitirPulsoSos();
    _timerSos = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_sosActivo) _emitirPulsoSos();
    });
  }

  Future<void> _emitirPulsoSos() async {
    int bateria = -1;
    try {
      bateria = await _sysChannel.invokeMethod<int>('obtenerBateria') ?? -1;
    } catch (_) {}

    String? gpsStr;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 6));
      gpsStr =
          '${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}';
    } catch (_) {}

    final aliasEfectivo =
        _config.alias.trim().isEmpty ? 'NODO-SOS' : _config.alias.trim();
    final batTexto = bateria >= 0 ? ' • BAT: $bateria%' : '';
    final cuerpoSos =
        '🚨 [BALIZA SOS]$batTexto • REQUIERO ASISTENCIA INMEDIATA';

    await MeshChatService.publicarMensajeLocal(
      autor: aliasEfectivo,
      texto: cuerpoSos,
      ttlInicial: 20, // Máximo alcance posible en la malla
      gps: gpsStr,
    );

  }

  
  void _abrirConfiguracionNodo() {
    final aliasCtrl = TextEditingController(text: _config.alias);
    final claveCtrl = TextEditingController(text: _config.claveGrupo);
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
             const SizedBox(height: 10),
             TextField(
               controller: claveCtrl,
               obscureText: true,
               decoration: const InputDecoration(
                 labelText: 'Clave de Grupo AES-256 (Opcional)',
                 hintText: 'Vacío = solo canal abierto comunitario',
                 prefixIcon: Icon(Icons.lock_outline, color: Color(0xFF00E676)),
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
                 _config.claveGrupo = claveCtrl.text.trim();
                 if (_config.claveGrupo.isEmpty) _verCanalPrivado = false;
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
    void _abrirRadarVecinos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final vecinos = BleMeshService.listaVecinosActivos;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RADAR DE NODOS VECINOS (BLE)',
                    style: TextStyle(
                      color: Color(0xFFFF6D00),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${vecinos.length} activos',
                    style: const TextStyle(color: Color(0xFF00E676), fontSize: 12),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              if (vecinos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Ningún nodo vecino detectado en los últimos 25 segundos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...vecinos.map((v) {
                  final haceSeg =
                      DateTime.now().difference(v.ultimaVezVisto).inSeconds;
                  final String calidad;
                  final Color colorSenal;
                  if (v.rssi >= -65) {
                    calidad = 'Señal Fuerte (Cerca)';
                    colorSenal = const Color(0xFF00E676);
                  } else if (v.rssi >= -82) {
                    calidad = 'Señal Media';
                    colorSenal = const Color(0xFFFF6D00);
                  } else {
                    calidad = 'Señal Débil (Al límite)';
                    colorSenal = Colors.redAccent;
                  }

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.radar, color: colorSenal),
                    title: Text(
                      v.alias,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    subtitle: Text(
                      '$calidad • Visto hace ${haceSeg}s',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    trailing: Text(
                      '${v.rssi} dBm',
                      style: TextStyle(
                        color: colorSenal,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }


@override
Widget build(BuildContext context) {
  return Column(
    children: [
      Container(
        color: const Color(0xFF121212),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child:Row(
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
                        InkWell(
                          onTap: _bleActivo ? _abrirRadarVecinos : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: StreamBuilder<int>(
                              stream: BleMeshService.streamVecinos,
                              initialData: BleMeshService.cantidadNodosVecinos,
                              builder: (context, snap) {
                                final cant = snap.data ?? 0;
                                return Text(
                                  _bleActivo
                                      ? 'Malla BLE Activa • Vecinos: $cant (Ver radar ▸)'
                                      : 'Malla BLE Apagada (Ahorro máximo)',
                                  style: TextStyle(
                                    color: _bleActivo
                                        ? const Color(0xFF00E676)
                                        : Colors.grey,
                                    fontSize: 12,
                                    decoration: _bleActivo
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onLongPress: _activarODetenerSos,
                    onTap: () {
                      if (_sosActivo) {
                        _activarODetenerSos();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: Duration(seconds: 2),
                            backgroundColor: Colors.redAccent,
                            content: Text(
                              'Mantén presionado el botón SOS 2 segundos para emitir alerta de emergencia.',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: _sosActivo
                            ? Colors.red
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sos, color: Colors.white, size: 17),
                          if (_sosActivo) ...[
                            const SizedBox(width: 3),
                            const Text(
                              'ACTIVO',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _bleActivo,
                    activeThumbColor: const Color(0xFF00E676),
                    onChanged: _toggleMallaBle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Color(0xFFFF6D00)),
                    tooltip: 'Configurar Nodo y Batería',
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
             if (_config.chatActivo && _config.claveGrupo.trim().isNotEmpty)
       Container(
         color: const Color(0xFF0D0D0D),
         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
         child: Row(
           children: [
             Expanded(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: !_verCanalPrivado
                       ? const Color(0xFFFF6D00)
                       : const Color(0xFF1A1A1A),
                   foregroundColor:
                       !_verCanalPrivado ? Colors.black : Colors.grey,
                 ),
                 onPressed: () => setState(() => _verCanalPrivado = false),
                 icon: const Icon(Icons.public, size: 16),
                 label: const Text('CANAL ABIERTO',
                     style: TextStyle(
                         fontSize: 11, fontWeight: FontWeight.bold)),
               ),
             ),
             const SizedBox(width: 8),
             Expanded(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: _verCanalPrivado
                       ? const Color(0xFF00E676)
                       : const Color(0xFF1A1A1A),
                   foregroundColor:
                       _verCanalPrivado ? Colors.black : Colors.grey,
                 ),
                 onPressed: () => setState(() => _verCanalPrivado = true),
                 icon: const Icon(Icons.lock, size: 16),
                 label: const Text('GRUPO PRIVADO',
                     style: TextStyle(
                         fontSize: 11, fontWeight: FontWeight.bold)),
               ),
             ),
           ],
         ),
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
                    final todos = snapshot.data ?? [];
                    final msgs = todos
                        .where((m) =>
                            m.esPrivado ==
                            (_verCanalPrivado &&
                                _config.claveGrupo.trim().isNotEmpty))
                        .toList();

                    if (msgs.isEmpty) {
                      return Center(
                        child: Text(
                            _verCanalPrivado &&
                                    _config.claveGrupo.trim().isNotEmpty
                                ? 'Sin mensajes cifrados en este grupo.\nComparte la misma Clave AES-256 con tu equipo.'
                                : 'Sin mensajes en la malla.\nEnciende BLE o Wi-Fi para comunicarte.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey)),
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