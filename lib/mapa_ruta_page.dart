import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_google_places/flutter_google_places.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:google_maps_webservice/geocoding.dart';
import 'package:google_maps_webservice/directions.dart' as directions;
import 'package:flutter/foundation.dart'; // para compute()
import 'package:flutter/gestures.dart';
import 'grafo.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:uuid/uuid.dart';
import 'ruta_segura_controller.dart';

const String googleApiKey = 'AIzaSyAR4vFAk43C3sTnO-YEu-7g1kkT23mW9es';

enum RouteType { fast, safe }

class MapaRutaPage extends StatefulWidget {
  const MapaRutaPage({super.key});

  @override
  State<MapaRutaPage> createState() => _MapaRutaPageState();
}

class _MapaRutaPageState extends State<MapaRutaPage> {
  LatLng? _origenManual;
  LatLng? _destinoManual;
  GoogleMapController? _mapController;
  Position? _posicionActual;
  final TextEditingController _origenController = TextEditingController();
  final TextEditingController _destinoController = TextEditingController();
  final Set<Polyline> _rutas = {};
  final Set<Marker> _marcadores = {};
  final Set<Circle> _circulosPeligro = {};
  bool _mapaListo = false;
  bool _seleccionandoOrigenManual = false;
  bool _cargandoRuta = false; // loader para la ruta
  bool _cargandoBusqueda = false; // loader para el autocompletado
  RouteType _tipoRuta = RouteType.safe; // Por defecto, ruta segura
  late RutaSeguraController _rutaSeguraController;

  final LatLng _centroSJM = LatLng(-12.1633, -76.9636);
  final LatLngBounds _limitesSJM = LatLngBounds(
    southwest: LatLng(-12.2000, -77.0100),
    northeast: LatLng(-12.1200, -76.9400),
  );

  final Grafo _grafo = Grafo();
  final GoogleMapsGeocoding _geocoding = GoogleMapsGeocoding(
    apiKey: googleApiKey,
  );
  final directions.GoogleMapsDirections _directions =
      directions.GoogleMapsDirections(apiKey: googleApiKey);

