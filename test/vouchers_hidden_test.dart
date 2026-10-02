import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giftcheck/main.dart';
import 'package:giftcheck/feature_flags.dart';
import 'package:giftcheck/account_service.dart';
import 'package:giftcheck/gift_card_service.dart';

void main() {
  if (vouchersEnabled) return;
  const local = AccountProfile(uid:'local',username:'Local',email:'',role:'local',localName:'Local',active:true);
  Future<GiftCardService> seed() async {
    final db = FakeFirebaseFirestore();
    for (final code in ['A000001','VA000001']) {
      await db.collection('giftCards').doc(code).set({'code':code,'amount':'10000','status':'Activa','createdAt':Timestamp.now()});
      await db.collection('giftCardUsages').add({'giftCardCode':code,'amountUsed':'1000','usedAt':Timestamp.now()});
    }
    return GiftCardService(firestore:db);
  }
  testWidgets('Both roles hide vouchers while preserving Gift Card actions', (tester) async {
    tester.view.physicalSize = const Size(1000,2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home:LocalHomePage(profile:local)));
    await tester.pumpAndSettle();
    expect(find.text('Crear voucher'),findsNothing);
    expect(find.text('Escanear QR'),findsOneWidget);
    expect(find.text('Ingresar código manualmente'),findsOneWidget);
    await tester.pumpWidget(MaterialApp(home:AdminHomePage(displayName:'Admin',service:await seed())));
    await tester.pumpAndSettle();
    expect(find.text('Crear voucher'),findsNothing);
    expect(find.text('Crear Gift Card'),findsWidgets);
    expect(find.text('Ingresar código manualmente'),findsNothing);
    expect(find.textContaining('VA000001'),findsNothing);
    expect(find.textContaining('A000001'),findsOneWidget);
  });
  testWidgets('Issued and usage histories hide vouchers without deleting them', (tester) async {
    final service = await seed();
    await tester.pumpWidget(MaterialApp(home:CardHistoryPage(service:service)));
    await tester.pumpAndSettle();
    expect(find.text('Gift Card A000001'),findsOneWidget);
    expect(find.textContaining('VA000001'),findsNothing);
    await tester.tap(find.text('Usos'));await tester.pumpAndSettle();
    expect(find.text('Gift Card A000001'),findsOneWidget);
    expect(find.textContaining('VA000001'),findsNothing);
    expect(await service.findGiftCardByCode('VA000001'),isNotNull);
  });
  testWidgets('Disabled creation cannot open form and lookup rejects voucher codes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:CreateVoucherPage()));
    expect(find.text('Esta sección no está habilitada.'),findsOneWidget);
    expect(find.byType(TextFormField),findsNothing);
    await tester.pumpWidget(MaterialApp(home:LocalHomePage(profile:local,service:await seed())));
    await tester.tap(find.text('Ingresar código manualmente'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField),'VA000001');
    await tester.tap(find.text('Consultar'));await tester.pumpAndSettle();
    expect(find.text('Código no disponible'),findsOneWidget);
    expect(find.text('Registrar uso'),findsNothing);
  });
}
