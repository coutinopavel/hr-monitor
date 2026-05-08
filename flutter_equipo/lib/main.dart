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
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        useMaterial3: true,
      ),
      home: const MonitorScreen(),
    );
  }
}

// Algoritmo de detección de latidos
// Usa filtro DC + media móvil + detección por cruce por cero
// con período refractario para evitar doble conteo
class BeatDetector {
  // Filtro DC pasa-altas IIR
  double _dcW = 0;
  static const double _dcAlpha = 0.95;

  // Media móvil
  static const int _maSize = 4;
  final List<double> _maBuffer = List.filled(_maSize, 0);
  int _maIndex = 0;
  double _maSum = 0;

  // Estado de detección
  double _signalPrev = 0;
  int _lastBeatTime = 0;
  int _samplesProcessed = 0;

  // Período refractario: 300ms = máx 200 BPM
  // (evita doble conteo de la dícrota)
  static const int _refractoryMs = 300;

  // Tracking para diagnóstico
  double _lastSignal = 0;
  double _signalMin = 0;
  double _signalMax = 0;
  int _lastBeatDetectedAt = 0; 

  // Rechaza cambios extremos
  int _lastValidInterval = 0;

  // Buffer temporal de BPMs
  final List<MapEntry<int, int>> _bpmHistory = [];
  static const int _averageWindowMs = 15000;
  static const int _minSamplesForAvg = 2; 

  int _avgBpm = 0;
  double _instantBpm = 0;

  int get bpm => _avgBpm;
  double get instantBpm => _instantBpm;
  int get sampleCount => _bpmHistory.length;
  bool get hasReliableReading => _bpmHistory.length >= _minSamplesForAvg;
  double get currentSignal => _lastSignal;
  double get signalAmplitude => _signalMax - _signalMin;
  int get lastBeatDetectedAt => _lastBeatDetectedAt;

