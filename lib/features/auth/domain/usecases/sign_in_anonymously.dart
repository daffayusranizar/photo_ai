import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class SignInAnonymously {
  final AuthRepository repository;

  SignInAnonymously(this.repository);

  Future<Either<Failure, User>> call() async {
    return await repository.signInAnonymously();
  }
}
