/// Keep integer amounts exactly representable in Flutter Web/Firestore rules.
const maxVoucherAmount = 999999999999;

String? validateVoucherAmount(String? value) {
  if (value == null || value.isEmpty) return 'Ingresá el importe';
  if (!RegExp(r'^[0-9]+$').hasMatch(value)) return 'Ingresá solo números';
  final amount = int.tryParse(value);
  if (amount == null || amount > maxVoucherAmount) {
    return 'El importe es demasiado grande';
  }
  if (amount <= 0) return 'El importe debe ser mayor que cero';
  return null;
}

String? validateVoucherExpiration(DateTime? value, {DateTime? now}) {
  if (value == null) return 'Elegí la fecha de vencimiento';
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(value.year, value.month, value.day);
  if (day.isBefore(today)) return 'El vencimiento debe ser hoy o posterior';
  // Firestore timestamps support years through 9999, rather than literal infinity.
  if (value.year > 9999) return 'El año máximo permitido es 9999';
  return null;
}

DateTime voucherEndOfDay(DateTime date) {
  final end = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  final maxTimestamp = DateTime.utc(9999, 12, 31, 23, 59, 59, 999);
  return end.isAfter(maxTimestamp) ? maxTimestamp.toLocal() : end;
}

const maxVoucherSequence = 26 * 999999;

bool isVoucherCode(String code) =>
    RegExp(r'^V[A-Z][0-9]{6}$').hasMatch(code) || code.startsWith('V-');

String voucherCodeFromSequence(int sequence) {
  if (sequence < 1 || sequence > maxVoucherSequence) {
    throw StateError('Se agotó la numeración de vouchers disponible.');
  }
  final letter = String.fromCharCode(65 + (sequence - 1) ~/ 999999);
  final number = ((sequence - 1) % 999999 + 1).toString().padLeft(6, '0');
  return 'V$letter$number';
}
