import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class ZonaPeligrosa {
  final String nombre;
  final LatLng coordenada;
  final int nivelInseguridad;

  ZonaPeligrosa(this.nombre, this.coordenada, this.nivelInseguridad);
}

class Grafo {
  final Map<String, Map<String, double>> nodos = {};

  void agregarArista(String origen, String destino, double peso) {
    nodos[origen] ??= {};
    nodos[origen]![destino] = peso;
    nodos[destino] ??= {};
    nodos[destino]![origen] = peso; // bidireccional
  }

  void agregarConInseguridad(
    String origen,
    String destino,
    LatLng coordOrigen,
    LatLng coordDestino,
    int riesgoOrigen,
    int riesgoDestino,
  ) {
    final distancia = Geolocator.distanceBetween(
      coordOrigen.latitude,
      coordOrigen.longitude,
      coordDestino.latitude,
      coordDestino.longitude,
    );
    final penalizacion = ((riesgoOrigen + riesgoDestino) / 2) * 10;
    agregarArista(origen, destino, distancia + penalizacion);
  }

  List<String> dijkstra(String inicio, String fin) {
    final distancias = Map<String, double>.fromIterable(
      nodos.keys,
      value: (_) => double.infinity,
    );
    final anteriores = <String, String?>{};
    final visitados = <String>{};
    distancias[inicio] = 0;

    while (visitados.length < nodos.length) {
      final actual = distancias.entries
          .where((e) => !visitados.contains(e.key))
          .reduce((a, b) => a.value < b.value ? a : b)
          .key;

      if (actual == fin) break;

      visitados.add(actual);

      nodos[actual]?.forEach((vecino, peso) {
        final nuevaDistancia = distancias[actual]! + peso;
        if (nuevaDistancia < distancias[vecino]!) {
          distancias[vecino] = nuevaDistancia;
          anteriores[vecino] = actual;
        }
      });
    }

    final camino = <String>[];
    for (String? at = fin; at != null; at = anteriores[at]) {
      camino.insert(0, at);
    }
    return camino;
  }
} 

final zonasPeligrosas = [
  ZonaPeligrosa("Avenida San Juan", LatLng(-12.1402414, -76.9691541), 8),
  ZonaPeligrosa("Avenida Los Héroes", LatLng(-12.1547273, -76.9707644), 9),
  ZonaPeligrosa("Av. Ramón Vargas Machuca", LatLng(-12.1658274, -76.9746875), 7),
  ZonaPeligrosa("Puente Alipio Ponce", LatLng(-12.169201, -76.9796643), 8),
  ZonaPeligrosa("Puente Atocongo", LatLng(-12.1497377, -76.9832397), 7),
  ZonaPeligrosa("La Rinconada de Pamplona Alta", LatLng(-12.1279257, -76.958905), 9),
  ZonaPeligrosa("A.H. El Imperio", LatLng(-12.1837402, -76.9553042), 10),
  ZonaPeligrosa("Pampas de San Juan", LatLng(-12.1669372, -76.9657831), 7),
  ZonaPeligrosa("María Auxiliadora (parte alta)", LatLng(-12.1654307, -76.9797152), 9),
  ZonaPeligrosa("Calle Rosendo Level", LatLng(-12.1654307, -76.9797152), 8),
  ZonaPeligrosa("Estación San Juan (Metro)", LatLng(-12.1565027, -76.9656846), 8),
  ZonaPeligrosa("Estación Atocongo (Metro)", LatLng(-12.1425706, -76.9821635), 7),
  ZonaPeligrosa("Asociación Roardi (La Molina)", LatLng(-12.0604019, -77.0469288), 6),
  ZonaPeligrosa("Sector Ciudad de Dios", LatLng(-7.1849968, -78.5314426), 10),
  ZonaPeligrosa("Calle Pedro Miotta", LatLng(-12.1612807, -76.9802997), 8),
  ZonaPeligrosa("Mercado Ciudad de Dios", LatLng(-12.1533763, -76.9714089), 9),
  ZonaPeligrosa("Parque Ernesto Giusti Acuña", LatLng(-12.127818, -76.983346), 7),
];

void construirGrafo(Grafo grafo) {
  // Ejemplo de conexiones manuales entre zonas
  grafo.agregarConInseguridad("Avenida San Juan", "Avenida Los Héroes",
    zonasPeligrosas[0].coordenada, zonasPeligrosas[1].coordenada,
    zonasPeligrosas[0].nivelInseguridad, zonasPeligrosas[1].nivelInseguridad);

  grafo.agregarConInseguridad("Avenida Los Héroes", "Mercado Ciudad de Dios",
    zonasPeligrosas[1].coordenada, zonasPeligrosas[15].coordenada,
    zonasPeligrosas[1].nivelInseguridad, zonasPeligrosas[15].nivelInseguridad);

  // Puedes seguir conectando los demás según tu lógica vial
} 
