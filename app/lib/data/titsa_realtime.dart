import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Una llegada prevista de una guagua a una parada (tiempo real, SAE de TITSA).
class Arrival {
  final int stopId;
  final String stopName;
  final int lineId;
  final String lineDestination;
  final int wayId;
  final int minutesLeft;

  Arrival({
    required this.stopId,
    required this.stopName,
    required this.lineId,
    required this.lineDestination,
    required this.wayId,
    required this.minutesLeft,
  });
}

/// Cliente del web service SAE de TITSA para tiempos de llegada en tiempo real.
///
/// La clave [idApp] la facilita TITSA. NO se incrusta en el código: se inyecta
/// desde configuración (--dart-define TITSA_ID_APP=...).
class TitsaRealtime {
  final String idApp;
  final String baseUrl;
  final http.Client _client;

  TitsaRealtime({
    required this.idApp,
    this.baseUrl = 'http://apps.titsa.com/apps',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Llegadas para una parada, ordenadas por minutos restantes.
  Future<List<Arrival>> arrivals(int stopId,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final uri = Uri.parse('$baseUrl/apps_sae_llegadas_parada.asp')
        .replace(queryParameters: {'idApp': idApp, 'idParada': '$stopId'});

    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('SAE respondió ${res.statusCode}');
    }
    return _parse(res.body)
      ..sort((a, b) => a.minutesLeft.compareTo(b.minutesLeft));
  }

  List<Arrival> _parse(String xmlBody) {
    final doc = XmlDocument.parse(xmlBody);
    final out = <Arrival>[];
    for (final e in doc.findAllElements('llegada')) {
      String t(String name) => e.getElement(name)?.innerText.trim() ?? '';
      int i(String name) => int.tryParse(t(name)) ?? 0;
      out.add(Arrival(
        stopId: i('codigoParada'),
        stopName: t('denominacion'),
        lineId: i('linea'),
        lineDestination: t('destinoLinea'),
        wayId: i('idTrayecto'),
        minutesLeft: i('minutosParaLlegar'),
      ));
    }
    return out;
  }

  void dispose() => _client.close();
}
