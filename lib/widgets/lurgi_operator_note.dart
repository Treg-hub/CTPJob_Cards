import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Dismissible operator tip. Key is stored in prefs so "Don't show again" sticks.
///
/// Remove a note from the product by deleting the widget call site (and the
/// corresponding [noteId] is unused). Prefs keys: `lurgi.note.dismissed.{id}`.
class LurgiOperatorNote extends StatefulWidget {
  const LurgiOperatorNote({
    super.key,
    required this.noteId,
    required this.message,
    this.title = 'Operator tip',
  });

  /// Stable id for dismiss prefs (e.g. `hub_walk_order`).
  final String noteId;
  final String message;
  final String title;

  @override
  State<LurgiOperatorNote> createState() => _LurgiOperatorNoteState();
}

class _LurgiOperatorNoteState extends State<LurgiOperatorNote> {
  bool? _visible; // null = loading

  String get _prefsKey => 'lurgi.note.dismissed.${widget.noteId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _visible = !(prefs.getBool(_prefsKey) ?? false));
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    if (!mounted) return;
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_visible != true) return const SizedBox.shrink();
    final appColors = Theme.of(context).appColors;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: appColors.lurgiSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: appColors.lurgiDark.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 18, color: appColors.lurgiDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: appColors.lurgiDark,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: "Don't show again",
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _dismiss,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Text(
                widget.message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _dismiss,
                child: const Text("Don't show again"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
