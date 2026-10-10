import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About & Technical Transparency'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // DevShield Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.shield, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppConstants.appName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(AppConstants.appTagline, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'DevShield AI is an incident response and root-cause analysis assistant designed for site reliability engineers and backend developers. '
                    'It transforms raw production logs and Git diffs into structured, evidence-backed remediation hypotheses.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Deterministic vs AI Breakdown
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Deterministic vs. AI Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(
                    'Log Ingestion & Normalization',
                    'Deterministic parser supporting JSONL, CSV, and Syslog with secret scrubbing.',
                    isDeterministic: true,
                  ),
                  _buildFeatureBullet(
                    'Anomaly Detection Engine',
                    'Statistical Z-score and median absolute deviation algorithms over latency & error metrics.',
                    isDeterministic: true,
                  ),
                  _buildFeatureBullet(
                    'Change Impact Correlation',
                    'Deterministic AST token extraction, regex signal matching, and transparent saturating score function.',
                    isDeterministic: true,
                  ),
                  _buildFeatureBullet(
                    'Report Synthesis',
                    'Synthesizes plain-language executive reports using the configured open-weight model.',
                    isDeterministic: false,
                  ),
                  _buildFeatureBullet(
                    'Remediation Insights',
                    'Grounds suggested tests in verified configuration parameters and error signatures.',
                    isDeterministic: false,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Open-Weight Model Specification
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Open-Weight Model Details (Hackathon Rule)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 10),
                  Text(
                    '• Target Model: Qwen2.5-Coder-7B-Instruct (or Llama-3.1-8B-Instruct)\n'
                    '• Parameter Count: 7.6 Billion parameters (Compliant with <= 8B parameter rule)\n'
                    '• Model License: Apache 2.0 (Permissive open source)\n'
                    '• Inference Runtime: Local Ollama / vLLM / OpenAI-compatible endpoint\n'
                    '• Degraded Fallback: Automatic graceful fallback to deterministic evidence ranking when model runtime is offline.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Safety Principles
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Safe Operation Principles', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 10),
                  Text(
                    '1. DevShield AI is an investigation assistant, not an autonomous production deployment tool.\n'
                    '2. It never automatically modifies source code, deploys fixes, restarts production services, or executes shell commands.\n'
                    '3. All findings distinguish between observed facts and hypotheses.\n'
                    '4. API keys and passwords in diffs or logs are redacted before processing.\n'
                    '5. Secrets are never embedded in frontend source code.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Open Source Attribution & License
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attribution & Open Source License', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 10),
                  Text(
                    'Original Repository:\n'
                    'ai-incident-analysis-agent by Diogo Ribeiro\n'
                    'https://github.com/DiogoRibeiro7/ai-incident-analysis-agent\n'
                    'Licensed under MIT License (Copyright (c) 2026 Diogo Ribeiro).\n\n'
                    'DevShield AI Contributions:\n'
                    '• Original Change Impact Correlation engine (matching Git diffs to incident signals)\n'
                    '• Transparent rule-based evidence scoring & confidence calculation\n'
                    '• Open-weight model provider adapter (<8B params)\n'
                    '• Modern Flutter + Riverpod developer-tool frontend\n'
                    '• Multi-format log ingestion & verification suite',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBullet(String title, String desc, {required bool isDeterministic}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDeterministic ? AppColors.primary.withOpacity(0.12) : AppColors.secondary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: (isDeterministic ? AppColors.primary : AppColors.secondary).withOpacity(0.3)),
            ),
            child: Text(
              isDeterministic ? 'DETERMINISTIC' : 'AI-AUGMENTED',
              style: TextStyle(
                color: isDeterministic ? AppColors.primary : AppColors.secondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

