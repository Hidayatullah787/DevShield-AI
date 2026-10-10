import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../application/investigation_notifier.dart';
import 'investigation_detail_screen.dart';

class NewInvestigationScreen extends ConsumerStatefulWidget {
  const NewInvestigationScreen({super.key});

  @override
  ConsumerState<NewInvestigationScreen> createState() => _NewInvestigationScreenState();
}

class _NewInvestigationScreenState extends ConsumerState<NewInvestigationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController(text: 'Checkout Service Connection Timeout');
  final _serviceController = TextEditingController(text: 'checkout');
  final _envController = TextEditingController(text: 'production');
  final _logsController = TextEditingController(text: AppConstants.sampleCheckoutLogs);
  final _diffController = TextEditingController(text: AppConstants.sampleCheckoutDiff);

  bool _isValidating = false;
  Map<String, dynamic>? _validationResult;

  @override
  void dispose() {
    _titleController.dispose();
    _serviceController.dispose();
    _envController.dispose();
    _logsController.dispose();
    _diffController.dispose();
    super.dispose();
  }

  void _loadScenario(String scenario) {
    if (scenario == 'checkout') {
      _titleController.text = 'Checkout Service Connection Timeout';
      _serviceController.text = 'checkout';
      _logsController.text = AppConstants.sampleCheckoutLogs;
      _diffController.text = AppConstants.sampleCheckoutDiff;
    } else if (scenario == 'auth') {
      _titleController.text = 'Auth Service High Token Expiration Rate';
      _serviceController.text = 'auth';
      _logsController.text = AppConstants.sampleAuthLogs;
      _diffController.text = AppConstants.sampleAuthDiff;
    }
    setState(() {
      _validationResult = null;
    });
  }

  Future<void> _validateInput() async {
    setState(() {
      _isValidating = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.validateInput(
        rawLogs: _logsController.text,
        rawDiff: _diffController.text,
        service: _serviceController.text,
        environment: _envController.text,
      );
      setState(() {
        _validationResult = res;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Validation error: $e')),
      );
    } finally {
      setState(() {
        _isValidating = false;
      });
    }
  }

  Future<void> _submitInvestigation() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(newInvestigationProvider.notifier);
    final result = await notifier.startInvestigation(
      title: _titleController.text.trim(),
      service: _serviceController.text.trim(),
      environment: _envController.text.trim(),
      rawLogs: _logsController.text.trim(),
      rawDiff: _diffController.text.trim(),
    );

    if (result != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => InvestigationDetailScreen(jobId: result.jobId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newInvestigationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Incident Investigation'),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preload scenario helper
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_fix_high, size: 18, color: AppColors.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Quickstart sample scenarios:',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            ActionChip(
                              label: const Text('Checkout DB Pool (Timeout)', style: TextStyle(fontSize: 12)),
                              backgroundColor: AppColors.surfaceLight,
                              side: const BorderSide(color: AppColors.border),
                              onPressed: () => _loadScenario('checkout'),
                            ),
                            ActionChip(
                              label: const Text('Auth Token Spike (401)', style: TextStyle(fontSize: 12)),
                              backgroundColor: AppColors.surfaceLight,
                              side: const BorderSide(color: AppColors.border),
                              onPressed: () => _loadScenario('auth'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Metadata section
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
                        const Text('1. Incident Metadata', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Investigation Title',
                            hintText: 'e.g. Database connection timeout in checkout replica',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _serviceController,
                                decoration: const InputDecoration(
                                  labelText: 'Service Name',
                                  hintText: 'e.g. checkout, api-gateway',
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter service' : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextFormField(
                                controller: _envController,
                                decoration: const InputDecoration(
                                  labelText: 'Environment',
                                  hintText: 'production, staging',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Telemetry Logs section
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('2. Application Error Logs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Required', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Paste JSON lines, CSV, or formatted syslog text containing error events.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _logsController,
                          maxLines: 7,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: 'Paste log events here...',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please provide application error logs' : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Code Diff section
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('3. Git Diff / Code Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Optional', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'DevShield Change Impact Correlation matches modified variables, timeouts, and service components against the incident evidence to produce remediation hypotheses.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _diffController,
                          maxLines: 7,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: 'Paste git diff or modified code patch here...',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Validation preview box if tested
                  if (_validationResult != null) _buildValidationBanner(_validationResult!),

                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.criticalBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.critical.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.critical, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Error: ${state.errorMessage}',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Submit Actions
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: _isValidating
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Validate Telemetry Input'),
                        onPressed: _isValidating || state.isSubmitting ? null : _validateInput,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Start Investigation'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: state.isSubmitting ? null : _submitInvestigation,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // Progress Overlay during active pipeline execution
          if (state.isSubmitting) _buildProgressOverlay(state.currentStage ?? 'Running incident analysis...'),
        ],
      ),
    );
  }

  Widget _buildValidationBanner(Map<String, dynamic> v) {
    final isValid = v['valid'] == true;
    final eventCount = v['log_event_count'] ?? 0;
    final diffFiles = v['diff_file_count'] ?? 0;
    final services = (v['detected_services'] as List?)?.cast<String>() ?? [];
    final warnings = (v['warnings'] as List?)?.cast<String>() ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isValid ? AppColors.successBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isValid ? AppColors.success.withOpacity(0.4) : AppColors.warning.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isValid ? Icons.verified : Icons.warning, size: 18, color: isValid ? AppColors.success : AppColors.warning),
              const SizedBox(width: 8),
              Text(
                isValid ? 'Validation Succeeded' : 'Validation Notice',
                style: TextStyle(
                  color: isValid ? AppColors.success : AppColors.warning,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Parsed $eventCount log records. Identified services: ${services.isEmpty ? "default" : services.join(", ")}. '
            'Git diff files extracted: $diffFiles.',
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...warnings.map((w) => Text('• $w', style: const TextStyle(fontSize: 11, color: AppColors.warning))),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressOverlay(String stage) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Analyzing Incident Evidence',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                stage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.primary),
              ),
              const SizedBox(height: 14),
              const Text(
                'Running telemetry normalization, anomaly isolation, and git diff signal correlation.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

