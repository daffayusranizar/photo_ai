import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'injection_container.dart' as di;
import 'features/auth/domain/usecases/sign_in_anonymously.dart' as di; // Alias for test
import 'features/home/domain/usecases/get_photos.dart' as di; // Alias for test

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
        child: ElevatedButton(
          onPressed: () async {
            try {
              // 1. Test Auth
              final authUseCase = di.sl<di.SignInAnonymously>();
              final result = await authUseCase();
              
              result.fold(
                (failure) => print('Auth Failed: $failure'),
                (user) async {
                  print('Auth Success: User ID ${user.id}');
                  
                  // 2. Test Firestore Read (Empty stream check)
                  final photosUseCase = di.sl<di.GetPhotos>();
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
      ),
    );
  }
}
