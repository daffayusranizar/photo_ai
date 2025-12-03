import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'private_image.dart';
import '../../domain/entities/photo.dart';

class PhotoGridItem extends StatelessWidget {
  final Photo photo;

  const PhotoGridItem({super.key, required this.photo});

  @override
  Widget build(BuildContext context) {
    final isCompleted = photo.status == 'completed';
    final isFailed = photo.status == 'failed';
    final displayPath = isCompleted && photo.generatedPaths.isNotEmpty 
        ? photo.generatedPaths[0] 
        : photo.originalPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Main Image
          if (displayPath.isNotEmpty)
            PrivateImage(
              storagePath: displayPath,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: Colors.grey[200]),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            )
          else
            Container(color: Colors.grey[300]),

          // Overlay for Pending State
          if (!isCompleted && !isFailed)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // Overlay for Failed State
          if (isFailed)
            Container(
              color: Colors.red.withOpacity(0.5),
              child: const Center(
                child: Icon(Icons.error_outline, color: Colors.white, size: 32),
              ),
            ),

          // Status Label (Optional)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Text(
                isCompleted ? '✨ AI Magic' : (isFailed ? 'Failed' : 'Processing...'),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
