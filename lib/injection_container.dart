import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get_it/get_it.dart';

import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/domain/usecases/sign_in_anonymously.dart';
import 'features/home/data/datasources/photo_remote_data_source.dart';
import 'features/home/data/repositories/photo_repository_impl.dart';
import 'features/home/domain/repositories/photo_repository.dart';
import 'features/home/domain/usecases/get_photos.dart';
import 'features/home/domain/usecases/upload_photo.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // Features - Auth
  // Use cases
  sl.registerLazySingleton(() => SignInAnonymously(sl()));

  // Repository
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(remoteDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSourceImpl(
      firebaseAuth: sl(),
      firestore: sl(),
    ),
  );

  // Features - Home
  // Use cases
  sl.registerLazySingleton(() => UploadPhoto(sl()));
  sl.registerLazySingleton(() => GetPhotos(sl()));

  // Repository
  sl.registerLazySingleton<PhotoRepository>(
    () => PhotoRepositoryImpl(remoteDataSource: sl(), firebaseAuth: sl()),
  );

  // Data sources
  sl.registerLazySingleton<PhotoRemoteDataSource>(
    () => PhotoRemoteDataSourceImpl(storage: sl(), firestore: sl()),
  );

  // External
  sl.registerLazySingleton(() => FirebaseAuth.instance);
  sl.registerLazySingleton(() => FirebaseFirestore.instance);
  sl.registerLazySingleton(() => FirebaseStorage.instanceFor(bucket: 'gs://photo-ai-16051.firebasestorage.app'));
}
