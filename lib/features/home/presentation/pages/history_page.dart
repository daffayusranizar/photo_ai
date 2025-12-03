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
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: _buildHeader(),
            ),

            // Content
            Expanded(
              child: StreamBuilder<List<Photo>>(
                stream: _photosStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.black26,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFF2667FF),
                        ),
                      ),
                    );
                  }

                  final photos = snapshot.data ?? [];

                  if (photos.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.history,
                            size: 64,
                            color: Colors.black12,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No history yet',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Your generated remixes will appear here',
                            style: TextStyle(
                              color: Colors.black45,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Group photos by date
                  final groupedPhotos = _groupPhotosByDate(photos);

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: groupedPhotos.length,
                    itemBuilder: (context, index) {
                      final date = groupedPhotos.keys.elementAt(index);
                      final dayPhotos = groupedPhotos[date]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: index == 0 ? 0 : 24,
                              bottom: 12,
                            ),
                            child: Text(
                              date,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
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
                                    barrierColor: Colors.black.withOpacity(0.7),
                                    builder: (context) => PhotoDetailDialog(
                                      photo: dayPhotos[photoIndex],
                                    ),
                                  );
                                },
                                child: PhotoGridItem(
                                  photo: dayPhotos[photoIndex],
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Colors.black87,
          ),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
        ),
        const Spacer(),
        const Text(
          'History',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 36), // Balance the back button
      ],
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
