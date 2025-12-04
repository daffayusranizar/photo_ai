import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/private_image.dart';

import '../../../../injection_container.dart';
import '../../domain/usecases/upload_photo.dart';
import 'history_page.dart';

class RemixPage extends StatefulWidget {
  final File? imageFile;

  const RemixPage({super.key, this.imageFile});

  @override
  State<RemixPage> createState() => _RemixPageState();
}

class _RemixPageState extends State<RemixPage> {
  File? _imageFile;
  
  // Comprehensive Scene Selection - matches Cloud Function sceneMap
  final List<Map<String, String>> _scenes = [
    // ORIGINAL CORE SCENES
    {'id': 'cafe', 'label': 'Café', 'icon': '☕', 'category': 'Popular'},
    {'id': 'mountain', 'label': 'Mountain', 'icon': '🏔️', 'category': 'Popular'},
    {'id': 'beach', 'label': 'Beach', 'icon': '🏖️', 'category': 'Popular'},
    {'id': 'luxury_car', 'label': 'Luxury Car', 'icon': '🚗', 'category': 'Popular'},
    {'id': 'city_street', 'label': 'City Street', 'icon': '🏙️', 'category': 'Popular'},
    
    // NATURE & OUTDOOR
    {'id': 'forest', 'label': 'Forest', 'icon': '🌲', 'category': 'Nature'},
    {'id': 'lake', 'label': 'Lake', 'icon': '🏞️', 'category': 'Nature'},
    {'id': 'waterfall', 'label': 'Waterfall', 'icon': '💧', 'category': 'Nature'},
    {'id': 'desert', 'label': 'Desert', 'icon': '🏜️', 'category': 'Nature'},
    {'id': 'garden', 'label': 'Garden', 'icon': '🌺', 'category': 'Nature'},
    {'id': 'park', 'label': 'Park', 'icon': '🌳', 'category': 'Nature'},
    {'id': 'sunset_field', 'label': 'Sunset Field', 'icon': '🌅', 'category': 'Nature'},
    
    // URBAN & ARCHITECTURE
    {'id': 'rooftop', 'label': 'Rooftop', 'icon': '🏢', 'category': 'Urban'},
    {'id': 'bridge', 'label': 'Bridge', 'icon': '🌉', 'category': 'Urban'},
    {'id': 'shopping_district', 'label': 'Shopping District', 'icon': '🛍️', 'category': 'Urban'},
    {'id': 'metro_station', 'label': 'Metro Station', 'icon': '🚇', 'category': 'Urban'},
    {'id': 'skyscraper', 'label': 'Skyscraper', 'icon': '🏙️', 'category': 'Urban'},
    {'id': 'alley', 'label': 'Alley', 'icon': '🏘️', 'category': 'Urban'},
    {'id': 'plaza', 'label': 'Plaza', 'icon': '🏛️', 'category': 'Urban'},
    
    // LANDMARKS & TRAVEL
    {'id': 'eiffel_tower', 'label': 'Eiffel Tower', 'icon': '🗼', 'category': 'Landmarks'},
    {'id': 'times_square', 'label': 'Times Square', 'icon': '🗽', 'category': 'Landmarks'},
    {'id': 'colosseum', 'label': 'Colosseum', 'icon': '🏛️', 'category': 'Landmarks'},
    {'id': 'taj_mahal', 'label': 'Taj Mahal', 'icon': '🕌', 'category': 'Landmarks'},
    {'id': 'statue_liberty', 'label': 'Statue of Liberty', 'icon': '🗽', 'category': 'Landmarks'},
    {'id': 'big_ben', 'label': 'Big Ben', 'icon': '🕰️', 'category': 'Landmarks'},
    
    // LEISURE & ACTIVITIES
    {'id': 'airport', 'label': 'Airport', 'icon': '✈️', 'category': 'Activities'},
    {'id': 'gym', 'label': 'Gym', 'icon': '💪', 'category': 'Activities'},
    {'id': 'library', 'label': 'Library', 'icon': '📚', 'category': 'Activities'},
    {'id': 'museum', 'label': 'Museum', 'icon': '🖼️', 'category': 'Activities'},
    {'id': 'restaurant', 'label': 'Restaurant', 'icon': '🍽️', 'category': 'Activities'},
    {'id': 'hotel_lobby', 'label': 'Hotel Lobby', 'icon': '🏨', 'category': 'Activities'},
    {'id': 'pool', 'label': 'Pool', 'icon': '🏊', 'category': 'Activities'},
    {'id': 'yacht', 'label': 'Yacht', 'icon': '🛥️', 'category': 'Activities'},
    
    // COZY & INDOOR
    {'id': 'bookstore', 'label': 'Bookstore', 'icon': '📖', 'category': 'Indoor'},
    {'id': 'coffee_shop', 'label': 'Coffee Shop', 'icon': '☕', 'category': 'Indoor'},
    {'id': 'home_interior', 'label': 'Home Interior', 'icon': '🏠', 'category': 'Indoor'},
    {'id': 'balcony', 'label': 'Balcony', 'icon': '🪴', 'category': 'Indoor'},
    
    // SEASONAL & SPECIAL
    {'id': 'cherry_blossoms', 'label': 'Cherry Blossoms', 'icon': '🌸', 'category': 'Seasonal'},
    {'id': 'autumn_leaves', 'label': 'Autumn Leaves', 'icon': '🍂', 'category': 'Seasonal'},
    {'id': 'snow_scene', 'label': 'Snow Scene', 'icon': '❄️', 'category': 'Seasonal'},
    {'id': 'rain', 'label': 'Rain', 'icon': '🌧️', 'category': 'Seasonal'},
    
    // UNIQUE & CREATIVE
    {'id': 'graffiti_wall', 'label': 'Graffiti Wall', 'icon': '🎨', 'category': 'Creative'},
    {'id': 'neon_lights', 'label': 'Neon Lights', 'icon': '💡', 'category': 'Creative'},
    {'id': 'vintage_car', 'label': 'Vintage Car', 'icon': '🚙', 'category': 'Creative'},
    {'id': 'motorcycle', 'label': 'Motorcycle', 'icon': '🏍️', 'category': 'Creative'},
    {'id': 'ferris_wheel', 'label': 'Ferris Wheel', 'icon': '🎡', 'category': 'Creative'},
    {'id': 'concert_venue', 'label': 'Concert', 'icon': '🎸', 'category': 'Creative'},
    {'id': 'sports_stadium', 'label': 'Sports Stadium', 'icon': '🏟️', 'category': 'Creative'},
  ];
  String _selectedSceneId = 'cafe';
  String _selectedShotType = 'Fullbody';
  String _selectedTime = 'Sunset';

