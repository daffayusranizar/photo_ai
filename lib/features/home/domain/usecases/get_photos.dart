import '../entities/photo.dart';
import '../repositories/photo_repository.dart';

class GetPhotos {
  final PhotoRepository repository;

  GetPhotos(this.repository);

  Stream<List<Photo>> call(String userId) {
    return repository.getPhotos(userId);
  }
}
