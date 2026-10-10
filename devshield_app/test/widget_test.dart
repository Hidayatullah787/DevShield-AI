import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devshield_app/app.dart';
import 'package:devshield_app/core/widgets/code_snippet_box.dart';
import 'package:devshield_app/core/widgets/severity_badge.dart';
import 'package:devshield_app/core/widgets/status_pill.dart';
import 'package:devshield_app/features/investigation/domain/investigation_models.dart';

void main() {
  testWidgets('DevShieldApp boots up and renders navigation header', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: DevShieldApp(),
      ),
    );
    await tester.pump();

    expect(find.text('DevShield AI'), findsWidgets);
    expect(find.byIcon(Icons.shield), findsWidgets);
  });

  testWidgets('SeverityBadge renders expected labels and styles', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SeverityBadge(severity: 'CRITICAL'),
              SeverityBadge(severity: 'HIGH'),
              SeverityBadge(severity: 'WARN'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('CRITICAL'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('WARN'), findsOneWidget);
  });

  testWidgets('StatusPill renders review status correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StatusPill(status: 'approved'),
              StatusPill(status: 'draft'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('DRAFT'), findsOneWidget);
  });

  testWidgets('CodeSnippetBox renders diff lines correctly', (WidgetTester tester) async {
    const diff = '''@@ -1,2 +1,2 @@
-timeout = 30
+timeout = 2''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CodeSnippetBox(
            title: 'diff_preview',
            content: diff,
            isDiff: true,
          ),
        ),
      ),
    );

    expect(find.text('diff_preview'), findsOneWidget);
    expect(find.text('+timeout = 2'), findsOneWidget);
    expect(find.text('-timeout = 30'), findsOneWidget);
  });

  test('Investigation models deserialization test', () {
    final json = {
      'job_id': 'job-test123',
      'title': 'Test Incident',
      'service': 'checkout',
      'environment': 'production',
      'severity': 'CRITICAL',
      'status': 'completed',
      'created_at': '2026-03-20T10:00:00Z',
      'summary': 'Connection pool exhausted',
      'has_change_correlation': true,
      'review_status': 'draft',
    };

    final model = InvestigationSummaryModel.fromJson(json);
    expect(model.jobId, 'job-test123');
    expect(model.service, 'checkout');
    expect(model.hasChangeCorrelation, true);
    expect(model.reviewStatus, 'draft');
  });

  test('ChangeCorrelationResultModel deserialization test', () {
    final json = {
      'total_files_analyzed': 2,
      'total_hunks_analyzed': 3,
      'overall_confidence': 0.85,
      'confidence_calculation_method': 'Rational saturating score function',
      'is_hypothesis': true,
      'degraded_mode': false,
      'ai_enriched': false,
      'matches': [
        {
          'file_path': 'services/db.py',
          'change_summary': 'services/db.py (+2, -2)',
          'matched_signals': ['timeout', 'pool'],
          'match_category': 'configuration_key',
          'evidence_context': 'Timeout error',
          'raw_score': 0.85,
          'hypothesis': 'The change in db.py may be correlated with timeout.',
          'explanation': 'Modifies pool timeout',
          'suggested_fix': 'Restore timeout to 30s',
          'verification_tests': ['Run unit tests'],
        }
      ],
    };

    final result = ChangeCorrelationResultModel.fromJson(json);
    expect(result.totalFilesAnalyzed, 2);
    expect(result.overallConfidence, 0.85);
    expect(result.matches.length, 1);
    expect(result.matches.first.filePath, 'services/db.py');
    expect(result.isHypothesis, true);
  });
}
