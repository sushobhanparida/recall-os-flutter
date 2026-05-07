import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as p;
import '../theme/colors.dart';

enum CropResult { success, noSubjectDetected, cancelled, failed }

class CropService {
  /// Detects the most prominent object via ML Kit and crops the image to it
  /// (with 5% padding). Overwrites the file at [filePath].
  Future<CropResult> smartCrop(String filePath) async {
    final detector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: false,
        multipleObjects: true,
      ),
    );
    try {
      final inputImage = InputImage.fromFile(File(filePath));
      final objects = await detector.processImage(inputImage);
      if (objects.isEmpty) return CropResult.noSubjectDetected;

      // Pick the largest detected object by area.
      objects.sort((a, b) {
        final areaA = a.boundingBox.width * a.boundingBox.height;
        final areaB = b.boundingBox.width * b.boundingBox.height;
        return areaB.compareTo(areaA);
      });
      final box = objects.first.boundingBox;

      final bytes = await File(filePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return CropResult.failed;

      // 5% padding around the detected object.
      const pad = 0.05;
      final padX = box.width * pad;
      final padY = box.height * pad;
      final left = (box.left - padX).clamp(0, decoded.width.toDouble()).toInt();
      final top = (box.top - padY).clamp(0, decoded.height.toDouble()).toInt();
      final right =
          (box.right + padX).clamp(0, decoded.width.toDouble()).toInt();
      final bottom =
          (box.bottom + padY).clamp(0, decoded.height.toDouble()).toInt();

      final width = right - left;
      final height = bottom - top;
      if (width <= 0 || height <= 0) return CropResult.failed;

      final cropped = img.copyCrop(
        decoded,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      final encoded = _encode(cropped, filePath);
      await File(filePath).writeAsBytes(encoded);
      return CropResult.success;
    } catch (_) {
      return CropResult.failed;
    } finally {
      await detector.close();
    }
  }

  /// Opens the interactive crop UI. Overwrites the file at [filePath] on success.
  Future<CropResult> manualCrop(String filePath) async {
    try {
      final result = await ImageCropper().cropImage(
        sourcePath: filePath,
        compressFormat: ImageCompressFormat.png,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop',
            toolbarColor: AppColors.bgBase,
            toolbarWidgetColor: AppColors.textPrimary,
            statusBarColor: AppColors.bgBase,
            backgroundColor: AppColors.bgBase,
            activeControlsWidgetColor: AppColors.accent,
            cropFrameColor: AppColors.textPrimary,
            cropGridColor: AppColors.borderSubtle.withValues(alpha: 0.33),
            hideBottomControls: false,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop',
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
          ),
        ],
      );
      if (result == null) return CropResult.cancelled;

      final bytes = await File(result.path).readAsBytes();
      await File(filePath).writeAsBytes(bytes);
      return CropResult.success;
    } catch (_) {
      return CropResult.failed;
    }
  }

  Uint8List _encode(img.Image image, String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.jpg' || ext == '.jpeg') {
      return Uint8List.fromList(img.encodeJpg(image, quality: 92));
    }
    return Uint8List.fromList(img.encodePng(image));
  }
}
