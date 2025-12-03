import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../domain/entities/user.dart' as entity;

abstract class AuthRemoteDataSource {
  Future<entity.User> signInAnonymously();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseAuth firebaseAuth;
  final FirebaseFirestore firestore;

  AuthRemoteDataSourceImpl({
    required this.firebaseAuth,
    required this.firestore,
  });

  @override
  Future<entity.User> signInAnonymously() async {
    final userCredential = await firebaseAuth.signInAnonymously();
    final user = userCredential.user!;
    
    // Save user to Firestore
    await firestore.collection('users').doc(user.uid).set({
      'id': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return entity.User(id: user.uid);
  }
}
