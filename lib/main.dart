import 'package:flutter/material.dart';
import 'mapa_ruta_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rutas Seguras',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MapaRutaPage(),
    );
  }
}
//const String googleApiKey = 'AIzaSyAR4vFAk43C3sTnO-YEu-7g1kkT23mW9es';