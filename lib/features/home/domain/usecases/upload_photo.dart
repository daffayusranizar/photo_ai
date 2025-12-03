import 'dart:io';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/photo_repository.dart';

class UploadPhoto {
  final PhotoRepository repository;

  UploadPhoto(this.repository);

  Future<Either<Failure, void>> call(File image, {String? place, String? shotType, String? timeOfDay}) async {
    return await repository.uploadPhoto(image, place: place, shotType: shotType, timeOfDay: timeOfDay);
  }
}
