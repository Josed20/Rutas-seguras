import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'grafo.dart';

class RutaSeguraController {
  final Grafo grafo;
  final List<dynamic> zonasPeligrosas;
  final Set<Polyline> rutas;
  final BuildContext context;

  RutaSeguraController({
    required this.grafo,
    required this.zonasPeligrosas,
    required this.rutas,
    required this.context,
  });

  List<String> _rutaConDijkstra(List<dynamic> args) {
    final grafo = args[0] as Grafo;
    final String inicio = args[1];
    final String fin = args[2];
    return grafo.dijkstra(inicio, fin);
  }

  Future<void> trazarRutaSegura(LatLng? origen, LatLng? destino) async {
    if (origen == null || destino == null) {
      return;
    }

    try {
      String? nodoInicio;
      String? nodoFin;
      double distanciaMinimaOrigen = double.infinity;
      double distanciaMinimaDestino = double.infinity;

      // Encontrar los nodos más cercanos al origen y destino
      for (var zona in zonasPeligrosas) {
        double distanciaOrigen = Geolocator.distanceBetween(
          origen.latitude,
          origen.longitude,
          zona.coordenada.latitude,
          zona.coordenada.longitude,
        );

        double distanciaDestino = Geolocator.distanceBetween(
          destino.latitude,
          destino.longitude,
          zona.coordenada.latitude,
          zona.coordenada.longitude,
        );

        // Actualizar el nodo más cercano al origen
        if (distanciaOrigen < distanciaMinimaOrigen) {
          distanciaMinimaOrigen = distanciaOrigen;
          nodoInicio = zona.nombre;
        }

        // Actualizar el nodo más cercano al destino
        if (distanciaDestino < distanciaMinimaDestino) {
          distanciaMinimaDestino = distanciaDestino;
          nodoFin = zona.nombre;
        }
      }

      // Verificar si los puntos están demasiado lejos de cualquier nodo
      const double distanciaMaxima = 300; // 300 metros como distancia máxima
      if (distanciaMinimaOrigen > distanciaMaxima ||
          distanciaMinimaDestino > distanciaMaxima) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Las ubicaciones seleccionadas están demasiado lejos de las rutas disponibles",
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final camino = await compute(_rutaConDijkstra, [
        grafo,
        nodoInicio!,
        nodoFin!,
      ]);

      if (camino.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No se encontró una ruta segura entre los puntos seleccionados",
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      List<LatLng> puntosRuta = camino.map((nombre) {
        return zonasPeligrosas
                .firstWhere(
                  (z) => z.nombre == nombre,
                  orElse: () => throw Exception("Zona no encontrada: $nombre"),
                )
                .coordenada
            as LatLng;
      }).toList();

      if (!context.mounted) return;
      rutas.clear();
      rutas.add(
        Polyline(
          polylineId: const PolylineId("ruta_segura"),
          points: puntosRuta,
          color: Colors.green,
          width: 6,
        ),
      );
    } catch (e) {
      debugPrint("Error al trazar ruta segura: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al trazar la ruta: ${e.toString()}"),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
