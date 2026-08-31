import 'package:cloud_firestore/cloud_firestore.dart';

class LocalRecord {
  final String id;
  final String name;
  final bool active;

  const LocalRecord({
    required this.id,
    required this.name,
    required this.active,
  });

  factory LocalRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? {};

    return LocalRecord(
      id: document.id,
      name: data['name'] as String? ?? '',
      active: data['active'] as bool? ?? true,
    );
  }
}

class LocalService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _localsCollection {
    return _firestore.collection('locals');
  }

  String _normalizeName(String value) {
    return value.trim().toLowerCase();
  }

  Future<void> createLocal({required String name}) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw Exception('Ingresá el nombre del local.');
    }

    final normalizedName = _normalizeName(cleanName);

    final existingLocal = await _localsCollection
        .where('normalizedName', isEqualTo: normalizedName)
        .limit(1)
        .get();

    if (existingLocal.docs.isNotEmpty) {
      throw Exception('Ya existe un local con ese nombre.');
    }

    await _localsCollection.add({
      'name': cleanName,
      'normalizedName': normalizedName,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<LocalRecord>> loadLocals() async {
    final snapshot = await _localsCollection.orderBy('name').get();

    return snapshot.docs
        .map((document) => LocalRecord.fromDocument(document))
        .toList();
  }

  Future<void> updateLocalName({
    required String localId,
    required String name,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw Exception('Ingresá el nombre del local.');
    }

    await _localsCollection.doc(localId).update({
      'name': cleanName,
      'normalizedName': _normalizeName(cleanName),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateLocalStatus({
    required String localId,
    required bool active,
  }) async {
    await _localsCollection.doc(localId).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
