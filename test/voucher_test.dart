import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giftcheck/gift_card_service.dart';
import 'package:giftcheck/voucher_validation.dart';

void main() {
  test('Mandatory integer amount; positive and within exact numeric range', () {
    for (final value in [null, '', '0', '-1', '1.5', 'abc', '1000000000000']) {
      expect(validateVoucherAmount(value), isNotNull);
    }
    expect(validateVoucherAmount('50000'), isNull);
  });
  test(
    'Expiration includes today and leap days; excludes past and missing dates',
    () {
      final now = DateTime(2028, 2, 29, 23, 50);
      expect(validateVoucherExpiration(null, now: now), isNotNull);
      expect(
        validateVoucherExpiration(DateTime(2028, 2, 28), now: now),
        isNotNull,
      );
      expect(
        validateVoucherExpiration(DateTime(2028, 2, 29), now: now),
        isNull,
      );
      expect(validateVoucherExpiration(DateTime(2500, 1, 1), now: now), isNull);
      expect(voucherEndOfDay(now).hour, 23);
    },
  );

  test(
    'Short code rolls over without gaining digits or colliding with Gift Cards',
    () {
      expect(voucherCodeFromSequence(1), 'VA000001');
      expect(voucherCodeFromSequence(999999), 'VA999999');
      expect(voucherCodeFromSequence(1000000), 'VB000001');
      expect(voucherCodeFromSequence(maxVoucherSequence), 'VZ999999');
      expect(
        () => voucherCodeFromSequence(maxVoucherSequence + 1),
        throwsStateError,
      );
    },
  );
  late FakeFirebaseFirestore db;
  late GiftCardService service;
  late String code;
  final expiry = DateTime.now().add(const Duration(days: 30));
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = GiftCardService(firestore: db);
    code = await service.reserveNextVoucherCode();
  });
  Future<void> create() => service.saveVoucher(
    code: code,
    amount: '50000',
    expirationDate: expiry,
    creatorUid: 'local1',
  );
  Future<Map<String, dynamic>> use(String amount) => service.saveGiftCardUsage(
    giftCardCode: code,
    amountUsed: amount,
    username: 'Local 1',
    accountUid: 'local1',
  );

  test(
    'Creates a unique voucher, supports manual lookup and idempotent retry',
    () async {
      expect(code, matches(r'^V[A-Z][0-9]{6}$'));
      expect(await service.reserveNextVoucherCode(), isNot(code));
      await create();
      await create();
      expect((await db.collection('giftCards').get()).docs, hasLength(1));
      final found = await service.findGiftCardByCode(' ${code.toLowerCase()} ');
      expect(found!['type'], 'voucher');
      expect(found['remainingAmount'], '50000');
      expect((found['expirationDate'] as Timestamp).toDate().hour, 23);
      expect((await db.collection('publicEcards').get()).docs, isEmpty);
    },
  );
  test('Gift Card numbering skips the reserved voucher range', () async {
    await db.collection('counters').doc('giftCards').set({
      'lastSequence': 572 * 999999,
    });
    expect(await service.reserveNextGiftCardCode(), 'WA000001');
  });
  test('Partial uses preserve balance, history and full redemption', () async {
    await create();
    expect((await use('10000'))['remainingAmount'], 40000);
    expect((await use('15000'))['remainingAmount'], 25000);
    await expectLater(use('30000'), throwsException);
    expect(await service.loadGiftCardUsages(code), hasLength(2));
    expect((await use('25000'))['status'], 'Canjeada');
    await expectLater(use('1'), throwsException);
    expect(await service.loadGiftCardUsages(code), hasLength(3));
  });
  test('Expired, blocked and canceled vouchers cannot be redeemed', () async {
    await create();
    final ref = db.collection('giftCards').doc(code);
    for (final status in ['Bloqueada', 'Anulada']) {
      await ref.update({'status': status});
      await expectLater(use('100'), throwsException);
    }
    await ref.update({
      'status': 'Activa',
      'expirationDate': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
    });
    await expectLater(use('100'), throwsException);
    expect(await service.loadGiftCardUsages(code), isEmpty);
  });
  test('Service rejects invalid fields even without the form', () async {
    await expectLater(
      service.saveVoucher(
        code: code,
        amount: '0',
        expirationDate: expiry,
        creatorUid: 'local1',
      ),
      throwsArgumentError,
    );
    await expectLater(
      service.saveVoucher(
        code: code,
        amount: '10',
        expirationDate: DateTime(2000),
        creatorUid: 'local1',
      ),
      throwsArgumentError,
    );
    expect((await db.collection('giftCards').get()).docs, isEmpty);
  });
}
