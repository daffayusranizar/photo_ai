import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'injection_container.dart' as di;
import 'features/auth/domain/usecases/sign_in_anonymously.dart' as auth_uc;
import 'features/home/domain/usecases/get_photos.dart' as photo_uc;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp();
  
  await di.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Photo Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TestPage(),
    );
  }
}

class TestPage extends StatelessWidget {
  const TestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Step 3: Data Layer Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                try {
                  // 1. Test Auth
                  final authUseCase = di.sl<auth_uc.SignInAnonymously>();
                  final result = await authUseCase();
                  
                  result.fold(
                    (failure) => print('Auth Failed: $failure'),
                    (user) async {
                      print('Auth Success: User ID ${user.id}');
                      
                      // 2. Test Firestore Read (Empty stream check)
                      final photosUseCase = di.sl<photo_uc.GetPhotos>();
                      photosUseCase().listen((photos) {
                        print('Firestore Stream Active: Found ${photos.length} photos');
                      });
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Firebase Connection Successful! Check Console.')),
                      );
                    },
                  );
                } catch (e) {
                  print('Error: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('Test Firebase Connection'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  final auth = di.sl<auth_uc.SignInAnonymously>();
                  final result = await auth();
                  result.fold(
                    (l) => print('Auth First!'),
                    (user) async {
                      // Simulate Upload
                      final firestore = di.sl<FirebaseFirestore>();
                      final docRef = firestore
                          .collection('users')
                          .doc(user.id)
                          .collection('photos')
                          .doc();
                      
                      await docRef.set({
                        'id': docRef.id,
                        'originalUrl': 'https://picsum.photos/400', // Mock URL
                        'generatedUrl': null,
                        'status': 'pending',
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      
                      print('Simulated Upload: ${docRef.id}');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Upload Simulated! Check Firestore.')),
                      );
                    },
                  );
                } catch (e) {
                  print('Error: $e');
                }
              },
              child: const Text('Simulate Upload (Triggers AI)'),
            ),
          ],
        ),
      ),
    );
  }
}
