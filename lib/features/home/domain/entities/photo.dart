import 'package:equatable/equatable.dart';

class Photo extends Equatable {
  final String id;
  final String originalPath;
  final List<String> generatedPaths; // Changed from single URL to array for 4 variants
  final String status; // 'pending', 'completed', 'failed'
  final DateTime createdAt;
  
  // User preferences for generation
  final String? place;
  final String? shotType; // 'fullbody', 'half', 'closeup', 'landscape'
  final String? timeOfDay; // 'morning', 'sunrise', 'noon', 'afternoon', 'sunset', 'night'

  const Photo({
    required this.id,
    required this.originalPath,
    this.generatedPaths = const [],
    required this.status,
    required this.createdAt,
    this.place,
    this.shotType,
    this.timeOfDay,
  });

  @override
  List<Object?> get props => [id, originalPath, generatedPaths, status, createdAt, place, shotType, timeOfDay];
}
