import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

(Color, String) cronResultView(BuildContext context, CronResult result) {
  final colors = context.colors;
  return switch (result) {
    CronResult.delivered => (colors.online, 'delivered'),
    CronResult.wokeAndDelivered => (colors.online, 'woke + delivered'),
    CronResult.deliverFailed => (colors.error, 'failed'),
    CronResult.skippedBusy => (colors.warn, 'skipped (busy)'),
    CronResult.skippedDown => (colors.text4, 'skipped (stopped)'),
    CronResult.skippedDisabled => (colors.text4, 'skipped (disabled)'),
    CronResult.unknown => (colors.text4, '—'),
  };
}

String fmtDateTime(DateTime dt) {
  final local = dt.toLocal();
  return '${_fmt2(local.day)}/${_fmt2(local.month)} '
      '${_fmt2(local.hour)}:${_fmt2(local.minute)}';
}

String fmtIso(String? iso) {
  if (iso == null) return '—';
  final dt = DateTime.tryParse(iso);
  return dt == null ? iso : fmtDateTime(dt);
}

String fmtTs(int ms) => fmtDateTime(DateTime.fromMillisecondsSinceEpoch(ms));

String _fmt2(int n) => n.toString().padLeft(2, '0');
