import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../domain/investigation_models.dart';

// Provider for list of all investigations
final investigationsListProvider = FutureProvider.autoDispose<List<InvestigationSummaryModel>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final rawList = await client.fetchInvestigations();
  return rawList.map((e) => InvestigationSummaryModel.fromJson(e)).toList();
});

// Family provider to load specific investigation details
final investigationDetailProvider =
    FutureProvider.autoDispose.family<InvestigationDetailModel, String>((ref, jobId) async {
  final client = ref.watch(apiClientProvider);
  final raw = await client.fetchInvestigationDetail(jobId);
  return InvestigationDetailModel.fromJson(raw);
});

// State for active submission of an investigation
class NewInvestigationState {
  final bool isSubmitting;
  final String? currentStage;
  final String? errorMessage;
  final InvestigationDetailModel? result;

  NewInvestigationState({
    this.isSubmitting = false,
    this.currentStage,
    this.errorMessage,
    this.result,
  });

  NewInvestigationState copyWith({
    bool? isSubmitting,
    String? currentStage,
    String? errorMessage,
    InvestigationDetailModel? result,
  }) {
    return NewInvestigationState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      currentStage: currentStage ?? this.currentStage,
      errorMessage: errorMessage,
      result: result ?? this.result,
    );
  }
}

class NewInvestigationNotifier extends StateNotifier<NewInvestigationState> {
  final ApiClient _client;
  final Ref _ref;

  NewInvestigationNotifier(this._client, this._ref) : super(NewInvestigationState());

  Future<InvestigationDetailModel?> startInvestigation({
    required String title,
    required String service,
    required String environment,
    String? rawLogs,
    String? rawDiff,
  }) async {
    state = state.copyWith(
      isSubmitting: true,
      currentStage: 'Validating telemetry & code diff input...',
      errorMessage: null,
    );

    try {
      // Stage 1: Validation
      await Future.delayed(const Duration(milliseconds: 250));
      state = state.copyWith(currentStage: 'Normalizing logs & detecting anomaly spikes...');

      // Stage 2: Normalization & Telemetry
      await Future.delayed(const Duration(milliseconds: 300));
      state = state.copyWith(currentStage: 'Correlating error signals with code changes...');

      // Stage 3: Correlate and execute pipeline
      final response = await _client.submitInvestigation(
        title: title,
        service: service,
        environment: environment,
        rawLogs: rawLogs,
        rawDiff: rawDiff,
      );

      state = state.copyWith(currentStage: 'Synthesizing evidence-backed remediation hypotheses...');
      await Future.delayed(const Duration(milliseconds: 200));

      final detail = InvestigationDetailModel.fromJson(response);
      state = state.copyWith(
        isSubmitting: false,
        currentStage: 'Investigation complete',
        result: detail,
      );

      // Invalidate list provider so history and dashboard update automatically
      _ref.invalidate(investigationsListProvider);
      _ref.invalidate(apiInfoProvider);

      return detail;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        currentStage: null,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  void reset() {
    state = NewInvestigationState();
  }
}

final newInvestigationProvider =
    StateNotifierProvider<NewInvestigationNotifier, NewInvestigationState>((ref) {
  final client = ref.watch(apiClientProvider);
  return NewInvestigationNotifier(client, ref);
});

