import 'package:flutter/material.dart';
import '../../../../injection_container.dart';
import '../../domain/usecases/sign_in_anonymously.dart';
import '../../../home/presentation/pages/home_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLoading = false;

  Future<void> _signIn() async {
    setState(() => _isLoading = true);

    final signInUseCase = sl<SignInAnonymously>();
    final result = await signInUseCase();

    if (!mounted) return;

    result.fold(
      (failure) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: ${failure.toString()}')),
        );
      },
      (user) {
        // Navigate to Home Page on success
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 24),
              const Text(
                'AI Travel Photos',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Turn your selfies into travel masterpieces.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _signIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Get Started'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
