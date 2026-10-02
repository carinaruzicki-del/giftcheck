import 'package:giftcheck/feature_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftcheck/main.dart';

Widget host(Widget child) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  supportedLocales: const [Locale('es')],
  home: child,
);

void main() {
  if (!vouchersEnabled) return;
  testWidgets('Voucher requires amount and expiration; numbers only', (
    tester,
  ) async {
    await tester.pumpWidget(host(const CreateVoucherPage()));
    await tester.tap(find.widgetWithText(FilledButton, 'Crear voucher'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresá el importe'), findsOneWidget);
    expect(find.text('Elegí la fecha de vencimiento'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('voucher-amount')), 'abc12x34');
    expect(find.text('1.234'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('voucher-amount')), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear voucher'));
    await tester.pumpAndSettle();
    expect(find.text('El importe debe ser mayor que cero'), findsOneWidget);
  });

  testWidgets('Calendar allows today and future years beyond 2100', (
    tester,
  ) async {
    await tester.pumpWidget(host(const CreateVoucherPage()));
    await tester.tap(find.byKey(const Key('voucher-expiration')));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    final now = DateTime.now();
    expect(picker.firstDate, DateTime(now.year, now.month, now.day));
    expect(picker.lastDate.year, 9999);
    await tester.tap(find.text('Elegir fecha'));
    await tester.pumpAndSettle();
    expect(find.text(formatDate(now)), findsOneWidget);
  });
  testWidgets(
    'Month selector changes calendar and year selector allows distant years',
    (tester) async {
      await tester.pumpWidget(
        host(ExpirationCalendarDialog(initialDate: DateTime(2200, 1, 15))),
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marzo').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2200, 3, 15),
      );
      await tester.tap(find.text('2200 ▾'));
      await tester.pumpAndSettle();
      expect(find.byType(YearPicker), findsOneWidget);
      await tester.tap(find.text('2201'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2201, 3, 15),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
