import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/photo.dart';
import '../../domain/usecases/upload_photo.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';  // ADD THIS PACKAGE
import 'history_page.dart';
import 'dart:async';


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
  Set<int> _selectedVariants = {};
  final ImagePicker _picker = ImagePicker();
  StreamSubscription? _generationSubscription;
  String? _currentPhotoId;

  static const List<String> _shotTypes = ['Fullbody', 'Half', 'Close-up', 'Landscape'];
  static const List<String> _times = ['Morning', 'Sunrise', 'Noon', 'Afternoon', 'Sunset', 'Night'];

  @override
  void initState() {
    super.initState();
    _imageFile = widget.imageFile;
    _placeController.text = 'Jam Gadang, Indonesia';
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
            const SnackBar(content: Text('Image too large. Please select a smaller image.')),
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
      backgroundColor: const Color(0xFF1A1F2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
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
        _selectedVariants.clear();
        _generationComplete = false;
        _currentPhotoId = null;
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
      _selectedVariants.clear();
      _generationComplete = false;
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
                  content: Text('Generating 4 variants... This may take 30-60 seconds'),
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
          
          if (urls.isNotEmpty && urls.length >= 3) {
            if (mounted) {
              setState(() {
                _generatedUrls = urls;
                _isGenerating = false;
                _generationComplete = true;
              });
              
              // Precache images for faster display
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

  // NEW: Precache images for instant display
  void _precacheGeneratedImages(List<String> urls) {
    for (final url in urls) {
      precacheImage(NetworkImage(url), context);
    }
  }

  void _handleButtonPress() {
    if (_generationComplete) {
      _resetGenerationData();
    } else {
      _generateScenes();
    }
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
      backgroundColor: const Color(0xFF1A1F2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F2E),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Remix', 
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined, color: Colors.white70, size: 22),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Center(child: _buildImagePreview()),
              const SizedBox(height: 20),
              _buildLocationDisplay(),
              const SizedBox(height: 16),
              _buildOptionsRow(),
              const SizedBox(height: 28),
              
              if (_generatedUrls.isNotEmpty || _isGenerating)
                _buildResultsSection(),
              
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomButton(),
    );
  }

  Widget _buildImagePreview() {
    return GestureDetector(
      onTap: _isLoadingImage ? null : _showImageSourceSelection,
      child: Container(
        width: 140,
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF252A38),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _isLoadingImage
              ? const Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      color: Colors.blue,
                      strokeWidth: 3,
                    ),
                  ),
                )
              : _imageFile != null
                  ? Image.file(
                      _imageFile!,
                      fit: BoxFit.cover,
                      cacheWidth: 280,
                      cacheHeight: 320,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(Icons.error_outline, color: Colors.red),
                        );
                      },
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: Colors.blue, size: 36),
                        SizedBox(height: 8),
                        Text('Upload Selfie', 
                          style: TextStyle(color: Colors.blue, fontSize: 13)),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildLocationDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF252A38),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _placeController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter location',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
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
        Expanded(child: _buildDropdown(_selectedShotType, _shotTypes, (v) {
          setState(() => _selectedShotType = v!);
        })),
        const SizedBox(width: 12),
        Expanded(child: _buildDropdown(_selectedTime, _times, (v) {
          setState(() => _selectedTime = v!);
        })),
      ],
    );
  }

  Widget _buildDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A38),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: const Color(0xFF252A38),
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 20),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(item),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildResultsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isGenerating 
              ? 'Generating AI variants...'
              : 'Here are 4 AI-generated variants. Select one or more to save:',
          style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _isGenerating ? 4 : _generatedUrls.length,
          itemBuilder: (context, index) {
            if (_isGenerating) {
              return _buildLoadingPlaceholder();
            }
            return _buildVariantItem(index);
          },
        ),
      ],
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252A38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: Colors.blue,
          strokeWidth: 2.5,
        ),
      ),
    );
  }

  Widget _buildVariantItem(int index) {
    final isSelected = _selectedVariants.contains(index);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedVariants.remove(index);
          } else {
            _selectedVariants.add(index);
          }
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B9EFF) : Colors.transparent,
            width: 3,
          ),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(  // CHANGED: Use CachedNetworkImage
                imageUrl: _generatedUrls[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                memCacheWidth: 400,  // Reduced memory cache
                placeholder: (context, url) => Container(
                  color: const Color(0xFF252A38),
                  child: const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: Colors.blue,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFF252A38),
                  child: const Center(
                    child: Icon(Icons.error_outline, color: Colors.red, size: 32),
                  ),
                ),
                fadeInDuration: const Duration(milliseconds: 200),  // Smooth fade
                fadeOutDuration: const Duration(milliseconds: 100),
              ),
            ),
            if (isSelected)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF3B9EFF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isGenerating ? null : _handleButtonPress,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B9EFF),
            disabledBackgroundColor: const Color(0xFF3B9EFF).withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _generationComplete ? Icons.refresh : Icons.auto_awesome,
                color: Colors.white, 
                size: 20
              ),
              const SizedBox(width: 10),
              Text(
                _isGenerating 
                    ? 'Generating...' 
                    : _generationComplete 
                        ? 'Generate Another Scenes'
                        : 'Generate Scenes',
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
