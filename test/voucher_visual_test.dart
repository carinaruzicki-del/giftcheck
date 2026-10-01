import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:giftcheck/main.dart';

void main() {
  testWidgets(
    'Voucher preserves the original visual and shows expiry above code',
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await tester.binding.setSurfaceSize(const Size(600, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final regular = FontLoader('Roboto');
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk != null) {
        regular.addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
              ).readAsBytesSync(),
            ),
          ),
        );
        await tester.runAsync(() => regular.load());
      }
      final key = GlobalKey();
      final card = GiftCard(
        code: 'VA000001',
        amount: '50000',
        expirationDate: DateTime(2026, 11, 30),
        dedication: '',
        status: 'Activa',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 535,
                  height: 650,
                  child: GiftCardVisual(giftCard: card),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await GoogleFonts.pendingFonts();
        await precacheImage(
          const AssetImage('assets/el-cielo-logos.png'),
          key.currentContext!,
        );
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(find.text('VOU'), findsOneWidget);
      expect(find.text('CHER'), findsNWidgets(2));
      expect(find.text('PARA:'), findsNothing);
      final date = find.text('VENCE: 30 de noviembre del 2026');
      final code = find.text('CÓDIGO VA000001');
      expect(date, findsOneWidget);
      expect(tester.getTopLeft(date).dy, lessThan(tester.getTopLeft(code).dy));
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      expect(boundary.size, const Size(535, 650));
      if (Platform.environment['SAVE_VOUCHER_PREVIEW'] == '1') {
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '../voucher-vista-previa.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.binding.setSurfaceSize(const Size(320, 700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Existing Gift Card keeps its original fields and title', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.binding.setSurfaceSize(const Size(600, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const card = GiftCard(
      code: 'A000123',
      amount: '50000',
      expirationDate: null,
      dedication: '',
      status: 'Activa',
      recipientName: 'Ana',
      senderName: 'Juan',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GiftCardVisual(giftCard: card)),
      ),
    );
    await tester.runAsync(() => GoogleFonts.pendingFonts());
    await tester.pumpAndSettle();
    expect(find.text('GIFT'), findsOneWidget);
    expect(find.text('CARD'), findsNWidgets(2));
    expect(find.text('PARA:'), findsOneWidget);
    expect(find.text('DE:'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Juan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
