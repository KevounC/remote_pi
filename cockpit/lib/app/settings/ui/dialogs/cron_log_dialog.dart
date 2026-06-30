import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/settings/ui/cron_viewmodel.dart';
import 'package:cockpit/app/settings/ui/dialogs/cron_formatting.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Future<void> showCronLogDialog(
  BuildContext context, {
  required CronViewModel viewModel,
  required CronJob job,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => CronLogDialog(viewModel: viewModel, job: job),
  );
}

/// Dialog displaying the `cron.jsonl` history for one schedule.
class CronLogDialog extends StatefulWidget {
  const CronLogDialog({required this.viewModel, required this.job, super.key});

  final CronViewModel viewModel;
  final CronJob job;

  @override
  State<CronLogDialog> createState() => _CronLogDialogState();
}

class _CronLogDialogState extends State<CronLogDialog> {
  List<CronLogEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.viewModel.fetchLog(jobId: widget.job.id);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _error = entries == null
          ? (widget.viewModel.actionError ?? 'Failed to read the log.')
          : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: Text(
        'History — ${widget.job.schedule}',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(width: 460, child: _content(context)),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final colors = context.colors;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            size: 22,
            strokeWidth: 2,
            color: colors.text3,
          ),
        ),
      );
    }
    if (_error != null) {
      return Text(
        _error!,
        style: context.typo.body.copyWith(fontSize: 13.5, color: colors.error),
      );
    }
    final entries = _entries ?? const <CronLogEntry>[];
    if (entries.isEmpty) {
      return Text(
        'No records yet.',
        style: context.typo.body.copyWith(fontSize: 13.5, color: colors.text3),
      );
    }
    // Most recent first.
    final ordered = entries.reversed.toList(growable: false);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: ordered.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
        itemBuilder: (context, i) {
          final entry = ordered[i];
          final (color, label) = cronResultView(context, entry.result);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: context.typo.body.copyWith(
                              fontSize: 12.5,
                              color: color,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            fmtTs(entry.tsMs),
                            style: context.typo.mono.copyWith(
                              fontSize: 11,
                              color: colors.text3,
                            ),
                          ),
                        ],
                      ),
                      if (entry.promptPreview.isNotEmpty)
                        Text(
                          entry.promptPreview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.label.copyWith(
                            color: colors.text3,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
