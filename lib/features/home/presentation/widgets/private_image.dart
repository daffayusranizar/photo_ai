import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PrivateImage extends StatefulWidget {
  final String storagePath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const PrivateImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<PrivateImage> createState() => _PrivateImageState();
}

class _PrivateImageState extends State<PrivateImage> {
  Future<String>? _urlFuture;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  @override
  void didUpdateWidget(PrivateImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _loadUrl();
    }
  }

  void _loadUrl() {
    _urlFuture = FirebaseStorage.instance.ref(widget.storagePath).getDownloadURL();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.placeholder?.call(context, widget.storagePath) ??
              Container(
                width: widget.width,
                height: widget.height,
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return widget.errorWidget?.call(context, widget.storagePath, snapshot.error) ??
              Container(
                width: widget.width,
                height: widget.height,
                color: Colors.grey[200],
                child: const Icon(Icons.error_outline, color: Colors.grey),
              );
        }

        return CachedNetworkImage(
          imageUrl: snapshot.data!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          placeholder: (context, url) =>
              widget.placeholder?.call(context, url) ??
              Container(
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          errorWidget: (context, url, error) =>
              widget.errorWidget?.call(context, url, error) ??
              Container(
                color: Colors.grey[200],
                child: const Icon(Icons.error_outline, color: Colors.grey),
              ),
        );
      },
    );
  }
}
