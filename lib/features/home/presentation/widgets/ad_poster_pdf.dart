import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Renders the first page of a PDF asset as a poster with fixed decode size
/// for low-RAM TV. Document and page are closed in dispose.
class AdPosterPdf extends StatefulWidget {
  const AdPosterPdf({
    super.key,
    required this.assetPath,
    required this.width,
    required this.height,
    required this.cacheWidth,
    required this.cacheHeight,
    this.fit = BoxFit.cover,
  });

  final String assetPath;
  final double width;
  final double height;
  final int cacheWidth;
  final int cacheHeight;
  final BoxFit fit;

  @override
  State<AdPosterPdf> createState() => _AdPosterPdfState();
}

class _AdPosterPdfState extends State<AdPosterPdf> {
  PdfDocument? _document;
  PdfPage? _page;
  Uint8List? _imageBytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final PdfDocument document = await PdfDocument.openAsset(widget.assetPath);
      if (!mounted) {
        document.close();
        return;
      }
      _document = document;
      final PdfPage page = await document.getPage(1);
      _page = page;
      final PdfPageImage? image = await page.render(
        width: widget.cacheWidth.toDouble(),
        height: widget.cacheHeight.toDouble(),
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#ffffff',
      );
      if (!mounted) {
        page.close();
        document.close();
        return;
      }
      if (image != null) {
        setState(() {
          _imageBytes = image.bytes;
        });
      } else {
        setState(() => _error = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _page?.close();
    _document?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(
            child: Icon(
              Icons.picture_as_pdf_outlined,
              color: Colors.white54,
              size: 48,
            ),
          ),
        ),
      );
    }
    if (_imageBytes == null) {
      return RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: Image.memory(
        _imageBytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
      ),
    );
  }
}
