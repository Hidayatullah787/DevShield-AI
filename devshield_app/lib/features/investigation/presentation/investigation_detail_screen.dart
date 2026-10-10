import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/code_snippet_box.dart';
import '../../../core/widgets/severity_badge.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/investigation_notifier.dart';
import '../domain/investigation_models.dart';

class InvestigationDetailScreen extends ConsumerStatefulWidget {
  final String jobId;

  const InvestigationDetailScreen({super.key, required this.jobId});

  @override
  ConsumerState<InvestigationDetailScreen> createState() => _InvestigationDetailScreenState();
}

class _InvestigationDetailScreenState extends ConsumerState<InvestigationDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showReviewDialog(InvestigationDetailModel detail) async {
    final noteController = TextEditingController();
    String selectedStatus = 'approved';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Update Investigation Review', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Audit transition lifecycle status:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedStatus,
                decoration: const InputDecoration(labelText: 'Review Status'),
                dropdownColor: AppColors.surface,
                items: const [
                  DropdownMenuItem(value: 'reviewed', child: Text('Reviewed (Under Evaluation)')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved (Fix Confirmed)')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected (Unrelated)')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedStatus = v);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reviewer Note',
                  hintText: 'e.g. Confirmed with team lead that pool size was decreased in commit.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Review'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        final client = ref.read(apiClientProvider);
        await client.transitionReview(
          jobId: detail.jobId,
          toStatus: selectedStatus,
          reviewer: 'Engineer (DevShield)',
          note: noteController.text.trim().isEmpty ? 'Review updated in UI' : noteController.text.trim(),
        );
        ref.invalidate(investigationDetailProvider(widget.jobId));
        ref.invalidate(investigationsListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Status updated to $selectedStatus')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update status: $e')),
          );
        }
      }
    }
  }

  Future<void> _exportReport(String format) async {
    try {
      final client = ref.read(apiClientProvider);
      final report = await client.exportReport(jobId: widget.jobId, format: format);
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${format.toUpperCase()} report copied to clipboard!'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(investigationDetailProvider(widget.jobId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Investigation ${widget.jobId}'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download, size: 20),
            tooltip: 'Export Report',
            color: AppColors.surface,
            onSelected: (val) => _exportReport(val),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'markdown',
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Export Markdown'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'json',
                child: Row(
                  children: [
                    Icon(Icons.code, size: 16, color: AppColors.secondary),
                    SizedBox(width: 8),
                    Text('Export JSON'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: detailAsync.when(
        data: (detail) => _buildDetailContent(detail),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40, color: AppColors.critical),
                const SizedBox(height: 12),
                Text('Failed to load investigation: $e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(investigationDetailProvider(widget.jobId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailContent(InvestigationDetailModel detail) {
    return Column(
      children: [
        // Top Overview Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SeverityBadge(severity: detail.severity),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Service: ${detail.service} • Environment: ${detail.environment} • Created: ${detail.createdAt.split("T").first}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      StatusPill(status: detail.reviewStatus),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.rate_review_outlined, size: 14),
                        label: const Text('Review', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: () => _showReviewDialog(detail),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                detail.incidentSummary,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),

        // Navigation Tabs
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            const Tab(text: 'Hypotheses'),
            Tab(
              child: Row(
                children: [
                  const Text('Change Impact'),
                  if (detail.changeCorrelation?.matches.isNotEmpty == true) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${detail.changeCorrelation!.matches.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Remediation & Tests'),
            const Tab(text: 'Evidence'),
            const Tab(text: 'AI Status & Export'),
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildHypothesesTab(detail),
              _buildChangeCorrelationTab(detail),
              _buildRemediationTab(detail),
              _buildEvidenceTab(detail),
              _buildExportTab(detail),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHypothesesTab(InvestigationDetailModel detail) {
    final causes = detail.report.likelyRootCauses;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.info.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.info),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hypotheses are heuristically generated from telemetry signals and require human review. They are not absolute proof of causation.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (causes.isEmpty)
          const Text('No explicit root-cause hypotheses returned.', style: TextStyle(color: AppColors.textMuted))
        else
          ...causes.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 20, color: AppColors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Root Cause Hypothesis',
                            style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c,
                            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildChangeCorrelationTab(InvestigationDetailModel detail) {
    final corr = detail.changeCorrelation;
    if (corr == null || corr.matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.commit, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                'No Code Changes Correlated',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'To correlate code changes with errors, provide a Git diff or code snippet when creating the investigation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final confidencePct = (corr.overallConfidence * 100).toInt();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Overall Confidence Header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.secondary.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.analytics, color: AppColors.secondary, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Change Impact Correlation Confidence',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.secondary),
                    ),
                    child: Text(
                      '$confidencePct% Confidence',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Analyzed ${corr.totalFilesAnalyzed} file(s) across ${corr.totalHunksAnalyzed} modification hunk(s).',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Scoring calculation: ${corr.confidenceCalculationMethod}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              if (corr.warning != null) ...[
                const SizedBox(height: 8),
                Text('Notice: ${corr.warning}', style: const TextStyle(color: AppColors.warning, fontSize: 12)),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Text(
          'Flagged Code Modifications & Hypotheses',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),

        ...corr.matches.map((match) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            match.filePath,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'Score: ${match.rawScore}',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Signals matched
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: match.matchedSignals.map((sig) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
                        ),
                        child: Text(
                          sig,
                          style: const TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: 'monospace'),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Hypothesis
                  Text(
                    match.hypothesis,
                    style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  // Why flagged
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.rule, size: 15, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ranking criteria: ${match.explanation}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Suggested fix
                  const Text('Suggested Remediation:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(match.suggestedFix, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  // Verification tests
                  const Text('Verification Tests:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                  const SizedBox(height: 4),
                  ...match.verificationTests.map((t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                            Expanded(child: Text(t, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                          ],
                        ),
                      )),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildRemediationTab(InvestigationDetailModel detail) {
    final actions = detail.report.recommendedActions;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Recommended Action Items',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (actions.isEmpty)
          const Text('No recommended actions available.', style: TextStyle(color: AppColors.textMuted))
        else
          ...actions.map((act) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 20, color: AppColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        act,
                        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildEvidenceTab(InvestigationDetailModel detail) {
    final evidence = detail.report.evidence;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Observed Telemetry Evidence',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (evidence.isEmpty)
          const Text('No individual evidence records recorded.', style: TextStyle(color: AppColors.textMuted))
        else
          ...evidence.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Kind: ${e["kind"] ?? "telemetry"}',
                          style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${e["timestamp"] ?? ""}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${e["content"] ?? ""}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildExportTab(InvestigationDetailModel detail) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // AI Provider transparency info
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI & Pipeline Runtime Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _buildKeyValue('Configured Provider', '${detail.aiProviderInfo["provider"] ?? "mock"}'),
              _buildKeyValue('Report Model', '${detail.aiProviderInfo["model"] ?? "qwen2.5-coder:7b (open-weight, <=8B)"}'),
              _buildKeyValue('Degraded Mode', detail.aiProviderInfo["degraded_mode"] == true ? "Active (Deterministic fallback)" : "None"),
              _buildKeyValue('Determinism', 'Change Impact Correlation ranking & confidence are 100% deterministic.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.description, size: 16),
                label: const Text('Copy Markdown Report'),
                onPressed: () => _exportReport('markdown'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.data_object, size: 16),
                label: const Text('Copy JSON Report'),
                onPressed: () => _exportReport('json'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        CodeSnippetBox(
          title: 'REPORT PREVIEW (${detail.jobId})',
          maxHeight: 200,
          content: '''# DevShield Incident Report: ${detail.title}
Service: ${detail.service} | Environment: ${detail.environment} | Severity: ${detail.severity}
Status: ${detail.reviewStatus}

## Executive Summary
${detail.incidentSummary}

## Root Cause Hypotheses
${detail.report.likelyRootCauses.map((c) => '- $c').join('\n')}

## Recommended Actions
${detail.report.recommendedActions.map((a) => '- $a').join('\n')}
''',
        ),
      ],
    );
  }

  Widget _buildKeyValue(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
