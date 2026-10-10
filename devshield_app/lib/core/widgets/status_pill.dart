import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StatusPill extends StatelessWidget {
  final String status;
  final bool isReviewed;

  const StatusPill({
    super.key,
    required this.status,
    this.isReviewed = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg;
    Color fg;
    Color dot;

    if (s == 'approved' || s == 'completed' || s == 'ok' || s == 'ready') {
      bg = AppColors.successBg;
      fg = AppColors.success;
      dot = AppColors.success;
    } else if (s == 'reviewed') {
      bg = AppColors.infoBg;
      fg = AppColors.info;
      dot = AppColors.info;
    } else if (s == 'rejected' || s == 'failed' || s == 'error') {
      bg = AppColors.criticalBg;
      fg = AppColors.critical;
      dot = AppColors.critical;
    } else {
      bg = AppColors.surfaceLight;
      fg = AppColors.textSecondary;
      dot = AppColors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

