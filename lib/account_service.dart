import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountProfile {
  final String uid;
  final String username;
  final String email;
  final String role;
  final String localName;
  final bool active;

  const AccountProfile({
    required this.uid,
    required this.username,
    required this.email,
    required this.role,
    required this.localName,
    required this.active,
  });

  bool get isAdministrator => role == 'administrator';
  bool get isLocal => role == 'local';

  factory AccountProfile.fromMap(String uid, Map<String, dynamic> data) {
    return AccountProfile(
      uid: uid,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'local',
      localName: data['localName'] as String? ?? '',
      active: data['active'] as bool? ?? true,
    );
  }
}

class AccountService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String normalizeUsername(String value) {
    return value.trim().toLowerCase();
  }

  Future<void> registerAccount({
    required String username,
    required String email,
    required String password,
    required String role,
    required String localName,
  }) async {
    final normalizedUsername = normalizeUsername(username);

    if (normalizedUsername.isEmpty) {
      throw Exception('Ingresá un nombre de usuario.');
    }

    if (email.trim().isEmpty) {
      throw Exception('Ingresá un email.');
    }

    if (password.length < 6) {
      throw Exception('La contraseña debe tener al menos 6 caracteres.');
    }

    final aliasReference = _firestore
        .collection('loginAliases')
        .doc(normalizedUsername);

    final aliasSnapshot = await aliasReference.get();

    if (aliasSnapshot.exists) {
      throw Exception('Ese nombre de usuario ya está registrado.');
    }

    UserCredential? credential;

    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('Firebase no devolvió el usuario creado.');
      }

      if (_auth.currentUser?.uid != user.uid) {
        throw Exception(
          'La cuenta se creó, pero Firebase no inició su sesión.',
        );
      }

      await user.updateDisplayName(username.trim());
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      try {
        await _firestore.collection('accounts').doc(user.uid).set({
          'uid': user.uid,
          'username': username.trim(),
          'email': email.trim(),
          'role': role,
          'localName': localName.trim(),
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (error) {
        throw Exception('Error guardando accounts: ${error.code}');
      }

      try {
        await aliasReference.set({'email': email.trim(), 'uid': user.uid});
      } on FirebaseException catch (error) {
        throw Exception('Error guardando loginAliases: ${error.code}');
      }

      await _auth.signOut();
    } catch (error) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      rethrow;
    }
  }

  Future<AccountProfile> signIn({
    required String identifier,
    required String password,
  }) async {
    final value = identifier.trim();

    if (value.isEmpty) {
      throw Exception('Ingresá tu usuario o email.');
    }

    String email = value;

    if (!value.contains('@')) {
      final aliasSnapshot = await _firestore
          .collection('loginAliases')
          .doc(normalizeUsername(value))
          .get();

      if (!aliasSnapshot.exists) {
        throw Exception('No encontramos ese nombre de usuario.');
      }

      final aliasData = aliasSnapshot.data();

      if (aliasData == null || aliasData['email'] == null) {
        throw Exception('La cuenta no tiene un email válido.');
      }

      email = aliasData['email'] as String;
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('No se pudo iniciar sesión.');
      }

      final accountSnapshot = await _firestore
          .collection('accounts')
          .doc(user.uid)
          .get();

      if (!accountSnapshot.exists) {
        await _auth.signOut();

        throw Exception('No encontramos el perfil de esta cuenta.');
      }

      final accountData = accountSnapshot.data();

      if (accountData == null) {
        await _auth.signOut();

        throw Exception('El perfil de la cuenta está vacío.');
      }

      final profile = AccountProfile.fromMap(user.uid, accountData);

      if (!profile.active) {
        await _auth.signOut();

        throw Exception('Esta cuenta está desactivada.');
      }

      return profile;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'invalid-credential' ||
          error.code == 'user-not-found' ||
          error.code == 'wrong-password') {
        throw Exception('El usuario o la contraseña son incorrectos.');
      }

      if (error.code == 'invalid-email') {
        throw Exception('El email de la cuenta no es válido.');
      }

      throw Exception('No se pudo iniciar sesión.');
    }
  }

  Future<void> sendPasswordReset({required String identifier}) async {
    final value = identifier.trim();

    if (value.isEmpty) {
      throw Exception('Ingresá tu usuario o email.');
    }

    String email = value;

    if (!value.contains('@')) {
      final aliasSnapshot = await _firestore
          .collection('loginAliases')
          .doc(normalizeUsername(value))
          .get();

      if (!aliasSnapshot.exists) {
        throw Exception('No encontramos ese nombre de usuario.');
      }

      final aliasData = aliasSnapshot.data();

      if (aliasData == null || aliasData['email'] == null) {
        throw Exception('La cuenta no tiene un email válido.');
      }

      email = aliasData['email'] as String;
    }

    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<AccountProfile?> getCurrentProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    final accountSnapshot = await _firestore
        .collection('accounts')
        .doc(user.uid)
        .get();

    if (!accountSnapshot.exists) {
      await _auth.signOut();
      return null;
    }

    final accountData = accountSnapshot.data();

    if (accountData == null) {
      await _auth.signOut();
      return null;
    }

    final profile = AccountProfile.fromMap(user.uid, accountData);

    if (!profile.active) {
      await _auth.signOut();
      return null;
    }

    return profile;
  }

  Future<List<AccountProfile>> loadAccounts() async {
    final snapshot = await _firestore.collection('accounts').get();

    return snapshot.docs.map((document) {
      final data = document.data();

      return AccountProfile.fromMap(document.id, data);
    }).toList();
  }

  Future<void> updateAccountStatus({
    required String uid,
    required bool active,
  }) async {
    await _firestore.collection('accounts').doc(uid).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
