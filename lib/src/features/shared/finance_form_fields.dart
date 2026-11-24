import 'package:flutter/material.dart';

import 'finance_amount_field.dart';

class FinanceTextField extends StatelessWidget {
  const FinanceTextField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType,
    this.isAmount = false,
    this.validator,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool isAmount;
  final String? Function(String?)? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    if (isAmount) {
      return FinanceAmountField(
        controller: controller,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );
    }
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
