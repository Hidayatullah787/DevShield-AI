import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

// StateProvider for the configurable API Base URL
final apiBaseUrlProvider = StateProvider<String>((ref) => AppConstants.defaultBaseUrl);

// Provider for ApiClient
final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  return ApiClient(baseUrl: baseUrl);
});

// AsyncProvider for checking API Connection & Info
final apiInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final client = ref.watch(apiClientProvider);
  return client.fetchApiInfo();
});

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  final http.Client _httpClient;

  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  String _cleanUrl(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  Future<Map<String, dynamic>> fetchApiInfo() async {
    try {
      final uri = Uri.parse(_cleanUrl('/api-info'));
      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      throw ApiException('API returned HTTP ${response.statusCode}: ${response.body}', response.statusCode);
    } on TimeoutException {
      throw ApiException('Connection timed out connecting to $baseUrl. Verify backend is running.');
    } on http.ClientException catch (e) {
      throw ApiException('Failed to reach backend at $baseUrl ($e). Check URL and port.');
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> validateInput({
    String? rawLogs,
    String? rawDiff,
    String service = 'api-service',
    String environment = 'production',
  }) async {
    final uri = Uri.parse(_cleanUrl('/validate-input'));
    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'raw_logs': rawLogs,
            'raw_diff': rawDiff,
            'service': service,
            'environment': environment,
          }),
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Validation failed (${response.statusCode}): ${response.body}');
  }

  Future<Map<String, dynamic>> submitInvestigation({
    required String title,
    required String service,
    required String environment,
    String? rawLogs,
    String? rawDiff,
  }) async {
    final uri = Uri.parse(_cleanUrl('/investigate'));
    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'title': title,
            'service': service,
            'environment': environment,
            'raw_logs': rawLogs,
            'raw_diff': rawDiff,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Investigation failed (${response.statusCode}): ${response.body}');
  }

  Future<List<Map<String, dynamic>>> fetchInvestigations({String? service, String? severity}) async {
    var path = '/investigations';
    final params = <String>[];
    if (service != null && service.isNotEmpty) params.add('service=$service');
    if (severity != null && severity.isNotEmpty) params.add('severity=$severity');
    if (params.isNotEmpty) path += '?${params.join('&')}';

    final uri = Uri.parse(_cleanUrl(path));
    final response = await _httpClient.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw ApiException('Failed to load investigations (${response.statusCode})');
  }

  Future<Map<String, dynamic>> fetchInvestigationDetail(String jobId) async {
    final uri = Uri.parse(_cleanUrl('/investigations/$jobId'));
    final response = await _httpClient.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to load investigation $jobId (${response.statusCode})');
  }

  Future<Map<String, dynamic>> transitionReview({
    required String jobId,
    required String toStatus,
    required String reviewer,
    required String note,
  }) async {
    final uri = Uri.parse(_cleanUrl('/investigations/$jobId/review'));
    final response = await _httpClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'to_status': toStatus,
            'reviewer': reviewer,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to transition review (${response.statusCode}): ${response.body}');
  }

  Future<String> exportReport({required String jobId, required String format}) async {
    final uri = Uri.parse(_cleanUrl('/investigations/$jobId/export/$format'));
    final response = await _httpClient.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return response.body;
    }
    throw ApiException('Export failed (${response.statusCode})');
  }

  Future<void> seedSamples() async {
    final uri = Uri.parse(_cleanUrl('/seed-samples'));
    final response = await _httpClient.post(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ApiException('Failed to seed sample incidents (${response.statusCode})');
    }
  }
}

