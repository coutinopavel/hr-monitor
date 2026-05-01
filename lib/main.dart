import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const HrMonitorApp());
}

class HrMonitorApp extends StatelessWidget {
  const HrMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HR Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF4D6A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ── Modelo de datos del usuario ──
class UserProfile {
  String nombre;
  int edad;
  String sexo;
  double peso;
  double altura;

  UserProfile({
    this.nombre = '',
    this.edad = 0,
    this.sexo = 'Masculino',
    this.peso = 0,
    this.altura = 0,
  });
}

// ── Algoritmo de detección de latidos ──
class BeatDetector {
  static const int _rateSize = 4;
  final List<int> _rates = List.filled(_rateSize, 0);
  int _rateSpot = 0;
  int _lastBeatTime = 0;
  double _beatsPerMinute = 0;
  int _beatAvg = 0;

  // Variables para detección de picos
  double _irPrev = 0;
  double _irPrevPrev = 0;
  double _threshold = 80000;
  int _lastPeakTime = 0;
  bool _rising = false;

  int get bpm => _beatAvg;
  double get instantBpm => _beatsPerMinute;

  void processIR(int irValue) {
    double ir = irValue.toDouble();

    // Detección de pico: subió y ahora baja
    if (_irPrev > _threshold && _irPrevPrev < _irPrev && ir < _irPrev) {
      // Encontramos un pico (latido)
      int now = DateTime.now().millisecondsSinceEpoch;

      if (_lastPeakTime > 0) {
        int delta = now - _lastPeakTime;

        // Filtrar deltas razonables (300ms a 2000ms = 30 a 200 BPM)
        if (delta > 300 && delta < 2000) {
          _beatsPerMinute = 60000.0 / delta;

          if (_beatsPerMinute > 30 && _beatsPerMinute < 220) {
            _rates[_rateSpot] = _beatsPerMinute.toInt();
            _rateSpot = (_rateSpot + 1) % _rateSize;

            _beatAvg = 0;
            for (int i = 0; i < _rateSize; i++) {
              _beatAvg += _rates[i];
            }
            _beatAvg = _beatAvg ~/ _rateSize;
          }
        }
      }
      _lastPeakTime = now;
    }

    // Actualizar threshold dinámico
    _threshold = _threshold * 0.99 + ir * 0.01;
    if (_threshold < 50000) _threshold = 50000;

    _irPrevPrev = _irPrev;
    _irPrev = ir;
  }

  void reset() {
    _rates.fillRange(0, _rateSize, 0);
    _rateSpot = 0;
    _beatAvg = 0;
    _beatsPerMinute = 0;
    _lastPeakTime = 0;
    _irPrev = 0;
    _irPrevPrev = 0;
    _threshold = 80000;
  }
}

// ── Pantalla principal con navegación ──
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final UserProfile _perfil = UserProfile();
  int _bpm = 0;
  int _irValue = 0;
  bool _conectado = false;
  bool _dedoDetectado = false;
  BluetoothDevice? _device;
  StreamSubscription? _irSubscription;
  final List<Map<String, dynamic>> _historial = [];
  final BeatDetector _beatDetector = BeatDetector();

  // UUIDs del servicio custom
  final String _serviceUuid = "00001234-0000-1000-8000-00805f9b34fb";
  final String _charUuid = "00005678-0000-1000-8000-00805f9b34fb";

  Map<String, int> _getRangoNormal() {
    if (_perfil.edad <= 0) return {'min': 60, 'max': 100};
    if (_perfil.edad <= 12) return {'min': 70, 'max': 120};
    if (_perfil.edad <= 18) return {'min': 60, 'max': 100};
    if (_perfil.edad <= 65) return {'min': 60, 'max': 100};
    return {'min': 60, 'max': 90};
  }

  String _getEstado() {
    if (!_dedoDetectado || _bpm == 0) return 'Sin lectura';
    final rango = _getRangoNormal();
    if (_bpm < rango['min']!) return 'Bradicardia';
    if (_bpm > rango['max']!) return 'Taquicardia';
    return 'Normal';
  }

  Color _getColorEstado() {
    final estado = _getEstado();
    if (estado == 'Normal') return const Color(0xFF00D4AA);
    if (estado == 'Sin lectura') return Colors.grey;
    return const Color(0xFFFF4D6A);
  }

