import 'package:flutter/material.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/photo.dart';
import '../../domain/usecases/get_photos.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/photo_grid_item.dart';
import 'package:intl/intl.dart';
import '../widgets/photo_detail_dialog.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Stream<List<Photo>> _photosStream;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    _photosStream = sl<GetPhotos>()(userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('History', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Photo>>(
        stream: _photosStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final photos = snapshot.data ?? [];

          if (photos.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('No history yet.', style: TextStyle(color: Colors.white54)),
                ],
              ),
            );
          }

          // Group photos by date
          final groupedPhotos = _groupPhotosByDate(photos);

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groupedPhotos.length,
            itemBuilder: (context, index) {
              final date = groupedPhotos.keys.elementAt(index);
              final dayPhotos = groupedPhotos[date]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      date,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: dayPhotos.length,
                    itemBuilder: (context, photoIndex) {
                      return GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => PhotoDetailDialog(photo: dayPhotos[photoIndex]),
                          );
                        },
                        child: PhotoGridItem(photo: dayPhotos[photoIndex]),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Map<String, List<Photo>> _groupPhotosByDate(List<Photo> photos) {
    final Map<String, List<Photo>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (var photo in photos) {
      final date = photo.createdAt;
      final photoDate = DateTime(date.year, date.month, date.day);
      
      String header;
      if (photoDate == today) {
        header = 'Today';
      } else if (photoDate == yesterday) {
        header = 'Yesterday';
      } else {
        header = DateFormat('MMMM d, y').format(date);
      }

      if (!grouped.containsKey(header)) {
        grouped[header] = [];
      }
      grouped[header]!.add(photo);
    }
    return grouped;
  }
}
