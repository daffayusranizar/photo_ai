import 'package:equatable/equatable.dart';

class Photo extends Equatable {
  final String id;
  final String originalUrl;
  final String? generatedUrl;
  final String status; // 'pending', 'completed', 'failed'
  final DateTime createdAt;

  const Photo({
    required this.id,
    required this.originalUrl,
    this.generatedUrl,
    required this.status,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, originalUrl, generatedUrl, status, createdAt];
}
