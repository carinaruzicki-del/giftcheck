import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class GiftCardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _createShareToken() {
    const characters =
        'abcdefghijklmnopqrstuvwxyz'
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        '0123456789';

    final random = Random.secure();

    return List.generate(
      32,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  CollectionReference<Map<String, dynamic>> get _giftCardsCollection {
    return _firestore.collection('giftCards');
  }

  String _codeFromSequence(int sequence) {
    const maxNumberPerPrefix = 999999;

    int prefixRank = ((sequence - 1) ~/ maxNumberPerPrefix) + 1;

    var value = prefixRank;
    var prefix = '';

    while (value > 0) {
      value--;
      prefix = String.fromCharCode(65 + (value % 26)) + prefix;
      value ~/= 26;
    }

    final number = ((sequence - 1) % maxNumberPerPrefix) + 1;

    final paddedNumber = number.toString().padLeft(6, '0');

    return prefix + paddedNumber;
  }

  Future<String> reserveNextGiftCardCode() async {
    final counterReference = _firestore.collection('counters').doc('giftCards');

    return await _firestore.runTransaction<String>((transaction) async {
      final counterSnapshot = await transaction.get(counterReference);

      final data = counterSnapshot.data();

      final lastSequence = data?['lastSequence'] as int? ?? 1;

      final nextSequence = lastSequence + 1;

      final nextCode = _codeFromSequence(nextSequence);

      transaction.set(counterReference, {
        'lastSequence': nextSequence,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return nextCode;
    });
  }

  Future<String> saveGiftCard({
    required String code,
    required String amount,
    required DateTime? expirationDate,
    required String dedication,
    required String status,
    required String senderName,
    required String recipientName,
  }) async {
    final shareToken = _createShareToken();

    final giftCardReference = _giftCardsCollection.doc(code);

    final publicECardReference = _firestore
        .collection('publicEcards')
        .doc(shareToken);

    final giftCardData = {
      'code': code,
      'amount': amount,
      'expirationDate': expirationDate == null
          ? null
          : Timestamp.fromDate(expirationDate),
      'dedication': dedication,
      'senderName': senderName,
      'recipientName': recipientName,
      'status': status,
      'shareToken': shareToken,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final publicECardData = {
      'code': code,
      'amount': amount,
      'expirationDate': expirationDate == null
          ? null
          : Timestamp.fromDate(expirationDate),
      'dedication': dedication,
      'senderName': senderName,
      'recipientName': recipientName,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.batch();

    batch.set(giftCardReference, giftCardData);
    batch.set(publicECardReference, publicECardData);

    await batch.commit();

    return shareToken;
  }

  Future<void> updateGiftCardStatus({
    required String code,
    required String status,
  }) async {
    await _giftCardsCollection.doc(code).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> loadGiftCards() async {
    final snapshot = await _giftCardsCollection
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((document) {
      final data = document.data();

      final expirationValue = data['expirationDate'];

      DateTime? expirationDate;

      if (expirationValue is Timestamp) {
        expirationDate = expirationValue.toDate();
      }

      return {
        'code': data['code'] as String? ?? document.id,
        'amount': data['amount'] as String? ?? '',
        'expirationDate': expirationDate,
        'dedication': data['dedication'] as String? ?? '',
        'senderName': data['senderName'] as String? ?? '',
        'recipientName': data['recipientName'] as String? ?? '',
        'status': data['status'] as String? ?? 'Activa',
      };
    }).toList();
  }

  Stream<List<Map<String, dynamic>>> watchGiftCards() {
    return _giftCardsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((document) {
            final data = document.data();

            final expirationValue = data['expirationDate'];

            DateTime? expirationDate;

            if (expirationValue is Timestamp) {
              expirationDate = expirationValue.toDate();
            }

            return {
              'code': data['code'] as String? ?? document.id,
              'amount': data['amount'] as String? ?? '',
              'expirationDate': expirationDate,
              'dedication': data['dedication'] as String? ?? '',
              'senderName': data['senderName'] as String? ?? '',
              'status': data['status'] as String? ?? 'Activa',
              'recipientName': data['recipientName'] as String? ?? '',
            };
          }).toList();
        });
  }

  Future<Map<String, dynamic>?> findGiftCardByCode(String code) async {
    final normalizedCode = code.trim().toUpperCase();

    if (normalizedCode.isEmpty) {
      return null;
    }

    // Gift cards are written with the code as the document id (see
    // saveGiftCard), so a direct lookup resolves without the query round trip.
    final document = await _giftCardsCollection.doc(normalizedCode).get();

    if (document.exists) {
      return document.data();
    }

    // Fall back to a query for any card that predates that convention.
    final snapshot = await _giftCardsCollection
        .where('code', isEqualTo: normalizedCode)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return snapshot.docs.first.data();
  }

  Future<void> saveGiftCardUsage({
    required String giftCardCode,
    required String amountUsed,
    required String username,
    required String accountUid,
  }) async {
    double parseAmount(Object? value) {
      final text = value?.toString() ?? '';

      final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

      return double.tryParse(digitsOnly) ?? 0;
    }

    final code = giftCardCode.trim().toUpperCase();
    final amountToUse = parseAmount(amountUsed);

    if (amountToUse <= 0) {
      throw Exception('El importe utilizado no es válido.');
    }

    final giftCardSnapshot = await _firestore
        .collection('giftCards')
        .where('code', isEqualTo: code)
        .limit(1)
        .get();

    if (giftCardSnapshot.docs.isEmpty) {
      throw Exception('No encontramos la Gift Card.');
    }

    final giftCardReference = giftCardSnapshot.docs.first.reference;

    final usageReference = _firestore.collection('giftCardUsages').doc();

    await _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(giftCardReference);

      final data = currentSnapshot.data() ?? {};

      final originalAmount = parseAmount(data['amount']);

      final usedAmount = parseAmount(data['usedAmount']);

      final storedRemaining = data['remainingAmount'];

      final remainingAmount = storedRemaining == null
          ? originalAmount - usedAmount
          : parseAmount(storedRemaining);

      if (amountToUse > remainingAmount) {
        throw Exception('El importe supera el saldo disponible.');
      }

      final newUsedAmount = usedAmount + amountToUse;
      final newRemainingAmount = remainingAmount - amountToUse;

      final newStatus = newRemainingAmount <= 0
          ? 'Canjeada'
          : 'Parcialmente usada';

      transaction.update(giftCardReference, {
        'usedAmount': newUsedAmount.toStringAsFixed(0),
        'remainingAmount': newRemainingAmount.toStringAsFixed(0),
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(usageReference, {
        'giftCardCode': code,
        'amountUsed': amountToUse.toStringAsFixed(0),
        'username': username.trim(),
        'accountUid': accountUid,
        'usedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<List<Map<String, dynamic>>> loadGiftCardUsages(
    String giftCardCode,
  ) async {
    final snapshot = await _firestore
        .collection('giftCardUsages')
        .where('giftCardCode', isEqualTo: giftCardCode.trim().toUpperCase())
        .get();

    final usages = snapshot.docs.map((document) => document.data()).toList();

    DateTime usageDate(Object? value) {
      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    usages.sort((a, b) {
      final dateA = usageDate(a['usedAt']);
      final dateB = usageDate(b['usedAt']);

      return dateB.compareTo(dateA);
    });

    return usages;
  }

  Future<List<Map<String, dynamic>>> loadAllGiftCardUsages() async {
    final snapshot = await _firestore.collection('giftCardUsages').get();

    final usages = snapshot.docs.map((document) => document.data()).toList();

    DateTime usageDate(Object? value) {
      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is DateTime) {
        return value;
      }

      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    usages.sort((a, b) {
      final dateA = usageDate(a['usedAt']);
      final dateB = usageDate(b['usedAt']);

      return dateB.compareTo(dateA);
    });

    return usages;
  }

  Stream<List<Map<String, dynamic>>> watchAllGiftCardUsages() {
    return _firestore.collection('giftCardUsages').snapshots().map((snapshot) {
      final usages = snapshot.docs.map((document) => document.data()).toList();

      DateTime usageDate(Object? value) {
        if (value is Timestamp) {
          return value.toDate();
        }

        if (value is DateTime) {
          return value;
        }

        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      usages.sort((a, b) {
        final dateA = usageDate(a['usedAt']);
        final dateB = usageDate(b['usedAt']);

        return dateB.compareTo(dateA);
      });

      return usages;
    });
  }

  Future<Map<String, dynamic>?> findPublicECard(String shareToken) async {
    final token = shareToken.trim();

    if (token.isEmpty) {
      return null;
    }

    final snapshot = await _firestore
        .collection('publicEcards')
        .doc(token)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    return snapshot.data();
  }
}
