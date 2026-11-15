import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'mesh_chat_service.dart';
import 'nodo_config_service.dart';

class _VecinoActivo {
  final BluetoothDevice device;
  DateTime ultimaVezVisto;
  _VecinoActivo(this.device, this.ultimaVezVisto);
}

class BleMeshService {
  static const int manufacturerId = 0xAE61;
  static const String serviceUuidStr = '0000ae61-0000-1000-8000-00805f9b34fb';
  static const String charUuidStr = '0000ae62-0000-1000-8000-00805f9b34fb';

  static const MethodChannel _bleChannel =
      MethodChannel('com.emergencia.aegis_node/kiwix');

  static bool _activo = false;
  static NodoConfig? _configActual;
  static StreamSubscription<List<ScanResult>>? _scanSub;
  static final Map<String, _VecinoActivo> _vecinos = {};
  static final StreamController<int> _vecinosCtrl =
      StreamController<int>.broadcast();

  static final List<MensajeMesh> _colaEnvio = [];
  static bool _procesandoCola = false;
  static void Function()? onAbrirPestanaNodo;

  static bool get estaActivo => _activo;
  static int get cantidadNodosVecinos {
    _limpiarVecinosExpirados();
    return _vecinos.length;
  }

  static Stream<int> get streamVecinos => _vecinosCtrl.stream;

  static void _limpiarVecinosExpirados() {
    final limite = DateTime.now().subtract(const Duration(seconds: 60));
    final antes = _vecinos.length;
    _vecinos.removeWhere((_, v) => v.ultimaVezVisto.isBefore(limite));
    if (_vecinos.length != antes) {
      _vecinosCtrl.add(_vecinos.length);
    }
  }

  static Future<void> limpiarNotificaciones() async {
    try {
      await _bleChannel.invokeMethod('limpiarNotificaciones');
    } catch (_) {}
  }

  static Future<void> iniciarMalla(NodoConfig config) async {
    if (_activo) return;
    _activo = true;
    _configActual = config;

    _bleChannel.setMethodCallHandler((call) async {
      if (call.method == 'onMensajeGattRecibido') {
        final rawJson = call.arguments?.toString() ?? '';
        if (rawJson.isNotEmpty) {
          try {
            final mapa = jsonDecode(rawJson) as Map<String, dynamic>;
            final msgId = mapa['id']?.toString() ?? '';
            final autor =
                mapa['autor']?.toString() ?? mapa['a']?.toString() ?? '';
            final texto =
                mapa['texto']?.toString() ?? mapa['t']?.toString() ?? '';

            final yaVisto = MeshChatService.yaFueVisto(msgId);
            final esPropio = autor.trim().toLowerCase() ==
                (_configActual?.alias.trim().toLowerCase() ?? '');

            await MeshChatService.recibirPaqueteExterno(mapa);

            if (!yaVisto &&
                !esPropio &&
                _configActual?.notificarMensajes == true) {
              await _bleChannel.invokeMethod('notificarMensaje', {
                'autor': autor.isEmpty ? 'Nodo' : autor,
                'cuerpo': texto,
              });
            }
          } catch (e) {MeshChatService.publicarAvisoSistema('Error leyendo paquete: $e');}
        }
      } else if (call.method == 'abrirPestanaNodo') {
        onAbrirPestanaNodo?.call();
      }
    });

    await _bleChannel.invokeMethod('iniciarGattServer');
    await Future.delayed(const Duration(milliseconds: 400));

    MeshChatService.onReenviarPaquete = (paquete) async {
      _encolarYProcesar(paquete);
    };

    _scanSub = FlutterBluePlus.scanResults.listen((resultados) {
      for (final r in resultados) {
        final mData = r.advertisementData.manufacturerData[manufacturerId];
        if (mData != null && mData.isNotEmpty) {
          final idDispositivo = r.device.remoteId.str;
          final eraNuevo = !_vecinos.containsKey(idDispositivo);
          _vecinos[idDispositivo] = _VecinoActivo(r.device, DateTime.now());
          if (eraNuevo) {
            _vecinosCtrl.add(_vecinos.length);
          }
        }
      }
    });

    await _emitirBalizaPing();
    _ejecutarCicloEscucha(config);
  }
  static Future<void> _emitirBalizaPing() async {
    if (!_activo || _configActual == null) return;
    try {
      final aliasBytes = utf8.encode(_configActual!.alias);
      final recortado =
          aliasBytes.length > 12 ? aliasBytes.sublist(0, 12) : aliasBytes;
      final paquete = Uint8List.fromList([0x01, ...recortado]);

      await _bleChannel.invokeMethod('emitirBle', {
        'manufacturerId': manufacturerId,
        'datos': paquete,
      });
    } catch (_) {}
  }

