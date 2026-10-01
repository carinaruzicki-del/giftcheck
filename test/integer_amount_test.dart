import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftcheck/integer_amount.dart';

void main() {
  final formatter = IntegerAmountFormatter();
  TextEditingValue edit(String old, int caret, String next, int newCaret) =>
      formatter.formatEditUpdate(
        TextEditingValue(
          text: old,
          selection: TextSelection.collapsed(offset: caret),
        ),
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: newCaret),
        ),
      );
  test('typing and pasted text format integer pesos', () {
    for (final pair in {
      '100': '100',
      '1000': '1.000',
      '10000': '10.000',
      '100000': '100.000',
      '1000000': '1.000.000',
      '100.000': '100.000',
      'abc 1\$00,50': '10.050',
    }.entries) {
      final result = edit('', 0, pair.key, pair.key.length);
      expect(result.text, pair.value);
      expect(
        cleanIntegerAmount(result.text),
        int.parse(amountDigits(pair.key)),
      );
    }
  });
  test('insertion and deletion in middle preserve digit-relative cursor', () {
    final inserted = edit('12.345', 1, '192.345', 2);
    expect(inserted.text, '192.345');
    expect(inserted.selection.extentOffset, 2);
    final removed = edit('12.345', 2, '1.345', 1);
    expect(removed.text, '1.345');
    expect(removed.selection.extentOffset, 1);
  });
  test('backspace and forward delete across grouping separator', () {
    final backspace = edit('12.345', 3, '12345', 2);
    expect(backspace.text, '1.345');
    expect(backspace.selection.extentOffset, 1);
    final delete = edit('12.345', 2, '12345', 2);
    expect(delete.text, '1.245');
    expect(delete.selection.extentOffset, 3);
  });
  test('selection, empty input and representable integer limit', () {
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '123456',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      ),
    );
    expect(result.text, '123.456');
    expect(
      result.selection,
      const TextSelection(baseOffset: 1, extentOffset: 5),
    );
    expect(edit('1', 1, '', 0).text, '');
    expect(
      edit('999.999.999.999', 15, '999.999.999.9999', 16).text,
      '999.999.999.999',
    );
  });
}
