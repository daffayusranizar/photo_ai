import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  final TextEditingController _placeController = TextEditingController();
  String _selectedShotType = 'Fullbody';
  String _selectedTime = 'Sunset';

  bool _isGenerating = false;
  bool _isLoadingImage = false;
  bool _generationComplete = false;
  List<String> _generatedUrls = [];
  final ImagePicker _picker = ImagePicker();
  StreamSubscription? _generationSubscription;
  String? _currentPhotoId;

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
    _placeController.text = '';
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
        _generatedUrls.clear();
        _generationComplete = false;
        _currentPhotoId = null;
        _selectedPreviewIndex = 0;
      });
    }
  }

  Future<void> _generateScenes() async {
    if (_placeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a place')),
      );
      return;
    }

    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a selfie first')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedUrls.clear();
      _generationComplete = false;
      _selectedPreviewIndex = 0;
    });

    try {
      final uploadUseCase = sl<UploadPhoto>();

      final result = await uploadUseCase(
        _imageFile!,
        place: _placeController.text.trim(),
        shotType: _selectedShotType.toLowerCase(),
        timeOfDay: _selectedTime.toLowerCase(),
      );

      result.fold(
        (failure) {
          if (mounted) {
            setState(() => _isGenerating = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload failed: $failure')),
            );
          }
        },
        (_) async {
          if (!mounted) return;

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
        setState(() => _isGenerating = false);
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

        if (data != null && data['generatedUrls'] != null) {
          final urls = List<String>.from(data['generatedUrls'] as List);

          if (urls.isNotEmpty) {
            if (mounted) {
              setState(() {
                _generatedUrls = urls;
                _isGenerating = false;
                _generationComplete = true;
                _selectedPreviewIndex = 0;
              });
              _precacheGeneratedImages(urls);
            }

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

  void _precacheGeneratedImages(List<String> urls) {
    for (final url in urls) {
      precacheImage(NetworkImage(url), context);
    }
  }

  void _handleButtonPress() {
    if (_generationComplete) {
      _resetGenerationData();
    }
    _generateScenes();
  }

  @override
  void dispose() {
    _placeController.dispose();
    _generationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      resizeToAvoidBottomInset: true, // Important for keyboard handling
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
                  _buildLocationDisplay(),
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
    final bool hasResults = _generatedUrls.isNotEmpty;
    final bool hasSelfie = _imageFile != null;

    Widget child;

    if (_isGenerating) {
      child = Column(
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
            'Your remix will appear here',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Generating new variants...',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      );
    } else if (hasResults) {
      final imageUrl = _generatedUrls[
          _selectedPreviewIndex.clamp(0, _generatedUrls.length - 1)];
      child = ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    } else if (hasSelfie) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.file(
          _imageFile!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    } else {
      child = Column(
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
          minHeight: 280, // Minimum height to prevent card from being too small
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
          duration: const Duration(milliseconds: 200),
          child: _isLoadingImage
              ? const Center(
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
    if (_generatedUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _generatedUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isSelected = index == _selectedPreviewIndex;
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
                  color:
                      isSelected ? const Color(0xFF2667FF) : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: _generatedUrls[index],
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocationDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          const Icon(Icons.location_on_outlined,
              color: Colors.black54, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _placeController,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Place',
                hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
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
