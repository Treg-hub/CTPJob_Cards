import 'package:flutter/material.dart';

/// Free-text field with suggestions from previous gate log entries.
class SecuritySuggestionField extends StatelessWidget {
  const SecuritySuggestionField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
    this.required = false,
    this.maxLines = 1,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final bool required;
  final int maxLines;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return suggestions;
        return suggestions
            .where((s) => s.toLowerCase().contains(query))
            .toList();
      },
      onSelected: (value) => controller.text = value,
      fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
        if (fieldController.text != controller.text) {
          fieldController.text = controller.text;
        }
        fieldController.addListener(() {
          if (controller.text != fieldController.text) {
            controller.text = fieldController.text;
          }
        });
        return TextField(
          controller: fieldController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            border: const OutlineInputBorder(),
            helperText: helperText ?? 'Type freely or pick a previous entry',
          ),
          maxLines: maxLines,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        if (options.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}