import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:logging/logging.dart';
import 'package:simple_frame_app/rx/photo.dart';
import 'package:simple_frame_app/tx/camera_settings.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/plain_text.dart';

import 'helper/image_classification_helper.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {

  // Classification
  late ImageClassificationHelper _imageClassificationHelper;
  String _top3 = '';

  // the image and metadata to show
  Image? _image;
  ImageMetadata? _imageMeta;
  final Stopwatch _stopwatch = Stopwatch();

  // camera settings
  int _qualityIndex = 0;
  final List<double> _qualityValues = [10, 25, 50, 100];
  int _meteringIndex = 2;
  final List<String> _meteringValues = ['SPOT', 'CENTER_WEIGHTED', 'AVERAGE'];
  int _autoExpGainTimes = 1; // val >= 0; number of times auto exposure and gain algorithm will be run every 100ms
  double _exposure = 0.18; // 0.0 <= val <= 1.0
  double _exposureSpeed = 0.5;  // 0.0 <= val <= 1.0
  int _shutterLimit = 800; // 4 < val < 16383
  int _analogGainLimit = 248;     // 0 <= val <= 248
  double _whiteBalanceSpeed = 0.5;  // 0.0 <= val <= 1.0

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    _imageClassificationHelper = ImageClassificationHelper();
    _imageClassificationHelper.initHelper();
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    // keep looping, taking photos and displaying, until user clicks cancel
    while (currentState == ApplicationState.running) {

      try {
        // the image data as a list of bytes that accumulates with each packet
        ImageMetadata meta = ImageMetadata(_qualityValues[_qualityIndex].toInt(), _autoExpGainTimes, _meteringValues[_meteringIndex], _exposure, _exposureSpeed, _shutterLimit, _analogGainLimit, _whiteBalanceSpeed);

        // send the lua command to request a photo from the Frame
        _stopwatch.reset();
        _stopwatch.start();
        await frame!.sendMessage(TxCameraSettings(
          msgCode: 0x0d,
          qualityIndex: _qualityIndex,
          autoExpGainTimes: _autoExpGainTimes,
          meteringIndex: _meteringIndex,
          exposure: _exposure,
          exposureSpeed: _exposureSpeed,
          shutterLimit: _shutterLimit,
          analogGainLimit: _analogGainLimit,
          whiteBalanceSpeed: _whiteBalanceSpeed,
        ));

        // synchronously await the image response
        Uint8List imageData = await RxPhoto(qualityLevel: _qualityValues[_qualityIndex].toInt()).attach(frame!.dataResponse).first;

        // received a whole-image Uint8List with jpeg header and footer included
        _stopwatch.stop();
        _log.fine('Image file size in bytes: ${imageData.length}, elapsedMs: ${_stopwatch.elapsedMilliseconds}');

        try {
          // Decode image using package:image/image.dart (https://pub.dev/packages/image)
          image_lib.Image? im = image_lib.decodeJpg(imageData);

          if (im != null) {
            // Frame camera is rotated 90 degrees clockwise, so make it upright for image processing
            im = image_lib.copyRotate(im, angle: 270);

            // Perform vision processing pipeline
            // send image to classifier, produce some candidate classes (https://pub.dev/packages/tflite_flutter)
            Map<String, double> classification = await _imageClassificationHelper.inferenceImage(im);

            // classification map is unordered and can be long, sort it and pick the best 3 here
            _top3 = (classification.entries.toList()
                      ..sort((a, b) => a.value.compareTo(b.value),))
                      .reversed.take(3).toList().fold<String>('', (previousValue, element) => '$previousValue\n${element.key}: ${element.value.toStringAsFixed(2)}').trim();

            _log.fine('Classification result: $_top3');

            // Frame display
            await frame!.sendMessage(TxPlainText(msgCode: 0x0a, text: _top3));

            // UI display
            Image imWidget = Image.memory(image_lib.encodeJpg(im), gaplessPlayback: true,);

            // add the size and elapsed time to the image metadata widget
            meta.size = imageData.length;
            meta.elapsedTimeMs = _stopwatch.elapsedMilliseconds;

            setState(() {
              _image = imWidget;
              _imageMeta = meta;
            });

          }

        } catch (e) {
          _log.severe('Error converting bytes to image: $e');
        }

      } catch (e) {
        _log.severe('Error executing application: $e');
      }
    }
  }

  /// cancel the current photo
  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision - Classification',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Vision - Classification"),
          actions: [getBatteryWidget()]
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              const DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.blue,
                ),
                child: Text('Camera Settings',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
              ),
              ListTile(
                title: const Text('Quality'),
                subtitle: Slider(
                  value: _qualityIndex.toDouble(),
                  min: 0,
                  max: _qualityValues.length - 1,
                  divisions: _qualityValues.length - 1,
                  label: _qualityValues[_qualityIndex].toString(),
                  onChanged: (value) {
                    setState(() {
                      _qualityIndex = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Auto Exposure/Gain Runs'),
                subtitle: Slider(
                  value: _autoExpGainTimes.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _autoExpGainTimes.toInt().toString(),
                  onChanged: (value) {
                    setState(() {
                      _autoExpGainTimes = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Metering'),
                subtitle: DropdownButton<int>(
                  value: _meteringIndex,
                  onChanged: (int? newValue) {
                    setState(() {
                      _meteringIndex = newValue!;
                    });
                  },
                  items: _meteringValues
                      .map<DropdownMenuItem<int>>((String value) {
                    return DropdownMenuItem<int>(
                      value: _meteringValues.indexOf(value),
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ),
              ListTile(
                title: const Text('Exposure'),
                subtitle: Slider(
                  value: _exposure,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: _exposure.toString(),
                  onChanged: (value) {
                    setState(() {
                      _exposure = value;
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Exposure Speed'),
                subtitle: Slider(
                  value: _exposureSpeed,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: _exposureSpeed.toString(),
                  onChanged: (value) {
                    setState(() {
                      _exposureSpeed = value;
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Shutter Limit'),
                subtitle: Slider(
                  value: _shutterLimit.toDouble(),
                  min: 4,
                  max: 16383,
                  divisions: 10,
                  label: _shutterLimit.toStringAsFixed(0),
                  onChanged: (value) {
                    setState(() {
                      _shutterLimit = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Analog Gain Limit'),
                subtitle: Slider(
                  value: _analogGainLimit.toDouble(),
                  min: 0,
                  max: 248,
                  divisions: 8,
                  label: _analogGainLimit.toStringAsFixed(0),
                  onChanged: (value) {
                    setState(() {
                      _analogGainLimit = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('White Balance Speed'),
                subtitle: Slider(
                  value: _whiteBalanceSpeed,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: _whiteBalanceSpeed.toString(),
                  onChanged: (value) {
                    setState(() {
                      _whiteBalanceSpeed = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (_image != null) _image!,
                  const Divider(),
                  if (_imageMeta != null) _imageMeta!,
                  const Divider(),
                  Text(_top3),
                ],
              )
            ),
            const Divider(),
          ],
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.camera_alt), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}

class ImageMetadata extends StatelessWidget {
  final int quality;
  final int exposureRuns;
  final String metering;
  final double exposure;
  final double exposureSpeed;
  final int shutterLimit;
  final int analogGainLimit;
  final double whiteBalanceSpeed;

  ImageMetadata(this.quality, this.exposureRuns, this.metering, this.exposure, this.exposureSpeed, this.shutterLimit, this.analogGainLimit, this.whiteBalanceSpeed, {super.key});

  late int size;
  late int elapsedTimeMs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Quality: $quality\nExposureRuns: $exposureRuns\nMetering: $metering\nExposure: $exposure'),
        const Spacer(),
        Text('ExposureSpeed: $exposureSpeed\nShutterLim: $shutterLimit\nAnalogGainLim: $analogGainLimit\nWBSpeed: $whiteBalanceSpeed'),
        const Spacer(),
        Text('Size: ${(size/1024).toStringAsFixed(1)} kb\nTime: $elapsedTimeMs ms'),
      ],
    );
  }
}