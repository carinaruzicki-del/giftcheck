import 'package:giftcheck/feature_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giftcheck/main.dart';
import 'package:giftcheck/account_service.dart';
import 'package:giftcheck/gift_card_service.dart';

void main() {
  if (!vouchersEnabled) return;
  Future<FakeFirebaseFirestore> seed() async {
    final db = FakeFirebaseFirestore();
    await db.collection('giftCards').doc('VA000001').set({
      'code': 'VA000001',
      'amount': '10000',
      'status': 'Activa',
      'expirationDate': Timestamp.fromDate(DateTime(2100)),
      'createdAt': Timestamp.now(),
    });
    return db;
  }

  AccountProfile profile(String role) => AccountProfile(
    uid: 'test',
    username: 'test',
    email: '',
    role: role,
    localName: 'Local',
    active: true,
  );
  testWidgets('Unused vouchers appear under issued; usage tab remains empty', (
    tester,
  ) async {
    final db = await seed();
    await tester.pumpWidget(
      MaterialApp(
        home: CardHistoryPage(service: GiftCardService(firestore: db)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Voucher VA000001'), findsOneWidget);
    await tester.tap(find.text('Usos'));
    await tester.pumpAndSettle();
    expect(find.text('No hay registros para mostrar.'), findsOneWidget);
  });
  testWidgets('Administrator can block and reactivate from the shared detail', (
    tester,
  ) async {
    final db = await seed();
    await tester.pumpWidget(
      MaterialApp(
        home: CardHistoryDetailPage(
          code: 'VA000001',
          service: GiftCardService(firestore: db),
          profile: profile('administrator'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ver y compartir Voucher'), findsOneWidget);
    await tester.tap(find.text('Bloquear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(
      (await db.collection('giftCards').doc('VA000001').get())
          .data()!['status'],
      'Bloqueada',
    );
    await tester.tap(find.text('Reactivar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(
      (await db.collection('giftCards').doc('VA000001').get())
          .data()!['status'],
      'Activa',
    );
  });
  testWidgets(
    'Local sees sharing and remaining balance but no status controls',
    (tester) async {
      final db = await seed();
      await db.collection('giftCardUsages').add({
        'giftCardCode': 'VA000001',
        'amountUsed': 2500,
        'usedAt': Timestamp.now(),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CardHistoryDetailPage(
            code: 'VA000001',
            service: GiftCardService(firestore: db),
            profile: profile('local'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ver y compartir Voucher'), findsOneWidget);
      expect(find.text('Bloquear'), findsNothing);
      expect(find.text('Anular'), findsNothing);
      expect(find.textContaining('7.500'), findsOneWidget);
    },
  );
  testWidgets('Home actions follow role priorities', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: LocalHomePage(profile: profile('local'))),
    );
    await tester.pumpAndSettle();
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Escanear QR'), lessThan(y('Ingresar código manualmente')));
    expect(y('Ingresar código manualmente'), lessThan(y('Crear voucher')));
    expect(y('Crear voucher'), lessThan(y('Historial')));
    expect(find.text('Vouchers emitidos'), findsNothing);
    final db = await seed();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomePage(
          displayName: 'Admin',
          service: GiftCardService(firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(y('Crear Gift Card'), lessThan(y('Crear voucher')));

    expect(y('Crear voucher'),lessThan(y('Historial de Gift Cards y vouchers')));
    expect(find.text('Ingresar código manualmente'),findsNothing);
    expect(find.text('Escanear QR'), findsNothing);
    expect(find.text('Vouchers emitidos'), findsNothing);
  });
  testWidgets('Expired voucher lookup shows notice without usage inputs', (tester) async {
    final db = await seed();
    await db.collection('giftCards').doc('VA000001').update({'expirationDate':Timestamp.fromDate(DateTime.now().subtract(const Duration(days:1)))});
    await tester.pumpWidget(MaterialApp(home:LocalHomePage(profile:profile('local'),service:GiftCardService(firestore:db))));
    await tester.tap(find.text('Ingresar código manualmente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'VA000001');
    await tester.tap(find.text('Consultar'));
    await tester.pumpAndSettle();
    expect(find.text('Voucher vencido'),findsOneWidget);
    expect(find.textContaining('No se puede utilizar'),findsOneWidget);
    expect(find.text('Registrar uso'),findsNothing);
    expect(find.byType(TextField),findsNothing);
  });

}
