import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/photo.dart';

abstract class PhotoRemoteDataSource {
  Future<void> uploadPhoto(File image, String userId, {String? sceneType, String? shotType, String? timeOfDay});
  Stream<List<Photo>> getPhotos(String userId);
}

class PhotoRemoteDataSourceImpl implements PhotoRemoteDataSource {
  final FirebaseStorage storage;
  final FirebaseFirestore firestore;

  PhotoRemoteDataSourceImpl({required this.storage, required this.firestore});

  @override
  Future<void> uploadPhoto(File image, String userId, {String? sceneType, String? shotType, String? timeOfDay}) async {
    final photoId = const Uuid().v4();
    final storagePath = 'users/$userId/uploads/$photoId.jpg';
    final ref = storage.ref().child(storagePath);
    
    // 1. Upload to Storage
    await ref.putFile(image);
    // No need for getDownloadURL() anymore

    // 2. Save metadata to Firestore (triggers Cloud Function)
    final data = {
      'id': photoId,
      'originalPath': storagePath, // Save path instead of URL
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    
    // Add user preferences if provided
    if (sceneType != null) data['sceneType'] = sceneType;
    if (shotType != null) data['shotType'] = shotType;
    if (timeOfDay != null) data['timeOfDay'] = timeOfDay;
    
    await firestore.collection('users').doc(userId).collection('photos').doc(photoId).set(data);
  }

  @override
  Stream<List<Photo>> getPhotos(String userId) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('photos')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Photo(
          id: data['id'],
          originalPath: data['originalPath'] ?? '', // Fallback or handle migration
          generatedPaths: (data['generatedPaths'] as List?)?.map((e) => e.toString()).toList() ?? [],
          status: data['status'] ?? 'pending',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          place: data['place'],
          shotType: data['shotType'],
          timeOfDay: data['timeOfDay'],
        );
      }).toList();
    });
  }
}