 Future<void> _escanearYConectar() async {
    // Pedir permisos en tiempo de ejecución
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa el Bluetooth')),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Buscando XIAO-HRMonitor...'),
            ],
          ),
        ),
      );
    }

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) async {
      for (var result in results) {
        if (result.device.platformName.contains('XIAO-HRMonitor')) {
          FlutterBluePlus.stopScan();

          try {
            await result.device.connect(timeout: const Duration(seconds: 5));
            _device = result.device;

            List<BluetoothService> services =
                await result.device.discoverServices();

            for (var service in services) {
              if (service.uuid.toString().contains('1234')) {
                for (var characteristic in service.characteristics) {
                  if (characteristic.uuid.toString().contains('5678')) {
                    await characteristic.setNotifyValue(true);
                    _irSubscription =
                        characteristic.onValueReceived.listen((value) {
                      if (value.length >= 4) {
                        final bytes = Uint8List.fromList(value);
                        final irVal = ByteData.sublistView(bytes)
                            .getUint32(0, Endian.little);

                        setState(() {
                          _irValue = irVal;
                          _dedoDetectado = irVal > 50000;

                          if (_dedoDetectado) {
                            _beatDetector.processIR(irVal);
                            _bpm = _beatDetector.bpm;

                            if (_bpm > 0) {
                              final ahora = DateTime.now();
                              if (_historial.isEmpty ||
                                  ahora
                                          .difference(DateTime.parse(
                                              _historial.first['fecha']))
                                          .inSeconds >
                                      30) {
                                _historial.insert(0, {
                                  'bpm': _bpm,
                                  'estado': _getEstado(),
                                  'fecha': ahora.toIso8601String(),
                                });
                              }
                            }
                          } else {
                            _bpm = 0;
                            _beatDetector.reset();
                          }

                          _conectado = true;
                        });
                      }
                    });
                  }
                }
              }
            }

            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Conectado a XIAO-HRMonitor'),
                  backgroundColor: Color(0xFF00D4AA),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error al conectar: $e')),
              );
            }
          }
          return;
        }
      }
    });

    await Future.delayed(const Duration(seconds: 11));
    if (!_conectado && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró XIAO-HRMonitor')),
      );
    }
  }

  void _desconectar() async {
    _irSubscription?.cancel();
    await _device?.disconnect();
    setState(() {
      _conectado = false;
      _bpm = 0;
      _irValue = 0;
      _dedoDetectado = false;
      _device = null;
    });
    _beatDetector.reset();
  }

  @override
  void dispose() {
    _irSubscription?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildDashboard(),
      _buildHistorial(),
      _buildPerfil(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final rango = _getRangoNormal();
    final estado = _getEstado();
    final color = _getColorEstado();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'HR Monitor',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _conectado
                        ? const Color(0xFF00D4AA).withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth, size: 16,
                          color: _conectado
                              ? const Color(0xFF00D4AA)
                              : Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _conectado ? 'Conectado' : 'Desconectado',
                        style: TextStyle(fontSize: 12,
                            color: _conectado
                                ? const Color(0xFF00D4AA)
                                : Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_perfil.nombre.isNotEmpty)
              Text(
                '${_perfil.nombre} · ${_perfil.edad} años · ${_perfil.peso} kg · ${_perfil.altura} cm',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            const SizedBox(height: 24),

            // Card FC
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  const Text('Frecuencia Cardíaca',
                      style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Icon(Icons.favorite, color: color,
                          size: _bpm > 0 ? 36 : 24),
                      const SizedBox(width: 12),
                      Text(
                        _bpm > 0 ? '$_bpm' : '--',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('BPM',
                          style: TextStyle(
                              fontSize: 18,
                              color: color.withOpacity(0.7))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estado == 'Normal'
                          ? '● Normal (${rango['min']}-${rango['max']} BPM)'
                          : estado == 'Sin lectura'
                              ? _dedoDetectado
                                  ? 'Procesando...'
                                  : 'Esperando lectura...'
                              : '⚠ $estado (rango: ${rango['min']}-${rango['max']})',
                      style: TextStyle(fontSize: 13, color: color),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // IR Value debug
            if (_conectado)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('IR: $_irValue',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                        _dedoDetectado
                            ? 'Dedo detectado'
                            : 'Coloca tu dedo',
                        style: TextStyle(
                            color: _dedoDetectado
                                ? const Color(0xFF00D4AA)
                                : Colors.orange,
                            fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Alerta
            if (_dedoDetectado &&
                estado != 'Normal' &&
                estado != 'Sin lectura')
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D6A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFFF4D6A).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFFF4D6A),
                      radius: 16,
                      child:
                          Icon(Icons.warning, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        estado == 'Taquicardia'
                            ? 'FC elevada. Considera descansar y relajarte.'
                            : 'FC baja. Si presentas mareos, consulta a un médico.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Botón conectar
            ElevatedButton.icon(
              onPressed: _conectado ? _desconectar : _escanearYConectar,
              icon: Icon(_conectado
                  ? Icons.bluetooth_disabled
                  : Icons.bluetooth_searching),
              label:
                  Text(_conectado ? 'Desconectar' : 'Conectar sensor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _conectado
                    ? Colors.grey.shade800
                    : const Color(0xFFFF4D6A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorial() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Historial',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _historial.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Sin mediciones aún',
                            style:
                                TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _historial.length,
                    itemBuilder: (context, index) {
                      final m = _historial[index];
                      final fecha = DateTime.parse(m['fecha']);
                      final esNormal = m['estado'] == 'Normal';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: esNormal
                                ? const Color(0xFF00D4AA).withOpacity(0.2)
                                : const Color(0xFFFF4D6A).withOpacity(0.2),
                            child: Icon(Icons.favorite,
                                color: esNormal
                                    ? const Color(0xFF00D4AA)
                                    : const Color(0xFFFF4D6A)),
                          ),
                          title: Text('${m['bpm']} BPM',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18)),
                          subtitle: Text(m['estado'],
                              style: TextStyle(
                                  color: esNormal
                                      ? const Color(0xFF00D4AA)
                                      : const Color(0xFFFF4D6A))),
                          trailing: Text(
                            '${fecha.day}/${fecha.month}/${fecha.year}\n${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerfil() {
    final nombreCtrl = TextEditingController(text: _perfil.nombre);
    final edadCtrl = TextEditingController(
        text: _perfil.edad > 0 ? '${_perfil.edad}' : '');
    final pesoCtrl = TextEditingController(
        text: _perfil.peso > 0 ? '${_perfil.peso}' : '');
    final alturaCtrl = TextEditingController(
        text: _perfil.altura > 0 ? '${_perfil.altura}' : '');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tu perfil',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'Tus datos se usan para personalizar las alertas de FC',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 24),
            TextField(
              controller: nombreCtrl,
              decoration: InputDecoration(
                labelText: 'Nombre',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: edadCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Edad',
                prefixIcon: const Icon(Icons.cake),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Sexo',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _perfil.sexo = 'Masculino'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _perfil.sexo == 'Masculino'
                            ? const Color(0xFFFF4D6A).withOpacity(0.15)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _perfil.sexo == 'Masculino'
                                ? const Color(0xFFFF4D6A)
                                : Colors.grey.shade700),
                      ),
                      child: Center(
                        child: Text('Masculino',
                            style: TextStyle(
                                color: _perfil.sexo == 'Masculino'
                                    ? const Color(0xFFFF4D6A)
                                    : Colors.grey,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _perfil.sexo = 'Femenino'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _perfil.sexo == 'Femenino'
                            ? const Color(0xFFFF4D6A).withOpacity(0.15)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _perfil.sexo == 'Femenino'
                                ? const Color(0xFFFF4D6A)
                                : Colors.grey.shade700),
                      ),
                      child: Center(
                        child: Text('Femenino',
                            style: TextStyle(
                                color: _perfil.sexo == 'Femenino'
                                    ? const Color(0xFFFF4D6A)
                                    : Colors.grey,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pesoCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Peso (kg)',
                prefixIcon: const Icon(Icons.fitness_center),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: alturaCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Altura (cm)',
                prefixIcon: const Icon(Icons.height),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _perfil.nombre = nombreCtrl.text;
                  _perfil.edad = int.tryParse(edadCtrl.text) ?? 0;
                  _perfil.peso = double.tryParse(pesoCtrl.text) ?? 0;
                  _perfil.altura =
                      double.tryParse(alturaCtrl.text) ?? 0;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Perfil guardado'),
                    backgroundColor: Color(0xFF00D4AA),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D6A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              child: const Text('Guardar perfil'),
            ),
          ],
        ),
      ),
    );
  }
}