  void processIR(int irValue) {
    if (irValue < 50000) return;

    double raw = irValue.toDouble();
    _samplesProcessed++;

    // Filtro DC pasa-altas
    double dcW = raw + _dcAlpha * _dcW;
    double dcOut = dcW - _dcW;
    _dcW = dcW;

        // Filtrar 300ms a 2000ms = 30 a 200 BPM
        if (delta > 300 && delta < 2000) {
          _beatsPerMinute = 60000.0 / delta;

    _lastSignal = signal;

    // Esperar a que el filtro DC se estabilice (1 segundo)
    if (_samplesProcessed < 50) {
      _signalPrev = signal;
      return;
    }

    // Tracking de amplitud (ventana móvil simple)
    if (_samplesProcessed % 100 == 0) {
      _signalMin = signal;
      _signalMax = signal;
    } else {
      if (signal < _signalMin) _signalMin = signal;
      if (signal > _signalMax) _signalMax = signal;
    }

    int now = DateTime.now().millisecondsSinceEpoch;

    // Detección por cruce por cero ascendente
    bool zeroCrossing = _signalPrev < 0 && signal >= 0;

    if (zeroCrossing && (now - _lastBeatTime) > _refractoryMs) {
      _lastBeatDetectedAt = now;

      if (_lastBeatTime > 0) {
        int delta = now - _lastBeatTime;

        // Rango fisiológico: 40-200 BPM
        if (delta >= 300 && delta <= 1500) {
          _instantBpm = 60000.0 / delta;
          int bpmInt = _instantBpm.round();

          // Validación de variabilidad (más permisiva: 50%)
          bool intervalIsValid = true;
          if (_lastValidInterval > 0) {
            double change = (delta - _lastValidInterval).abs() /
                _lastValidInterval.toDouble();
            if (change > 0.50) {
              intervalIsValid = false;
            }
          }

          if (intervalIsValid) {
            _lastValidInterval = delta;
            _bpmHistory.add(MapEntry(now, bpmInt));

            _bpmHistory.removeWhere(
                (e) => now - e.key > _averageWindowMs);

            // Filtro de Mediana por los outliers
            if (_bpmHistory.length >= _minSamplesForAvg) {
              List<int> sorted = _bpmHistory.map((e) => e.value).toList()
                ..sort();
              int n = sorted.length;
              if (n.isOdd) {
                _avgBpm = sorted[n ~/ 2];
              } else {
                _avgBpm =
                    ((sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2).round();
              }
            }
          }
        }
      }
      _lastBeatTime = now;
    }

    _signalPrev = signal;
  }

  void reset() {
    _dcW = 0;
    _maBuffer.fillRange(0, _maSize, 0);
    _maIndex = 0;
    _maSum = 0;
    _signalPrev = 0;
    _lastBeatTime = 0;
    _samplesProcessed = 0;
    _lastValidInterval = 0;
    _bpmHistory.clear();
    _avgBpm = 0;
    _instantBpm = 0;
    _lastSignal = 0;
    _signalMin = 0;
    _signalMax = 0;
    _lastBeatDetectedAt = 0;
  }
}

// Pantalla principal con navegación
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen>
    with TickerProviderStateMixin {
  int _bpm = 0;
  int _irValue = 0;
  bool _conectado = false;
  bool _dedoDetectado = false;
  BluetoothDevice? _device;
  StreamSubscription? _irSubscription;
  final BeatDetector _beatDetector = BeatDetector();

  late AnimationController _heartController;
  late Animation<double> _heartAnimation;

  static const int _minNormal = 60;
  static const int _maxNormal = 100;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _heartAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.easeInOut),
    );
  }

  void _updateHeartAnimationSpeed() {
    if (_bpm > 0) {
      final ms = (60000 / _bpm / 2).round().clamp(200, 1500);
      _heartController.duration = Duration(milliseconds: ms);
      if (!_heartController.isAnimating) {
        _heartController.repeat(reverse: true);
      }
    } else {
      _heartController.duration = const Duration(milliseconds: 800);
    }
  }

  String _getEstado() {
    if (!_dedoDetectado || _bpm == 0) return 'Sin lectura';
    if (!_beatDetector.hasReliableReading) return 'Calibrando';
    if (_bpm < _minNormal) return 'Bradicardia';
    if (_bpm > _maxNormal) return 'Taquicardia';
    return 'Normal';
  }

  Color _getColorEstado() {
    final estado = _getEstado();
    if (estado == 'Normal') return const Color(0xFF00D4AA);
    if (estado == 'Sin lectura' || estado == 'Calibrando') {
      return const Color(0xFF6B7280);
    }
    return const Color(0xFFFF4D6A);
  }

  Future<void> _escanearYConectar() async {
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
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1F26),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          content: const Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFFFF4D6A),
                ),
              ),
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
                            _updateHeartAnimationSpeed();
                          } else {
                            _bpm = 0;
                            _beatDetector.reset();
                            _updateHeartAnimationSpeed();
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
                SnackBar(
                  content: const Text('Conectado a XIAO-HRMonitor'),
                  backgroundColor: const Color(0xFF00D4AA),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
    _updateHeartAnimationSpeed();
  }

  @override
  void dispose() {
    _heartController.dispose();
    _irSubscription?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = _getEstado();
    final color = _getColorEstado();

    // Indicador visual de latido detectado (parpadeo verde por 200ms)
    final now = DateTime.now().millisecondsSinceEpoch;
    final beatRecent =
        (now - _beatDetector.lastBeatDetectedAt) < 200 && _dedoDetectado;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'HR Monitor',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _conectado
                          ? const Color(0xFF00D4AA).withOpacity(0.15)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _conectado
                            ? const Color(0xFF00D4AA).withOpacity(0.3)
                            : Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Text(
                      estado == 'Normal'
                          ? '● Normal (${rango['min']}-${rango['max']} BPM)'
                          : estado == 'Sin lectura'
                              ? _dedoDetectado
                                  ? 'Procesando...'
                                  : 'Esperando lectura...'
                              : '$estado (rango: ${rango['min']}-${rango['max']})',
                      style: TextStyle(fontSize: 13, color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Card principal de FC
              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 36, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.18),
                      color.withOpacity(0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: color.withOpacity(0.25), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 30,
                      spreadRadius: -5,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.show_chart,
                            size: 14, color: color.withOpacity(0.7)),
                        const SizedBox(width: 6),
                        Text(
                          'PROMEDIO · ÚLTIMOS 15s',
                          style: TextStyle(
                              color: color.withOpacity(0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ScaleTransition(
                          scale: _bpm > 0
                              ? _heartAnimation
                              : const AlwaysStoppedAnimation(1.0),
                          child: Icon(
                            Icons.favorite,
                            color: color,
                            size: 52,
                            shadows: [
                              Shadow(
                                  color: color.withOpacity(0.6),
                                  blurRadius: 24),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _bpm > 0 ? '$_bpm' : '--',
                              style: TextStyle(
                                fontSize: 88,
                                fontWeight: FontWeight.w800,
                                color: color,
                                letterSpacing: -3,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text(
                                'BPM',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: color.withOpacity(0.7),
                                    letterSpacing: 1),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            estado == 'Normal'
                                ? Icons.check_circle
                                : estado == 'Sin lectura'
                                    ? Icons.hourglass_empty
                                    : estado == 'Calibrando'
                                        ? Icons.tune
                                        : Icons.warning_amber_rounded,
                            size: 16,
                            color: color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            estado == 'Normal'
                                ? 'Normal · $_minNormal-$_maxNormal BPM'
                                : estado == 'Sin lectura'
                                    ? _dedoDetectado
                                        ? 'Procesando...'
                                        : 'Coloca tu dedo en el sensor'
                                    : estado == 'Calibrando'
                                        ? 'Calibrando... mantén el dedo quieto'
                                        : '$estado · rango $_minNormal-$_maxNormal',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Cards info
              Row(
                children: [
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.fingerprint,
                      label: 'Sensor',
                      value: _dedoDetectado ? 'Activo' : 'En espera',
                      valueColor: _dedoDetectado
                          ? const Color(0xFF00D4AA)
                          : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoCard(
                      icon: Icons.timeline,
                      label: 'Latidos',
                      value: '${_beatDetector.sampleCount}',
                      valueColor: Colors.white,
                    ),
                  ),
                ],
              ),

              // Panel de diagnóstico
              if (_conectado) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    children: [
                      // Indicador de latido detectado
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: beatRecent
                                      ? const Color(0xFF00D4AA)
                                      : Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  boxShadow: beatRecent
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF00D4AA)
                                                .withOpacity(0.8),
                                            blurRadius: 10,
                                          )
                                        ]
                                      : [],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('Detector',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12)),
                            ],
                          ),
                          Text(
                              beatRecent
                                  ? 'LATIDO'
                                  : _dedoDetectado
                                      ? 'Esperando pico...'
                                      : 'Sin dedo',
                              style: TextStyle(
                                  color: beatRecent
                                      ? const Color(0xFF00D4AA)
                                      : Colors.white.withOpacity(0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.05)),
                      const SizedBox(height: 10),

                      // IR
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.sensors,
                                  size: 13,
                                  color: Colors.white.withOpacity(0.4)),
                              const SizedBox(width: 6),
                              Text('Señal IR',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12)),
                            ],
                          ),
                          Text('$_irValue',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Amplitud AC (calidad de la señal pulsátil)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.show_chart,
                                  size: 13,
                                  color: Colors.white.withOpacity(0.4)),
                              const SizedBox(width: 6),
                              Text('Amplitud AC',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12)),
                            ],
                          ),
                          Text(
                              _beatDetector.signalAmplitude.toStringAsFixed(0),
                              style: TextStyle(
                                  color: _beatDetector.signalAmplitude > 100
                                      ? const Color(0xFF00D4AA)
                                      : Colors.orange,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Alerta 
              if (_dedoDetectado &&
                  estado != 'Normal' &&
                  estado != 'Sin lectura' &&
                  estado != 'Calibrando') ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFF4D6A).withOpacity(0.15),
                        const Color(0xFFFF4D6A).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFFFF4D6A).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4D6A),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.warning_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              estado == 'Taquicardia'
                                  ? 'Frecuencia elevada'
                                  : 'Frecuencia baja',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF4D6A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              estado == 'Taquicardia'
                                  ? 'Considera descansar y respirar profundo.'
                                  : 'Si presentas mareos, consulta a un médico.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Botón
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: _conectado
                      ? []
                      : [
                          BoxShadow(
                            color: const Color(0xFFFF4D6A).withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                child: ElevatedButton.icon(
                  onPressed:
                      _conectado ? _desconectar : _escanearYConectar,
                  icon: Icon(_conectado
                      ? Icons.bluetooth_disabled
                      : Icons.bluetooth_searching),
                  label:
                      Text(_conectado ? 'Desconectar' : 'Conectar sensor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _conectado
                        ? const Color(0xFF2A2F38)
                        : const Color(0xFFFF4D6A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white.withOpacity(0.4)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