  bool _isGenerating = false;
  bool _isUploading = false;
  bool _isLoadingImage = false;
  bool _generationComplete = false;
  List<String> _generatedPaths = [];
  final ImagePicker _picker = ImagePicker();
  StreamSubscription? _generationSubscription;
  String? _currentPhotoId;

  // Progressive generation tracking
  int _variantsCompleted = 0;
  int _variantsTotal = 4;

  int _selectedPreviewIndex = 0;

  static const List<String> _shotTypes = [
    'Fullbody',
    'Half',
    'Close-up',
    'Landscape',
  ];
  static const List<String> _times = [
    'Morning',
    'Sunrise',
    'Noon',
    'Afternoon',
    'Sunset',
    'Night',
  ];

  @override
  void initState() {
    super.initState();
    _imageFile = widget.imageFile;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() => _isLoadingImage = true);
      await Future.delayed(const Duration(milliseconds: 100));

      final file = File(image.path);
      final fileSize = await file.length();

      if (fileSize > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image too large. Please select a smaller image.'),
            ),
          );
          setState(() => _isLoadingImage = false);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _imageFile = file;
          _isLoadingImage = false;
        });
        _resetGenerationData();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showImageSourceSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.black87),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.black87),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _resetGenerationData() {
    _generationSubscription?.cancel();
    if (mounted) {
      setState(() {
        _generatedPaths.clear();
        _generationComplete = false;
        _currentPhotoId = null;
        _selectedPreviewIndex = 0;
      });
    }
  }

  Future<void> _generateScenes() async {
    if (_imageFile == null) {
      print('❌ [RemixPage] No image selected - cannot generate');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a selfie first')),
      );
      return;
    }

    print('🚀 [RemixPage] Starting image generation...');
    print('   📍 Scene: $_selectedSceneId');
    print('   📸 Shot Type: $_selectedShotType');
    print('   ⏰ Time of Day: $_selectedTime');

    setState(() {
      _isUploading = true; // Start with upload state
      _isGenerating = false;
      _generatedPaths.clear();
      _generationComplete = false;
      _selectedPreviewIndex = 0;
    });

    try {
      final uploadUseCase = sl<UploadPhoto>();

      print('   ⬆️  Uploading image to Firebase...');
      final result = await uploadUseCase(
        _imageFile!,
        sceneType: _selectedSceneId,
        shotType: _selectedShotType.toLowerCase(),
        timeOfDay: _selectedTime.toLowerCase(),
      );
      print('   ✅ Upload complete - Cloud Function triggered');

      result.fold(
        (failure) {
          if (mounted) {
            setState(() {
              _isUploading = false;
              _isGenerating = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: $failure')),
            );
          }
        },
        (_) async {
          if (!mounted) return;

          // Upload complete, now switch to generating state
          setState(() {
            _isUploading = false;
            _isGenerating = true;
          });

          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              throw Exception('User not authenticated');
            }

            final snapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('photos')
                .orderBy('createdAt', descending: true)
                .limit(1)
                .get();

            if (snapshot.docs.isEmpty) {
              throw Exception('Photo document not found');
            }

            final photoId = snapshot.docs.first.id;

            if (mounted) {
              _currentPhotoId = photoId;
              _listenForGenerationResults(photoId);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Generating 4 variants... This may take 30-60 seconds',
                  ),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              setState(() => _isGenerating = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error getting photo ID: $e')),
              );
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _listenForGenerationResults(String photoId) {
    _generationSubscription?.cancel();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    print('👂 [RemixPage] Listening for progressive generation results...');

    _generationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('photos')
        .doc(photoId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      if (snapshot.exists) {
        final data = snapshot.data();

        if (data != null) {
          // Get progressive update data
          final paths = data['generatedPaths'] != null 
              ? List<String>.from(data['generatedPaths'] as List)
              : <String>[];
          final completed = data['variantsCompleted'] ?? 0;
          final total = data['variantsTotal'] ?? 4;
          final status = data['status'] ?? 'pending';

          // Check if new variant arrived
          final hasNewVariant = paths.length > _generatedPaths.length;

          print('📊 [RemixPage] Firestore update:');
          print('   Paths: ${paths.length}, Completed: $completed/$total, Status: $status');
          print('   Current state: _generatedPaths=${_generatedPaths.length}, _isGenerating=$_isGenerating');

          if (mounted) {
            setState(() {
              _generatedPaths = paths;
              _variantsCompleted = completed;
              _variantsTotal = total;
              _isGenerating = status == 'generating';
              _generationComplete = status == 'completed';
              
              // Auto-select the latest variant when it arrives
              if (hasNewVariant && paths.isNotEmpty) {
                _selectedPreviewIndex = paths.length - 1;
              }
            });

            print('   ✅ State updated: _generatedPaths=${_generatedPaths.length}, _isGenerating=$_isGenerating');

            // Show toast notification for new variant
            if (hasNewVariant && paths.isNotEmpty) {
              final remaining = total - paths.length;
              final message = remaining > 0
                  ? 'Variant ${paths.length} ready! Generating $remaining more...'
                  : 'All variants complete!';
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }

          // Cancel listener when complete
          if (status == 'completed') {
            print('✅ [RemixPage] All variants completed!');
            _generationSubscription?.cancel();
          }
        }
      }
    }, onError: (error) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error listening for results: $error')),
        );
      }
    });
  }

  void _resetAll() {
    print('🔄 [RemixPage] Resetting all data - clearing image and selections');
    _generationSubscription?.cancel();
    if (mounted) {
      setState(() {
        _imageFile = null;
        _generatedPaths.clear();
        _generationComplete = false;
        _currentPhotoId = null;
        _selectedPreviewIndex = 0;
        // Reset to defaults
        _selectedSceneId = 'cafe';
        _selectedShotType = 'Fullbody';
        _selectedTime = 'Sunset';
      });
    }
  }

  void _handleButtonPress() {
    print('🔘 [RemixPage] Generate button pressed');
    if (_generationComplete) {
      print('   ↳ Generation complete - resetting for new remix');
      _resetAll();
    } else {
      print('   ↳ Starting new generation');
      _generateScenes();
    }
  }

  @override
  void dispose() {
    _generationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _buildHeader(),
            ),
            const SizedBox(height: 16),

            // Preview section that fills available space
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Flexible(
                      child: _buildPreviewSection(),
                    ),
                    const SizedBox(height: 14),
                    _buildThumbnailStrip(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Inputs stick above keyboard
            Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _buildSceneSelector(),
                  const SizedBox(height: 10),
                  _buildOptionsRow(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomButton(),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'Remix',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryPage()),
            );
          },
          icon: const Icon(Icons.history, color: Colors.black54, size: 20),
          label: const Text(
            'History',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    final bool hasResults = _generatedPaths.isNotEmpty;
    final bool hasSelfie = _imageFile != null;

    print('🖼️ [Preview] Building preview: hasResults=$hasResults (${_generatedPaths.length} paths), _isGenerating=$_isGenerating, _isUploading=$_isUploading');

    Widget child;

    // FIXED: Check states in priority order: Upload > Generate > Results > Selfie > Empty
    // This prevents flashing between states
    if (_isUploading) {
      // Priority 1: Show upload state first
      child = Column(
        key: const ValueKey('uploading'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF2667FF),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Uploading your photo...',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'This will only take a moment',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      );
    } else if (_isGenerating && !hasResults) {
      // Priority 2: Show generating state (before first result arrives)
      child = Column(
        key: const ValueKey('generating_initial'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF2667FF),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Starting generation...',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'First variant in 30-60 seconds',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      );
    } else if (hasResults) {
      // Priority 3: Show generated images (even while still generating)
      final imagePath = _generatedPaths[
          _selectedPreviewIndex.clamp(0, _generatedPaths.length - 1)];
      child = Stack(
        key: ValueKey('result_$imagePath'), // Unique key per image
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: PrivateImage(
              storagePath: imagePath,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          // Show progress overlay if still generating
          if (_isGenerating)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Generating $_variantsCompleted/$_variantsTotal...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    } else if (hasSelfie) {
      // Priority 4: Show selfie preview
      child = ClipRRect(
        key: ValueKey('selfie_${_imageFile?.path}'),
        borderRadius: BorderRadius.circular(24),
        child: Image.file(
          _imageFile!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    } else {
      // Priority 5: Empty state
      child = Column(
        key: const ValueKey('empty'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.auto_awesome, size: 40, color: Color(0xFF2667FF)),
          SizedBox(height: 12),
          Text(
            'Your remixes appear here',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Add a selfie and set your preferences below to start generating new variants.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _isLoadingImage ? null : _showImageSourceSelection,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(
          minHeight: 280,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isLoadingImage
              ? const Center(
                  key: ValueKey('loading'),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF2667FF),
                    ),
                  ),
                )
              : child,
        ),
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    // Always show thumbnail strip when generating or has results
    if (!_isGenerating && _generatedPaths.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _variantsTotal,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final hasImage = index < _generatedPaths.length;
          final isSelected = index == _selectedPreviewIndex;
          
          if (hasImage) {
            // Show actual generated image
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPreviewIndex = index;
                });
              },
              child: Container(
                width: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF2667FF) : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: PrivateImage(
                    storagePath: _generatedPaths[index],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            );
          } else {
            // Show placeholder for pending variant
            return Container(
              width: 72,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 2,
                ),
              ),
              child: Center(
                child: _isGenerating && index == _generatedPaths.length
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF2667FF),
                        ),
                      )
                    : Icon(
                        Icons.image_outlined,
                        color: Colors.grey.shade400,
                        size: 28,
                      ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildSceneSelector() {
    final selectedScene = _scenes.firstWhere(
      (s) => s['id'] == _selectedSceneId,
      orElse: () => _scenes.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Scene',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ),
        GestureDetector(
          onTap: _showScenePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  selectedScene['icon']!,
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selectedScene['label']!,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.black45,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showScenePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  const Text(
                    'Choose Scene',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scene list grouped by category
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _buildGroupedScenes(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedScenes() {
    final categories = <String, List<Map<String, String>>>{};
    
    // Group scenes by category
    for (final scene in _scenes) {
      final category = scene['category'] ?? 'Other';
      categories.putIfAbsent(category, () => []);
      categories[category]!.add(scene);
    }

    final widgets = <Widget>[];
    final categoryOrder = ['Popular', 'Nature', 'Urban', 'Landmarks', 'Activities', 'Indoor', 'Seasonal', 'Creative'];

    for (final categoryName in categoryOrder) {
      if (!categories.containsKey(categoryName)) continue;
      
      final scenes = categories[categoryName]!;
      
      // Category header
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            categoryName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );

      // Scene items in this category
      for (final scene in scenes) {
        final isSelected = scene['id'] == _selectedSceneId;
        widgets.add(
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2667FF).withOpacity(0.1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  scene['icon']!,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            title: Text(
              scene['label']!,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? const Color(0xFF2667FF) : Colors.black87,
              ),
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Color(0xFF2667FF), size: 22)
                : null,
            onTap: () {
              setState(() => _selectedSceneId = scene['id']!);
              Navigator.pop(context);
            },
          ),
        );
      }
    }

    return widgets;
  }

  Widget _buildOptionsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildDropdown(
            _selectedShotType,
            _shotTypes,
            (v) => setState(() => _selectedShotType = v!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDropdown(
            _selectedTime,
            _times,
            (v) => setState(() => _selectedTime = v!),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        elevation: 2,
        dropdownColor: Colors.white,
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down,
            color: Colors.black45, size: 20),
        style: const TextStyle(color: Colors.black87, fontSize: 14),
        items: items
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(item),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isGenerating ? null : _handleButtonPress,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2667FF),
            disabledBackgroundColor:
                const Color(0xFF2667FF).withOpacity(0.6),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _generationComplete ? Icons.refresh : Icons.auto_awesome,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _isGenerating
                    ? 'Generating...'
                    : _generationComplete
                        ? 'Generate Another Remix'
                        : 'Generate Remix',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
