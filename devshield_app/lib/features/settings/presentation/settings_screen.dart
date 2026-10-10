import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../investigation/application/investigation_notifier.dart';
import 'about_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  String? _testMessage;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ref.read(apiBaseUrlProvider));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testMessage = null;
    });

    final targetUrl = _urlController.text.trim();
    // Update global base URL
    ref.read(apiBaseUrlProvider.notifier).state = targetUrl;

    try {
      final client = ref.read(apiClientProvider);
      final info = await client.fetchApiInfo();
      setState(() {
        _testSuccess = true;
        _testMessage = 'Connected successfully! Service: ${info["app_name"]} v${info["version"]}';
      });
      ref.invalidate(apiInfoProvider);
      ref.invalidate(investigationsListProvider);
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testMessage = 'Connection failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiInfoAsync = ref.watch(apiInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Architecture'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backend URL configuration
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
                  const Text('Backend Service Address', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                    'Specify the FastAPI server base URL for DevShield AI:',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'http://127.0.0.1:8000',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isTesting ? null : _testConnection,
                        child: _isTesting
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Text('Test & Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 8,
                    children: [
                      Text('Common targets:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      Text('• Desktop: http://127.0.0.1:8000', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                      Text('• Android Emulator: http://10.0.2.2:8000', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace')),
                    ],
                  ),
                  if (_testMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _testSuccess ? AppColors.successBg : AppColors.criticalBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: (_testSuccess ? AppColors.success : AppColors.critical).withOpacity(0.4)),
                      ),
                      child: Text(
                        _testMessage!,
                        style: TextStyle(fontSize: 12, color: _testSuccess ? AppColors.success : AppColors.critical),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // AI Provider & Model Runtime Info
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
                  const Text('AI Model & Hackathon Compliance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  apiInfoAsync.when(
                    data: (info) {
                      final ai = info['ai_provider'] as Map<String, dynamic>? ?? {};
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRow('Configured Provider', '${ai["provider_name"] ?? "mock"}'),
                          _buildRow('Report Model', '${ai["report_model"] ?? "gpt-4.1-mini"}'),
                          _buildRow('Target Open-Weight Model', '${ai["open_weight_model"] ?? "qwen2.5-coder:7b"}'),
                          _buildRow('Parameter Count', '${ai["parameter_count"] ?? "<= 8B parameters"}'),
                          _buildRow('Model License', '${ai["model_license"] ?? "Apache 2.0"}'),
                          _buildRow('Inference Engine', '${ai["runtime"] ?? "Local Ollama / OpenAI-compatible"}'),
                          _buildRow('Degraded Mode', ai["degraded_mode"] == true ? "Active" : "Normal"),
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    error: (e, _) => Text('Could not load AI details: $e', style: const TextStyle(color: AppColors.textMuted)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Navigation to Technical Transparency & About
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: ListTile(
                leading: const Icon(Icons.info_outline, color: AppColors.primary),
                title: const Text('Technical Transparency & About', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Deterministic vs AI breakdown, limitations, license & attribution', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
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
