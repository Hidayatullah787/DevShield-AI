import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/severity_badge.dart';
import '../../../core/widgets/status_pill.dart';
import '../../investigation/application/investigation_notifier.dart';
import '../../investigation/domain/investigation_models.dart';
import '../../investigation/presentation/investigation_detail_screen.dart';
import '../../investigation/presentation/new_investigation_screen.dart';

class DashboardScreen extends ConsumerWidget {
  final Function(int)? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiInfoAsync = ref.watch(apiInfoProvider);
    final investigationsAsync = ref.watch(investigationsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: const Icon(Icons.security, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DevShield AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(
                    'From production error to evidence-backed fix',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.normal),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _buildConnectionPill(apiInfoAsync, ref),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Telemetry',
            onPressed: () {
              ref.invalidate(apiInfoProvider);
              ref.invalidate(investigationsListProvider);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(apiInfoProvider);
          ref.invalidate(investigationsListProvider);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero banner with action button
              _buildHeroHeader(context, ref),
              const SizedBox(height: 24),

              // Summary metric cards
              investigationsAsync.when(
                data: (list) => _buildMetricCards(list),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (e, _) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.criticalBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.critical.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.critical),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Backend offline: Unable to load incidents from ${ref.watch(apiBaseUrlProvider)} ($e)',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Recent investigations list header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Recent Incident Investigations',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onNavigate != null)
                    TextButton(
                      onPressed: () => onNavigate!(1), // Go to History tab
                      child: const Text('View All History →'),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Recent investigations content
              investigationsAsync.when(
                data: (list) {
                  if (list.isEmpty) {
                    return _buildEmptyState(context, ref);
                  }
                  return Column(
                    children: list.take(6).map((item) => _buildIncidentTile(context, item)).toList(),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionPill(AsyncValue<Map<String, dynamic>> apiInfo, WidgetRef ref) {
    return apiInfo.when(
      data: (info) {
        final aiInfo = info['ai_provider'] as Map<String, dynamic>? ?? {};
        final model = aiInfo['open_weight_model'] ?? aiInfo['report_model'] ?? 'Mock';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.success.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                'Connected • $model',
                style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.criticalBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.critical.withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 12, color: AppColors.critical),
            SizedBox(width: 6),
            Text(
              'Backend Offline',
              style: TextStyle(color: AppColors.critical, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        gradient: LinearGradient(
          colors: [
            AppColors.surface,
            AppColors.surfaceLight.withOpacity(0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Incident Root-Cause & Code-Diff Correlation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'DevShield isolates telemetry anomalies, matches error signatures against recent Git commits, and generates evidence-grounded hypotheses with verified fixes.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('New Investigation'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NewInvestigationScreen()),
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.bolt, size: 17, color: AppColors.primary),
                      label: const Text('Seed Demo Scenario'),
                      onPressed: () async {
                        try {
                          final client = ref.read(apiClientProvider);
                          await client.seedSamples();
                          ref.invalidate(investigationsListProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Loaded sample incident (Checkout DB timeout) into investigation store!')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to seed: $e')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCards(List<InvestigationSummaryModel> list) {
    final total = list.length;
    final critical = list.where((i) => i.severity.toUpperCase() == 'CRITICAL').length;
    final high = list.where((i) => i.severity.toUpperCase() == 'HIGH').length;
    final reviewed = list.where((i) => i.reviewStatus != 'draft').length;
    final correlated = list.where((i) => i.hasChangeCorrelation).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final c1 = _buildStatCard('Total Analyzed', total.toString(), Icons.analytics_outlined, AppColors.primary);
        final c2 = _buildStatCard('Critical / High', (critical + high).toString(), Icons.warning_amber_rounded, AppColors.critical);
        final c3 = _buildStatCard('Diff Correlated', correlated.toString(), Icons.compare_arrows, AppColors.secondary);
        final c4 = _buildStatCard('Reviewed', reviewed.toString(), Icons.check_circle_outline, AppColors.success);

        if (isNarrow) {
          return Column(
            children: [
              Row(children: [c1, const SizedBox(width: 10), c2]),
              const SizedBox(height: 10),
              Row(children: [c3, const SizedBox(width: 10), c4]),
            ],
          );
        }

        return Row(
          children: [
            c1,
            const SizedBox(width: 12),
            c2,
            const SizedBox(width: 12),
            c3,
            const SizedBox(width: 12),
            c4,
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentTile(BuildContext context, InvestigationSummaryModel item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: SeverityBadge(severity: item.severity),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.hasChangeCorrelation) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.commit, size: 11, color: AppColors.secondary),
                    SizedBox(width: 4),
                    Text(
                      'Diff Matched',
                      style: TextStyle(fontSize: 10, color: AppColors.secondary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                'Service: ${item.service}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(width: 10),
              Text(
                '• Env: ${item.environment}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(width: 10),
              Text(
                '• ${item.jobId}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusPill(status: item.reviewStatus),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvestigationDetailScreen(jobId: item.jobId),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.troubleshoot, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 14),
          const Text(
            'No Investigations Yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start an investigation by providing application error logs and optional Git diffs.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Start First Investigation'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewInvestigationScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
