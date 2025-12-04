import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'private_image.dart';
import '../../domain/entities/photo.dart';

class PhotoGridItem extends StatelessWidget {
  final Photo photo;

  const PhotoGridItem({super.key, required this.photo});

  @override
  Widget build(BuildContext context) {
    // Show first generated variant if available, otherwise show original
    final displayPath = photo.generatedPaths.isNotEmpty 
        ? photo.generatedPaths[0] 
        : photo.originalPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Main Image
          PrivateImage(
            storagePath: displayPath,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey[200],
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF2667FF),
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[200],
              child: const Center(
                child: Icon(
                  Icons.error_outline,
                  color: Colors.black26,
                  size: 32,
                ),
              ),
            ),
          ),

          // Subtle badge if it has generated variants
          if (photo.generatedPaths.isNotEmpty)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${photo.generatedPaths.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
