import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class CodeSnippetBox extends StatelessWidget {
  final String content;
  final String? title;
  final double maxHeight;
  final bool isDiff;

  const CodeSnippetBox({
    super.key,
    required this.content,
    this.title,
    this.maxHeight = 220,
    this.isDiff = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF090D1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0E1526),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.code, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        title!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied snippet to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Row(
                      children: [
                        Icon(Icons.copy, size: 13, color: AppColors.textMuted),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: isDiff ? _buildDiffView(content) : _buildPlainCode(content),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlainCode(String text) {
    return SelectableText(
      text,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: AppColors.textPrimary,
        height: 1.45,
      ),
    );
  }

  Widget _buildDiffView(String diff) {
    final lines = diff.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: lines.map((line) {
        Color fg = AppColors.textSecondary;
        Color? bg;

        if (line.startsWith('+') && !line.startsWith('+++')) {
          fg = const Color(0xFF34D399); // Green for addition
          bg = const Color(0x1510B981);
        } else if (line.startsWith('-') && !line.startsWith('---')) {
          fg = const Color(0xFFF87171); // Red for removal
          bg = const Color(0x18EF4444);
        } else if (line.startsWith('@@')) {
          fg = AppColors.primary; // Cyan for hunk header
          bg = const Color(0x1038BDF8);
        }

        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: fg,
              height: 1.4,
            ),
          ),
        );
      }).toList(),
    );
  }
}

