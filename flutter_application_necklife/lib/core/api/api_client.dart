import 'package:dio/dio.dart';
import '../auth/auth_service.dart';

// URL de base du backend — remplacer par l'URL Firebase Functions réelle
const String urlApiBase = "https://YOUR_PROJECT_ID.cloudfunctions.net/api";

class ApiClient {
  late final Dio _dio;
  final AuthService _authService;

  ApiClient(this._authService) {
    _dio = Dio(BaseOptions(
      baseUrl: urlApiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // Intercepteur : injecte le token JWT à chaque requête
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _ajouterTokenJwt,
      onError: _gererErreur,
    ));
  }

  // ---------------------------------------------------------------------------
  // Intercepteur — récupère et injecte le token Firebase dans les headers
  // ---------------------------------------------------------------------------
  Future<void> _ajouterTokenJwt(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _authService.obtenirToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // ---------------------------------------------------------------------------
  // Intercepteur — gestion centralisée des erreurs HTTP
  // ---------------------------------------------------------------------------
  Future<void> _gererErreur(
    DioException erreur,
    ErrorInterceptorHandler handler,
  ) async {
    if (erreur.response?.statusCode == 401) {
      // Token expiré → déconnexion automatique
      await _authService.deconnecter();
    }
    handler.next(erreur);
  }

  // ---------------------------------------------------------------------------
  // Envoyer une alerte de chute au backend
  // ---------------------------------------------------------------------------
  Future<void> envoyerAlerte({
    required String userId,
    required DateTime timestamp,
    required double magnitude,
  }) async {
    await _dio.post('/alertes', data: {
      'userId':    userId,
      'timestamp': timestamp.toIso8601String(),
      'magnitude': magnitude,
      'type':      'CHUTE',
    });
  }

  // ---------------------------------------------------------------------------
  // Envoyer les réponses du quiz bien-être
  // ---------------------------------------------------------------------------
  Future<void> envoyerBienEtre({
    required String userId,
    required int score,
    required List<int> reponses,
  }) async {
    await _dio.post('/bienetre', data: {
      'userId':   userId,
      'score':    score,
      'reponses': reponses,
      'date':     DateTime.now().toIso8601String(),
    });
  }

  // ---------------------------------------------------------------------------
  // Récupérer l'historique des alertes d'un utilisateur
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> obtenirHistoriqueAlertes(
    String userId,
  ) async {
    final reponse = await _dio.get('/alertes/$userId');
    return List<Map<String, dynamic>>.from(reponse.data as List);
  }
}
