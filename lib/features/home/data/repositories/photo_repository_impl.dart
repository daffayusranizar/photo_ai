import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/photo.dart';
import '../../domain/repositories/photo_repository.dart';
import '../datasources/photo_remote_data_source.dart';

class PhotoRepositoryImpl implements PhotoRepository {
  final PhotoRemoteDataSource remoteDataSource;
  final FirebaseAuth firebaseAuth;

  PhotoRepositoryImpl({
    required this.remoteDataSource,
    required this.firebaseAuth,
  });

  @override
  Future<Either<Failure, void>> uploadPhoto(File image, {String? sceneType, String? shotType, String? timeOfDay}) async {
    try {
      final userId = firebaseAuth.currentUser?.uid;
      if (userId == null) return Left(ServerFailure()); // Should be logged in
      
      await remoteDataSource.uploadPhoto(image, userId, sceneType: sceneType, shotType: shotType, timeOfDay: timeOfDay);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Stream<List<Photo>> getPhotos(String userId) {
    return remoteDataSource.getPhotos(userId);
  }
}
