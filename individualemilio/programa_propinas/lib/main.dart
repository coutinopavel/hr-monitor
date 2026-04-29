import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const TipSplitApp());
}

class TipSplitApp extends StatelessWidget {
  const TipSplitApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tip & Split',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TipSplitPage(),
    );
  }
}

class TipSplitPage extends StatefulWidget {
  const TipSplitPage({super.key});

  @override
  State<TipSplitPage> createState() => _TipSplitPageState();
}

class _TipSplitPageState extends State<TipSplitPage> {
  final TextEditingController _billController = TextEditingController();
  double _tipPercent = 10;
  int _people = 1;

  // Parse the bill total safely from the text field.
  double get _billTotal {
    final text = _billController.text.trim();
    if (text.isEmpty) {
      return 0;
    }
    return double.tryParse(text) ?? 0;
  }

  // Derived totals used by the results card.
  double get _tipAmount => _billTotal * (_tipPercent / 100);
  double get _grandTotal => _billTotal + _tipAmount;
  double get _perPerson => _people > 0 ? _grandTotal / _people : 0;

  @override
  void dispose() {
    _billController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tip & Split'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Input section for bill, tip, and people count.
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total de la cuenta', style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _billController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.attach_money),
                          hintText: 'Ej: 250',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          setState(() {
                            // Update totals when the bill changes.
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      Text('Porcentaje de propina',
                          style: textTheme.titleMedium),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0%'),
                          Text('${_tipPercent.toStringAsFixed(0)}%'),
                          Text('30%'),
                        ],
                      ),
                      Slider(
                        value: _tipPercent,
                        min: 0,
                        max: 30,
                        divisions: 30,
                        label: '${_tipPercent.toStringAsFixed(0)}%',
                        onChanged: (value) {
                          setState(() {
                            _tipPercent = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text('Personas', style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (_people > 1) {
                                  _people--;
                                }
                              });
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$_people',
                            style: textTheme.headlineSmall,
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _people++;
                              });
                            },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Results section with a highlighted per-person amount.
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Resultados', style: textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _ResultRow(
                        label: 'Propina total',
                        value: _tipAmount.toStringAsFixed(2),
                      ),
                      const SizedBox(height: 8),
                      _ResultRow(
                        label: 'Total general',
                        value: _grandTotal.toStringAsFixed(2),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total por persona',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '\$${_perPerson.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          '\$$value',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
