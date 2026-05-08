import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Archery Scores',
      home: const ScorePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScorePage extends StatefulWidget {
  const ScorePage({super.key});

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  // 6 rondas de 6 flechas
  List<List<int>> scores =
      List.generate(6, (_) => List.filled(6, 0));
  // Total por ronda
  int roundTotal(int round) {
    return scores[round].reduce((a, b) => a + b);
  }
  // Promedio por serie
  double roundAverage(int round) {
    return roundTotal(round) / 6;
  }
  // Total
  int grandTotal() {
    return scores.expand((x) => x).reduce((a, b) => a + b);
  }
  // Promedio general
  double overallAverage() {
    return grandTotal() / 36;
  }
  // Mejor ronda de 6
  int bestRound() {
    int best = 0;
    int index = 0;

    for (int i = 0; i < 6; i++) {
      if (roundTotal(i) > best) {
        best = roundTotal(i);
        index = i;
      }
    }

    return index + 1;
  }

  void resetScores() {
    setState(() {
      scores = List.generate(6, (_) => List.filled(6, 0));
    });
  }

  Widget scoreButton(int round, int arrow, int value) {
    bool selected = scores[round][arrow] == value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        label: Text("$value"),
        selected: selected,
        onSelected: (_) {
          setState(() {
            scores[round][arrow] = value;
          });
        },
      ),
    );
  }

  Widget roundCard(int round) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Ronda ${round + 1}",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            for (int arrow = 0; arrow < 6; arrow++)
              Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    "Flecha ${arrow + 1}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 6),

                  SingleChildScrollView(
                    scrollDirection:
                        Axis.horizontal,
                    child: Row(
                      children: List.generate(
                        11,
                        (i) => scoreButton(
                          round,
                          arrow,
                          10 - i,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                ],
              ),

            const Divider(),

            Text(
              "Total: ${roundTotal(round)}",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(
              "Promedio: ${roundAverage(round).toStringAsFixed(2)}",
              style:
                  const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget summaryCard() {
    return Card(
      color: const Color.fromARGB(255, 234, 46, 103),
      margin: const EdgeInsets.all(12),
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text(
              "Resumen Final",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              "Total: ${grandTotal()}",
              style:
                  const TextStyle(fontSize: 18),
            ),

            Text(
              "Promedio: ${overallAverage().toStringAsFixed(2)}",
              style:
                  const TextStyle(fontSize: 18),
            ),

            Text(
              "Mejor serie: ${bestRound()}",
              style:
                  const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text("My Archery Scores"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: resetScores,
          )
        ],
      ),
      body: ListView(
        children: [
          ...List.generate(
            6,
            (index) => roundCard(index),
          ),
          summaryCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
