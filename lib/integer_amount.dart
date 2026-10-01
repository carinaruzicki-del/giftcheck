import 'package:flutter/services.dart';

String amountDigits(String text) => text.replaceAll(RegExp(r'[^0-9]'), '');
int cleanIntegerAmount(String text) => int.tryParse(amountDigits(text)) ?? 0;

/// Formats display text while anchoring both selection ends to digit positions.
class IntegerAmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    var selection = newValue.selection;
    // Backspace/delete on a grouping separator removes the adjacent digit too.
    if (oldValue.selection.isCollapsed &&
        selection.isCollapsed &&
        oldValue.text.length == text.length + 1) {
      final offset = selection.extentOffset;
      if (offset >= 0 &&
          offset < oldValue.text.length &&
          oldValue.text[offset] == '.') {
        final backwards = oldValue.selection.extentOffset > offset;
        final remove = backwards ? offset - 1 : offset;
        if (remove >= 0 && remove < text.length) {
          text = text.replaceRange(remove, remove + 1, '');
          selection = TextSelection.collapsed(
            offset: backwards ? remove : offset,
          );
        }
      }
    }
    final digits = amountDigits(text);
    // Keep integers exactly representable on web; match the service amount limit.
    if (digits.length > 12) return oldValue;
    final formatted = digits.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
    int mapOffset(int offset) {
      if (offset < 0) return formatted.length;
      final count = amountDigits(
        text.substring(0, offset.clamp(0, text.length)),
      ).length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != '.') seen++;
        if (seen == count) return i + 1;
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: mapOffset(selection.baseOffset),
        extentOffset: mapOffset(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
    );
  }
}