  static Future<void> _ejecutarCicloEscucha(NodoConfig config) async {
    while (_activo) {
      _limpiarVecinosExpirados();
      try {
        await FlutterBluePlus.startScan(
          withServices: [Guid(serviceUuidStr)],
          timeout: const Duration(seconds: 4),
        );
        await Future.delayed(const Duration(seconds: 4));
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      if (!_activo) break;
      final descanso = config.segundosDescansoRadio;
      await Future.delayed(Duration(seconds: descanso));

      if (_activo) {
        await _emitirBalizaPing();
      }
    }
  }

  static Future<void> _encolarYProcesar(MensajeMesh msg) async {
    if (!_activo) return;
    if (_colaEnvio.length >= 100) _colaEnvio.removeAt(0);
    _colaEnvio.add(msg);

    if (_procesandoCola) return;
    _procesandoCola = true;

    try {
      while (_activo && _colaEnvio.isNotEmpty) {
        final siguiente = _colaEnvio.removeAt(0);
        await _enviarConConfirmacionGatt(siguiente);
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      _procesandoCola = false;
    }
  }

  static Future<void> _enviarConConfirmacionGatt(MensajeMesh msg) async {
    if (!_activo) return;
    _limpiarVecinosExpirados();

    if (_vecinos.isEmpty) {
      MeshChatService.publicarAvisoSistema('Sin vecinos activos en rango.');
      return;
    }

    await Future.delayed(Duration(milliseconds: 150 + Random().nextInt(350)));

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final payloadBytes = utf8.encode(jsonEncode(msg.toJson()));

    for (final vecino in _vecinos.values.toList()) {
      final device = vecino.device;
      bool enviado = false;

      for (int intento = 0; intento < 2 && !enviado; intento++) {
        try {
          await device.connect(
            timeout: const Duration(seconds: 6),
            autoConnect: false,
            mtu: null,
          );

          await device.connectionState
              .where((s) => s == BluetoothConnectionState.connected)
              .first
              .timeout(const Duration(seconds: 4));

          final servicios = await device.discoverServices();
          for (final s in servicios) {
            if (s.uuid.toString().toLowerCase().contains('ae61')) {
              for (final c in s.characteristics) {
                if (c.uuid.toString().toLowerCase().contains('ae62')) {
                  const int maxChunk = 20;
                  for (int offset = 0;
                      offset < payloadBytes.length;
                      offset += maxChunk) {
                    final fin = (offset + maxChunk < payloadBytes.length)
                        ? offset + maxChunk
                        : payloadBytes.length;
                    final chunk = payloadBytes.sublist(offset, fin);
                    await c.write(chunk, withoutResponse: false);
                  }
                  enviado = true;
                }
              }
            }
          }
        } catch (e) {
          if (intento == 1 && !enviado) {
            MeshChatService.publicarAvisoSistema(
                'No se pudo entregar a vecino: $e');
          }
          await Future.delayed(const Duration(milliseconds: 400));
        } finally {
          try {
            await device.disconnect();
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> detenerMalla() async {
    _activo = false;
    _colaEnvio.clear();
    _procesandoCola = false;
    await _scanSub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
      await _bleChannel.invokeMethod('detenerBle');
    } catch (_) {}
    _vecinos.clear();
    _vecinosCtrl.add(0);
  }
}
