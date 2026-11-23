import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const AlusekisApp());
}

class AlusekisApp extends StatelessWidget {
  const AlusekisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alusekis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
      ),
      home: const PagrindinisEkranas(),
    );
  }
}

class PagrindinisEkranas extends StatelessWidget {
  const PagrindinisEkranas({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alusekis'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Center(
        child: Text('Alusekis'),
      ),
    );
  }
}
