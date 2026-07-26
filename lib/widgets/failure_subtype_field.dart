import 'package:flutter/material.dart';

import '../constants/failure_subtypes.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';

/// Optional free-text failure subtype under [JobType] (breakdown family SSoT).
/// Suggestions = curated seeds for this type + past values from Firestore.
class FailureSubtypeField extends StatefulWidget {
  const FailureSubtypeField({
    super.key,
    required this.jobType,
    required this.controller,
    this.enabled = true,
  });

  final JobType jobType;
  final TextEditingController controller;
  final bool enabled;

  @override
  State<FailureSubtypeField> createState() => _FailureSubtypeFieldState();
}

class _FailureSubtypeFieldState extends State<FailureSubtypeField> {
  List<String> _options = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _options = FailureSubtypes.suggestionsFor(widget.jobType);
    widget.controller.addListener(_onTextChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant FailureSubtypeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobType != widget.jobType) {
      _options = FailureSubtypes.suggestionsFor(widget.jobType);
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final past =
          await FirestoreService().fetchFailureSubtypeHistory(widget.jobType);
      if (!mounted) return;
      setState(() {
        _options =
            FailureSubtypes.suggestionsWithHistory(widget.jobType, past);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Failure subtype (optional)',
            hintText: 'e.g. Pneumatic / air — blank is OK',
            hintStyle: const TextStyle(fontSize: 12),
            border: const OutlineInputBorder(),
            helperText:
                'Under ${widget.jobType.displayName} · pick a chip or type your own',
            helperMaxLines: 2,
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (current.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: widget.enabled
                            ? () {
                                widget.controller.clear();
                              }
                            : null,
                      )
                    : null),
          ),
        ),
        if (_options.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _options.map((s) {
              final selected = current.toLowerCase() == s.toLowerCase();
              return FilterChip(
                label: Text(s, style: const TextStyle(fontSize: 11.5)),
                selected: selected,
                onSelected: widget.enabled
                    ? (_) {
                        if (selected) {
                          widget.controller.clear();
                        } else {
                          widget.controller.text = s;
                          widget.controller.selection =
                              TextSelection.collapsed(offset: s.length);
                        }
                        setState(() {});
                      }
                    : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
