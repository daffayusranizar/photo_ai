import 'package:firebase_auth/firebase_auth.dart';
import '../../domain/entities/user.dart' as entity;

abstract class AuthRemoteDataSource {
  Future<entity.User> signInAnonymously();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseAuth firebaseAuth;

  AuthRemoteDataSourceImpl({required this.firebaseAuth});

  @override
  Future<entity.User> signInAnonymously() async {
    final userCredential = await firebaseAuth.signInAnonymously();
    final user = userCredential.user!;
    return entity.User(id: user.uid);
  }
}
