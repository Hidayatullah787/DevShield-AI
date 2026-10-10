class InvestigationSummaryModel {
  final String jobId;
  final String title;
  final String service;
  final String environment;
  final String severity;
  final String status;
  final String createdAt;
  final String summary;
  final bool hasChangeCorrelation;
  final String reviewStatus;

  InvestigationSummaryModel({
    required this.jobId,
    required this.title,
    required this.service,
    required this.environment,
    required this.severity,
    required this.status,
    required this.createdAt,
    required this.summary,
    required this.hasChangeCorrelation,
    required this.reviewStatus,
  });

  factory InvestigationSummaryModel.fromJson(Map<String, dynamic> json) {
    return InvestigationSummaryModel(
      jobId: json['job_id'] ?? '',
      title: json['title'] ?? 'Incident Investigation',
      service: json['service'] ?? 'api-service',
      environment: json['environment'] ?? 'production',
      severity: json['severity'] ?? 'HIGH',
      status: json['status'] ?? 'completed',
      createdAt: json['created_at'] ?? '',
      summary: json['summary'] ?? '',
      hasChangeCorrelation: json['has_change_correlation'] ?? false,
      reviewStatus: json['review_status'] ?? 'draft',
    );
  }
}

class CorrelationMatchModel {
  final String filePath;
  final String changeSummary;
  final List<String> matchedSignals;
  final String matchCategory;
  final String evidenceContext;
  final double rawScore;
  final String hypothesis;
  final String explanation;
  final String suggestedFix;
  final List<String> verificationTests;

  CorrelationMatchModel({
    required this.filePath,
    required this.changeSummary,
    required this.matchedSignals,
    required this.matchCategory,
    required this.evidenceContext,
    required this.rawScore,
    required this.hypothesis,
    required this.explanation,
    required this.suggestedFix,
    required this.verificationTests,
  });

  factory CorrelationMatchModel.fromJson(Map<String, dynamic> json) {
    return CorrelationMatchModel(
      filePath: json['file_path'] ?? '',
      changeSummary: json['change_summary'] ?? '',
      matchedSignals: (json['matched_signals'] as List?)?.cast<String>() ?? [],
      matchCategory: json['match_category'] ?? 'component_path',
      evidenceContext: json['evidence_context'] ?? '',
      rawScore: (json['raw_score'] as num?)?.toDouble() ?? 0.0,
      hypothesis: json['hypothesis'] ?? '',
      explanation: json['explanation'] ?? '',
      suggestedFix: json['suggested_fix'] ?? '',
      verificationTests: (json['verification_tests'] as List?)?.cast<String>() ?? [],
    );
  }
}

class ChangeCorrelationResultModel {
  final int totalFilesAnalyzed;
  final int totalHunksAnalyzed;
  final List<CorrelationMatchModel> matches;
  final CorrelationMatchModel? topMatch;
  final double overallConfidence;
  final String confidenceCalculationMethod;
  final bool isHypothesis;
  final bool degradedMode;
  final bool aiEnriched;
  final String? warning;

  ChangeCorrelationResultModel({
    required this.totalFilesAnalyzed,
    required this.totalHunksAnalyzed,
    required this.matches,
    this.topMatch,
    required this.overallConfidence,
    required this.confidenceCalculationMethod,
    required this.isHypothesis,
    required this.degradedMode,
    required this.aiEnriched,
    this.warning,
  });

  factory ChangeCorrelationResultModel.fromJson(Map<String, dynamic> json) {
    final matchesList = (json['matches'] as List?)
            ?.map((e) => CorrelationMatchModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    CorrelationMatchModel? top;
    if (json['top_correlated_change'] != null) {
      top = CorrelationMatchModel.fromJson(json['top_correlated_change']);
    } else if (matchesList.isNotEmpty) {
      top = matchesList.first;
    }

    return ChangeCorrelationResultModel(
      totalFilesAnalyzed: json['total_files_analyzed'] ?? 0,
      totalHunksAnalyzed: json['total_hunks_analyzed'] ?? 0,
      matches: matchesList,
      topMatch: top,
      overallConfidence: (json['overall_confidence'] as num?)?.toDouble() ?? 0.0,
      confidenceCalculationMethod: json['confidence_calculation_method'] ?? '',
      isHypothesis: json['is_hypothesis'] ?? true,
      degradedMode: json['degraded_mode'] ?? false,
      aiEnriched: json['ai_enriched'] ?? false,
      warning: json['warning'],
    );
  }
}

class IncidentReportModel {
  final String title;
  final String severity;
  final String impactedService;
  final String incidentSummary;
  final List<String> likelyRootCauses;
  final List<String> recommendedActions;
  final List<Map<String, dynamic>> evidence;

  IncidentReportModel({
    required this.title,
    required this.severity,
    required this.impactedService,
    required this.incidentSummary,
    required this.likelyRootCauses,
    required this.recommendedActions,
    required this.evidence,
  });

  factory IncidentReportModel.fromJson(Map<String, dynamic> json) {
    return IncidentReportModel(
      title: json['title'] ?? '',
      severity: json['severity'] ?? 'HIGH',
      impactedService: json['impacted_service'] ?? 'service',
      incidentSummary: json['incident_summary'] ?? '',
      likelyRootCauses: (json['likely_root_causes'] as List?)?.cast<String>() ?? [],
      recommendedActions: (json['recommended_actions'] as List?)?.cast<String>() ?? [],
      evidence: (json['evidence'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
  }
}

class InvestigationDetailModel {
  final String jobId;
  final String title;
  final String service;
  final String environment;
  final String severity;
  final String status;
  final String createdAt;
  final String incidentSummary;
  final IncidentReportModel report;
  final ChangeCorrelationResultModel? changeCorrelation;
  final String reviewStatus;
  final Map<String, dynamic> aiProviderInfo;

  InvestigationDetailModel({
    required this.jobId,
    required this.title,
    required this.service,
    required this.environment,
    required this.severity,
    required this.status,
    required this.createdAt,
    required this.incidentSummary,
    required this.report,
    this.changeCorrelation,
    required this.reviewStatus,
    required this.aiProviderInfo,
  });

  factory InvestigationDetailModel.fromJson(Map<String, dynamic> json) {
    final reportJson = json['report'] as Map<String, dynamic>? ?? {};
    final changeJson = json['change_correlation'] as Map<String, dynamic>?;

    return InvestigationDetailModel(
      jobId: json['job_id'] ?? '',
      title: json['title'] ?? 'Incident Investigation',
      service: json['service'] ?? 'api-service',
      environment: json['environment'] ?? 'production',
      severity: json['severity'] ?? 'HIGH',
      status: json['status'] ?? 'completed',
      createdAt: json['created_at'] ?? '',
      incidentSummary: json['incident_summary'] ?? '',
      report: IncidentReportModel.fromJson(reportJson),
      changeCorrelation: changeJson != null ? ChangeCorrelationResultModel.fromJson(changeJson) : null,
      reviewStatus: json['review_status'] ?? 'draft',
      aiProviderInfo: json['ai_provider_info'] as Map<String, dynamic>? ?? {},
    );
  }
}

