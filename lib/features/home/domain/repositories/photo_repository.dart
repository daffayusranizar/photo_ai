import 'dart:io';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/photo.dart';

abstract class PhotoRepository {
  Future<Either<Failure, void>> uploadPhoto(File image, {String? place, String? shotType, String? timeOfDay});
  Stream<List<Photo>> getPhotos(String userId);
}
