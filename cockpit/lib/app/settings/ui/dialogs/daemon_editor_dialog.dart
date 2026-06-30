import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Result from the daemon editor dialog: daemon folder plus display name.
final class DaemonEditorResult {
  const DaemonEditorResult({required this.cwd, required this.name});

  final String cwd;
  final String name;
}

Future<DaemonEditorResult?> showDaemonEditorDialog(
  BuildContext context, {
  DaemonInfo? editing,
  required List<DaemonInfo> daemons,
}) {
  final others = daemons.where((daemon) => daemon.id != editing?.id);
  return showDialog<DaemonEditorResult>(
    context: context,
    builder: (_) => DaemonEditorDialog(
      editing: editing,
      existingNames: others
          .map((daemon) => daemon.name.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet(),
      existingCwds: others.map((daemon) => daemon.cwd).toSet(),
    ),
  );
}

/// Dialog for creating/editing a daemon.
///
/// Creation picks a folder and name. Editing locks the folder and changes only
/// the name. The dialog validates unique name and, on creation, unique folder
/// against the daemons supplied by the panel. The supervisor/CLI remains the
/// final normalization and duplicate-path backstop.
class DaemonEditorDialog extends StatefulWidget {
  const DaemonEditorDialog({
    required this.editing,
    required this.existingNames,
    required this.existingCwds,
    super.key,
  });

  final DaemonInfo? editing;
  final Set<String> existingNames;
  final Set<String> existingCwds;

  @override
  State<DaemonEditorDialog> createState() => _DaemonEditorDialogState();
}

class _DaemonEditorDialogState extends State<DaemonEditorDialog> {
  late final TextEditingController _nameCtrl;
  String? _cwd;
  String? _nameError;
  String? _pathError;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.editing?.name ?? '');
    _cwd = widget.editing?.cwd;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the Daemon Agent folder',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _cwd = picked;
      _pathError = null;
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    String? nameError;
    String? pathError;

    if (name.isEmpty) {
      nameError = 'Enter a name.';
    } else if (widget.existingNames.contains(name.toLowerCase())) {
      nameError = 'An agent with this name already exists.';
    }
    if (!_isEdit) {
      if (_cwd == null) {
        pathError = 'Choose a folder.';
      } else if (widget.existingCwds.contains(_cwd)) {
        pathError = 'An agent already exists in this folder.';
      }
    }

    if (nameError != null || pathError != null) {
      setState(() {
        _nameError = nameError;
        _pathError = pathError;
      });
      return;
    }
    Navigator.of(context).pop(
      DaemonEditorResult(
        cwd: _isEdit ? widget.editing!.cwd : _cwd!,
        name: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      title: Text(
        _isEdit ? 'Edit daemon' : 'New daemon',
        style: context.typo.title.copyWith(fontSize: 15, color: colors.text),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(context, 'Name'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => _submit(),
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text,
              ),
              placeholder: const Text('e.g. PC, Server, Home'),
              borderRadius: BorderRadius.circular(7),
            ),
            if (_nameError != null) ...[
              const SizedBox(height: 6),
              Text(
                _nameError!,
                style: context.typo.label.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: 16),
            _label(context, 'Folder'),
            const SizedBox(height: 6),
            if (_isEdit)
              SizedBox(
                width: double.infinity,
                child: _pathBox(context, _cwd ?? '', enabled: false),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _pathBox(
                      context,
                      _cwd ?? 'No folder chosen',
                      enabled: _cwd != null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlineButton(
                    onPressed: () => _pickFolder(),
                    child: Text(_cwd == null ? 'Choose' : 'Change'),
                  ),
                ],
              ),
            if (_isEdit) ...[
              const SizedBox(height: 6),
              Text(
                'The folder cannot be changed.',
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ],
            if (_pathError != null) ...[
              const SizedBox(height: 6),
              Text(
                _pathError!,
                style: context.typo.label.copyWith(color: colors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.text2,
            ),
          ),
        ),
        GhostButton(
          onPressed: _submit,
          child: Text(
            _isEdit ? 'Save' : 'Create',
            style: context.typo.body.copyWith(
              fontSize: 13,
              color: colors.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: context.typo.label.copyWith(color: context.colors.text3),
  );

  Widget _pathBox(BuildContext context, String text, {required bool enabled}) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.typo.mono.copyWith(
          fontSize: 11.5,
          color: enabled ? colors.text2 : colors.text3,
        ),
      ),
    );
  }
}