  // Definir colores personalizados
  final Color _primaryColor = const Color(0xFF6C63FF); // Morado elegante
  final Color _accentColor = const Color(0xFFFF6584); // Rosa moderno
  final Color _backgroundColor = const Color(0xFFF8F9FE); // Fondo suave
  final Color _textColor = const Color(0xFF2D3142); // Texto oscuro elegante

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await _obtenerUbicacion();
        if (!mounted) return;
        _generarCirculosZonasPeligrosas();
        construirGrafo(_grafo);
        _rutaSeguraController = RutaSeguraController(
          grafo: _grafo,
          zonasPeligrosas: zonasPeligrosas,
          rutas: _rutas,
          context: context,
        );
      } catch (e) {
        debugPrint("Error en initState: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error al inicializar el mapa"),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  List<String> _rutaConDijkstra(List<dynamic> args) {
    final grafo = args[0] as Grafo;
    final String inicio = args[1];
    final String fin = args[2];
    return grafo.dijkstra(inicio, fin);
  }

  void _generarCirculosZonasPeligrosas() {
    setState(() {
      _circulosPeligro.addAll(
        zonasPeligrosas.map((zona) {
          // Normalizar el nivel de inseguridad de 5-10 a 0-1 para la opacidad
          final opacidad = (zona.nivelInseguridad - 5) / 5.0;
          // Ajustar el color según el nivel de peligro
          final color = Color.fromRGBO(
            255, // Rojo
            (255 * (1 - opacidad)).round(), // Verde (menos verde = más rojo)
            0, // Sin azul
            opacidad * 0.5 + 0.2, // Opacidad base de 0.2 a 0.7
          );

          return Circle(
            circleId: CircleId(zona.nombre),
            center: zona.coordenada,
            radius: 120,
            strokeWidth: 2,
            strokeColor: color,
            fillColor: color.withAlpha((0.35 * 255).toInt()),
          );
        }),
      );
    });
  }

  Future<void> _obtenerUbicacion() async {
    try {
      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Se requiere permiso de ubicación para usar esta función",
              ),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }

      if (permiso == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Los permisos de ubicación están permanentemente denegados",
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      setState(() {
        _cargandoBusqueda = true;
        _seleccionandoOrigenManual =
            false; // Cancelar selección manual al usar ubicación actual
      });

      try {
        final posicion = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

        if (!mounted) return;

        // Obtener la dirección de la ubicación actual
        final direccion = await _obtenerDireccion(
          LatLng(posicion.latitude, posicion.longitude),
        );

        setState(() {
          _posicionActual = posicion;
          _origenManual = LatLng(posicion.latitude, posicion.longitude);
          _origenController.text = direccion;

          // Actualizar el marcador de origen
          _marcadores.removeWhere((m) => m.markerId.value == "origen_manual");
          _marcadores.add(
            Marker(
              markerId: const MarkerId("origen_manual"),
              position: _origenManual!,
              draggable: true,
              onDragEnd: (LatLng newPosition) {
                _actualizarMarcadorYDireccion(newPosition, true);
                if (_destinoManual != null) _trazarRutaEntrePuntos();
              },
              infoWindow: InfoWindow(title: direccion),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueViolet,
              ),
            ),
          );

          // Centrar el mapa en la ubicación actual
          if (_mapaListo && _mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(posicion.latitude, posicion.longitude),
                15.0,
              ),
            );
          }
        });

        // Actualizar la ruta si hay un destino definido
        if (_destinoManual != null) {
          await _trazarRutaEntrePuntos();
        }
      } catch (e) {
        debugPrint("Error al obtener la posición actual: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No se pudo obtener la ubicación actual. Intente nuevamente.",
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error en permisos de ubicación: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error al verificar permisos de ubicación"),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cargandoBusqueda = false);
      }
    }
  }

  Future<void> _trazarRutaEntrePuntos() async {
    if (_origenManual == null || _destinoManual == null) {
      debugPrint("Origen o destino no definidos");
      return;
    }

    // Validar que las coordenadas estén dentro de los límites
    if (!_limitesSJM.contains(_origenManual!) ||
        !_limitesSJM.contains(_destinoManual!)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Las ubicaciones deben estar dentro de San Juan de Miraflores",
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _cargandoRuta = true);

    try {
      if (_tipoRuta == RouteType.fast) {
        await _trazarRutaRapida();
      } else {
        await _trazarRutaSegura();
      }
    } catch (e) {
      debugPrint("Error al trazar la ruta: $e");
      if (!mounted) return;
      setState(() => _cargandoRuta = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error al trazar la ruta: ${e.toString()}"),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _trazarRutaRapida() async {
    try {
      final response = await _directions.directionsWithLocation(
        directions.Location(
          lat: _origenManual!.latitude,
          lng: _origenManual!.longitude,
        ),
        directions.Location(
          lat: _destinoManual!.latitude,
          lng: _destinoManual!.longitude,
        ),
        travelMode: directions.TravelMode.driving,
      );

      if (response.status != "OK") {
        throw Exception("No se pudo obtener la ruta: ${response.errorMessage}");
      }

      if (response.routes.isEmpty) {
        throw Exception(
          "No se encontró una ruta entre los puntos seleccionados",
        );
      }

      final route = response.routes.first;
      final points = route.legs.first.steps
          .expand(
            (step) => PolylinePoints().decodePolyline(step.polyline.points),
          )
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      if (!mounted) return;
      setState(() {
        _rutas.clear();
        _rutas.add(
          Polyline(
            polylineId: const PolylineId("ruta_rapida"),
            points: points,
            color: Colors.blue,
            width: 6,
          ),
        );
        _cargandoRuta = false;
      });
    } catch (e) {
      debugPrint("Error al trazar ruta rápida: $e");
      rethrow;
    }
  }

  Future<void> _trazarRutaSegura() async {
    await _rutaSeguraController.trazarRutaSegura(_origenManual, _destinoManual);
    setState(() => _cargandoRuta = false);
  }

  Future<String> _obtenerDireccion(LatLng posicion) async {
    try {
      final response = await _geocoding.searchByLocation(
        Location(lat: posicion.latitude, lng: posicion.longitude),
      );

      if (response.status == "OK" && response.results.isNotEmpty) {
        return response.results.first.formattedAddress ??
            'Dirección no encontrada';
      }
      return 'Dirección no encontrada';
    } catch (e) {
      debugPrint("Error al obtener la dirección: $e");
      return 'Error al obtener la dirección';
    }
  }

  void _actualizarMarcadorYDireccion(LatLng posicion, bool esOrigen) async {
    try {
      final direccion = await _obtenerDireccion(posicion);
      if (!mounted) return;

      setState(() {
        if (esOrigen) {
          _origenManual = posicion;
          _origenController.text = direccion;
          _seleccionandoOrigenManual = false;
          _marcadores.removeWhere((m) => m.markerId.value == "origen_manual");
          _marcadores.add(
            Marker(
              markerId: const MarkerId("origen_manual"),
              position: posicion,
              draggable: true,
              onDragEnd: (LatLng newPosition) {
                _actualizarMarcadorYDireccion(newPosition, true);
                if (_destinoManual != null) {
                  _trazarRutaEntrePuntos();
                }
              },
              infoWindow: InfoWindow(title: direccion),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueViolet,
              ),
            ),
          );
        } else {
          _destinoManual = posicion;
          _destinoController.text = direccion;
          _marcadores.removeWhere((m) => m.markerId.value == "destino_manual");
          _marcadores.add(
            Marker(
              markerId: const MarkerId("destino_manual"),
              position: posicion,
              draggable: true,
              onDragEnd: (LatLng newPosition) {
                _actualizarMarcadorYDireccion(newPosition, false);
                if (_origenManual != null) {
                  _trazarRutaEntrePuntos();
                }
              },
              infoWindow: InfoWindow(title: direccion),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRose,
              ),
            ),
          );
        }
      });

      // Actualizar la ruta si ambos puntos están definidos
      if (_origenManual != null && _destinoManual != null) {
        await _trazarRutaEntrePuntos();
      }
    } catch (e) {
      debugPrint("Error al actualizar marcador y dirección: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error al actualizar la ubicación"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _mostrarAutocompletado(BuildContext context) async {
    if (!mounted) return;

    try {
      // Mostrar la búsqueda de lugar con Google Places
      final Prediction? p = await PlacesAutocomplete.show(
        context: context,
        apiKey: googleApiKey,
        mode: Mode.overlay,
        language: "es",
        components: [Component(Component.country, "pe")],
      );

      if (p == null || !mounted) return;

      setState(() => _cargandoBusqueda = true);

      final places = GoogleMapsPlaces(apiKey: googleApiKey);
      final response = await places.getDetailsByPlaceId(p.placeId!);
      places.dispose();

      if (!mounted || response.status != "OK") return;

      final location = response.result.geometry?.location;
      if (location == null) return;

      LatLng nuevaPos = LatLng(location.lat, location.lng);
      _actualizarMarcadorYDireccion(nuevaPos, false);
      await _trazarRutaEntrePuntos();

      if (_mapaListo && _mapController != null && mounted) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(nuevaPos, 16));
      }
    } catch (e) {
      debugPrint("Error en búsqueda de dirección: $e");
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Hubo un error al buscar la dirección")),
      );
    } finally {
      if (mounted) {
        setState(() => _cargandoBusqueda = false);
      }
    }
  }

  Future<void> actualizarDireccionesAmbas(LatLng origen, LatLng destino) async {
    final resultados = await Future.wait([
      _obtenerDireccion(origen),
      _obtenerDireccion(destino),
    ]);
    final direccionOrigen = resultados[0];
    final direccionDestino = resultados[1];

    setState(() {
      _origenController.text = direccionOrigen;
      _destinoController.text = direccionDestino;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _primaryColor,
        title: const Text(
          'Rutas Seguras SJM ❤️',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              setState(() {
                _origenManual = null;
                _destinoManual = null;
                _rutas.clear();
                _seleccionandoOrigenManual = false;
                _marcadores.removeWhere(
                  (m) =>
                      m.markerId.value == "origen_manual" ||
                      m.markerId.value == "destino_manual",
                );
                _origenController.clear();
                _destinoController.clear();
              });
            },
            tooltip: 'Limpiar ruta',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Column(
                  children: [
                    TextField(
                      controller: _origenController,
                      readOnly: true,
                      onTap: () {
                        setState(() {
                          _seleccionandoOrigenManual = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Toque en el mapa para seleccionar el origen",
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Origen',
                        filled: true,
                        fillColor: _backgroundColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          Icons.location_on,
                          color: _primaryColor,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_origenManual != null)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _origenManual = null;
                                    _origenController.clear();
                                    _seleccionandoOrigenManual = false;
                                    _marcadores.removeWhere(
                                      (m) =>
                                          m.markerId.value == "origen_manual",
                                    );
                                    _rutas.clear();
                                  });
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.my_location),
                              onPressed: () {
                                _obtenerUbicacion();
                              },
                              tooltip: 'Usar ubicación actual',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TypeAheadField<Prediction>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: _destinoController,
                    decoration: InputDecoration(
                      hintText: 'Buscar destino',
                      filled: true,
                      fillColor: _backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.place, color: _accentColor),
                      suffixIcon: _destinoManual != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _destinoManual = null;
                                  _destinoController.clear();
                                  _seleccionandoOrigenManual = false;
                                  _marcadores.removeWhere(
                                    (m) => m.markerId.value == "destino_manual",
                                  );
                                  _rutas.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    onTap: () {
                      setState(() {
                        _seleccionandoOrigenManual = false;
                      });
                    },
                  ),
                  suggestionsCallback: (pattern) async {
                    if (pattern.isEmpty) return [];
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _seleccionandoOrigenManual = false;
                        });
                      }
                    });
                    final sessionToken = const Uuid().v4();
                    final places = GoogleMapsPlaces(apiKey: googleApiKey);
                    final response = await places.autocomplete(
                      pattern,
                      components: [Component(Component.country, "pe")],
                      sessionToken: sessionToken,
                    );
                    return response.predictions;
                  },
                  itemBuilder: (context, Prediction suggestion) {
                    return ListTile(
                      leading: const Icon(Icons.place),
                      title: Text(suggestion.description ?? ""),
                    );
                  },
                  onSuggestionSelected: (Prediction suggestion) async {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _cargandoBusqueda = true;
                          _seleccionandoOrigenManual = false;
                        });
                      }
                    });
                    try {
                      final places = GoogleMapsPlaces(apiKey: googleApiKey);
                      final detail = await places.getDetailsByPlaceId(
                        suggestion.placeId!,
                      );
                      final location = detail.result.geometry?.location;

                      if (location != null) {
                        final destino = LatLng(location.lat, location.lng);
                        _actualizarMarcadorYDireccion(destino, false);
                        await _trazarRutaEntrePuntos();
                        if (_mapaListo && _mapController != null) {
                          _mapController!.animateCamera(
                            CameraUpdate.newLatLngZoom(destino, 16),
                          );
                        }
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Error al obtener la ubicación del destino",
                          ),
                        ),
                      );
                    } finally {
                      if (mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() => _cargandoBusqueda = false);
                          }
                        });
                      }
                    }
                  },
                ),
                if (_origenManual != null && _destinoManual != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        Text(
                          'Tipo de ruta:',
                          style: TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SegmentedButton<RouteType>(
                            segments: const [
                              ButtonSegment<RouteType>(
                                value: RouteType.fast,
                                label: Text('Rápida'),
                                icon: Icon(Icons.speed),
                              ),
                              ButtonSegment<RouteType>(
                                value: RouteType.safe,
                                label: Text('Segura'),
                                icon: Icon(Icons.security),
                              ),
                            ],
                            selected: {_tipoRuta},
                            style: ButtonStyle(
                              backgroundColor: MaterialStateProperty.all(
                                _backgroundColor,
                              ),
                              foregroundColor:
                                  MaterialStateProperty.resolveWith((states) {
                                    if (states.contains(
                                      MaterialState.selected,
                                    )) {
                                      return _tipoRuta == RouteType.fast
                                          ? _primaryColor
                                          : _accentColor;
                                    }
                                    return _textColor;
                                  }),
                            ),
                            onSelectionChanged: (Set<RouteType> newSelection) {
                              setState(() {
                                _tipoRuta = newSelection.first;
                              });
                              _trazarRutaEntrePuntos();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_cargandoBusqueda)
            LinearProgressIndicator(
              backgroundColor: _backgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
              minHeight: 4,
            ),
          if (_cargandoRuta)
            LinearProgressIndicator(
              backgroundColor: _backgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
            ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _centroSJM,
                    zoom: 14.0,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _mapaListo = true;
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  markers: _marcadores,
                  polylines: _rutas,
                  circles: _circulosPeligro,
                  cameraTargetBounds: CameraTargetBounds(_limitesSJM),
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                    Factory<ScaleGestureRecognizer>(
                      () => ScaleGestureRecognizer(),
                    ),
                    Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
                  },
                  onTap: (LatLng position) {
                    // Verificar si se tocó un círculo
                    for (var circle in _circulosPeligro) {
                      final distancia = Geolocator.distanceBetween(
                        position.latitude,
                        position.longitude,
                        circle.center.latitude,
                        circle.center.longitude,
                      );
                      if (distancia <= circle.radius) {
                        final zona = zonasPeligrosas.firstWhere(
                          (z) => z.nombre == circle.circleId.value,
                          orElse: () => throw Exception('Zona no encontrada'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Zona: ${zona.nombre}\nNivel de inseguridad: ${zona.nivelInseguridad}',
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        return;
                      }
                    }

                    // Verificar si se tocó un marcador
                    for (var marker in _marcadores) {
                      final distancia = Geolocator.distanceBetween(
                        position.latitude,
                        position.longitude,
                        marker.position.latitude,
                        marker.position.longitude,
                      );
                      if (distancia <= 20) {
                        // 20 metros de tolerancia
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              marker.infoWindow.title ??
                                  'Ubicación seleccionada',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                    }

                    if (_seleccionandoOrigenManual) {
                      _actualizarMarcadorYDireccion(position, true);
                      _seleccionandoOrigenManual = false;
                    } else {
                      _actualizarMarcadorYDireccion(position, false);
                    }
                  },
                ),
                if (_seleccionandoOrigenManual)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _primaryColor.withOpacity(0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app, color: _primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            "Toque en el mapa para seleccionar el origen",
                            style: TextStyle(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Leyenda de niveles de riesgo
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Niveles de Riesgo',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildRiskLegendItem('Alto', Colors.red),
                            const SizedBox(width: 12),
                            _buildRiskLegendItem('Medio', Colors.orange),
                            const SizedBox(width: 12),
                            _buildRiskLegendItem('Bajo', Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  void dispose() {
    _origenController.dispose();
    _destinoController.dispose();
    _mapController?.dispose();
    _geocoding.dispose();
    _directions.dispose();
    super.dispose();
  }
}
