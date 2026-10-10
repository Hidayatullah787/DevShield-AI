import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SeverityBadge extends StatelessWidget {
  final String severity;
  final bool isCompact;

  const SeverityBadge({
    super.key,
    required this.severity,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final sev = severity.toUpperCase();
    Color bg;
    Color fg;
    Color border;

    switch (sev) {
      case 'CRITICAL':
      case 'FATAL':
        bg = AppColors.criticalBg;
        fg = AppColors.critical;
        border = AppColors.critical.withOpacity(0.4);
        break;
      case 'HIGH':
      case 'ERROR':
        bg = AppColors.criticalBg.withOpacity(0.6);
        fg = const Color(0xFFF87171);
        border = AppColors.critical.withOpacity(0.3);
        break;
      case 'MEDIUM':
      case 'WARN':
      case 'WARNING':
        bg = AppColors.warningBg;
        fg = AppColors.warning;
        border = AppColors.warning.withOpacity(0.4);
        break;
      case 'LOW':
      case 'INFO':
        bg = AppColors.infoBg;
        fg = AppColors.info;
        border = AppColors.info.withOpacity(0.3);
        break;
      default:
        bg = AppColors.surfaceLight;
        fg = AppColors.textSecondary;
        border = AppColors.border;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 10,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        sev,
        style: TextStyle(
          color: fg,
          fontSize: isCompact ? 10 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

