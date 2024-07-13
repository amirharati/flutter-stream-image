import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const CameraApp());
}

class CameraApp extends StatelessWidget {
  const CameraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CameraExample(),
    );
  }
}

class CameraExample extends StatefulWidget {
  const CameraExample({Key? key}) : super(key: key);

  @override
  State<CameraExample> createState() => _CameraExampleState();
}

class _CameraExampleState extends State<CameraExample>
    with WidgetsBindingObserver {
  CameraController? controller;
  bool _isCameraInitialized = false;

  final StreamController<Uint8List> _streamController =
      StreamController<Uint8List>();

  static const platform = MethodChannel('com.benamorn.liveness');

  DateTime _lastProcessedTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    onNewCameraSelected(_cameras[0]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamController.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      onNewCameraSelected(cameraController.description);
    }
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    final previousCameraController = controller;
    final CameraController cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium, // Reduced from high to medium
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await previousCameraController?.dispose();

    if (mounted) {
      setState(() {
        controller = cameraController;
      });
    }

    cameraController.addListener(() {
      if (mounted) setState(() {});
    });

    try {
      await cameraController.initialize();
      await cameraController.startImageStream(_processCameraImage);
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
    }

    if (mounted) {
      setState(() {
        _isCameraInitialized = controller!.value.isInitialized;
      });
    }
  }

  void _processCameraImage(CameraImage image) async {
    // Simple throttling: process at most one frame every 100ms
    if (DateTime.now().difference(_lastProcessedTime).inMilliseconds < 200) {
      return;
    }
    _lastProcessedTime = DateTime.now();

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      print(
          'Image size: ${bytes.length}, Width: ${image.width}, Height: ${image.height}');

      final imageData =
          await platform.invokeMethod<Uint8List>("checkLiveness", {
        'platforms': image.planes.map((plane) => plane.bytes).toList(),
        'height': image.height,
        'width': image.width,
        'strides': image.planes.map((plane) => plane.bytesPerRow).toList()
      });

      if (imageData != null) {
        print('Processed image size: ${imageData.length}');
        _streamController.add(imageData);
      } else {
        print('Processed image is null');
      }
    } catch (e) {
      print('Error processing image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Camera Stream Example")),
      body: _isCameraInitialized
          ? Column(
              children: [
                Expanded(
                  child: StreamBuilder<Uint8List>(
                    stream: _streamController.stream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Image.memory(
                        snapshot.data!,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                      );
                    },
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
