import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/severity_badge.dart';
import '../../../core/widgets/status_pill.dart';
import '../../investigation/application/investigation_notifier.dart';
import '../../investigation/domain/investigation_models.dart';
import '../../investigation/presentation/investigation_detail_screen.dart';
import '../../investigation/presentation/new_investigation_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  String _selectedSeverity = 'ALL';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final investigationsAsync = ref.watch(investigationsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Investigation History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh History',
            onPressed: () => ref.invalidate(investigationsListProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search investigations by title, service, ID...',
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Severity:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(width: 8),
                      ...['ALL', 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'].map((sev) {
                        final isSelected = _selectedSeverity == sev;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Text(sev, style: TextStyle(fontSize: 11, color: isSelected ? Colors.black : AppColors.textPrimary)),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.surfaceLight,
                            side: const BorderSide(color: AppColors.border),
                            onSelected: (val) {
                              if (val) setState(() => _selectedSeverity = sev);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // List content
          Expanded(
            child: investigationsAsync.when(
              data: (list) {
                var filtered = list;
                final query = _searchController.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  filtered = filtered.where((item) {
                    return item.title.toLowerCase().contains(query) ||
                        item.service.toLowerCase().contains(query) ||
                        item.jobId.toLowerCase().contains(query) ||
                        item.summary.toLowerCase().contains(query);
                  }).toList();
                }

                if (_selectedSeverity != 'ALL') {
                  filtered = filtered.where((item) => item.severity.toUpperCase() == _selectedSeverity).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off, size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          const Text('No Matching Investigations Found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('Try adjusting your search query or severity filter.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Start New Investigation'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NewInvestigationScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final item = filtered[idx];
                    return _buildHistoryTile(context, item);
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Text('Error loading history: $e', style: const TextStyle(color: AppColors.critical)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, InvestigationSummaryModel item) {
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
          child: Text(
            'Service: ${item.service} • ${item.createdAt.split("T").first} • ${item.jobId}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
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
}

