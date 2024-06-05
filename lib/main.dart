import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:motion_sensors/motion_sensors.dart';
import 'package:simple_shadow/simple_shadow.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, degrees;

late List<CameraDescription> _cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    Key? key,
  }) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late CameraController cameraController;
  bool _hasPermissions = false;
  CompassEvent? _lastRead;
  DateTime? _lastReadAt;

  double turns = 0;
  double prevValue = 0;

  Vector3 _absoluteOrientation = Vector3.zero();
  double headingForCameraMode = 0;

  @override
  void initState() {
    super.initState();

    /// CAMERA
    cameraController = CameraController(_cameras[0], ResolutionPreset.max);
    cameraController.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            print('User denied camera access.');
            break;
          default:
            print('Handle other errors.');
            break;
        }
      }
    });

    /// SENSORS
    motionSensors.absoluteOrientation.listen((AbsoluteOrientationEvent event) {
      setState(() {
        _absoluteOrientation.setValues(event.yaw, event.pitch, event.roll);
      });
    });

    FlutterCompass.events?.listen((event) {
      // headingForCameraMode = event.headingForCameraMode ?? 0;
      headingForCameraMode = event.headingForCameraMode ?? 0;
    });

    _fetchPermissionStatus();
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  _max(a, b) => a >= b ? a : b;

  _round(a) => (a * 100).toInt().toDouble() / 100;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Flutter Compass'),
        ),
        body: Builder(builder: (context) {
          if (_hasPermissions) {
            return Column(
              children: <Widget>[
                // _buildManualReader(),
                Expanded(child: _buildCompass()),
              ],
            );
          } else {
            return _buildPermissionSheet();
          }
        }),
      ),
    );
  }

  Widget _buildManualReader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: <Widget>[
          ElevatedButton(
            child: Text('Read Value'),
            onPressed: () async {
              final CompassEvent tmp = await FlutterCompass.events!.first;
              setState(() {
                _lastRead = tmp;
                _lastReadAt = DateTime.now();
              });
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '$_lastRead',
                    style: Theme.of(context).textTheme.caption,
                  ),
                  Text(
                    '$_lastReadAt',
                    style: Theme.of(context).textTheme.caption,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompass() {
    int sourceDigits = 0;
    double reduceFactor = 6.0;
    var source = _absoluteOrientation;
    double x = double.parse(degrees(source.z).toStringAsFixed(sourceDigits));
    double y = double.parse(degrees(source.y).toStringAsFixed(sourceDigits));
    double angle =
        double.parse(degrees(source.x).toStringAsFixed(sourceDigits));

    angle = _round(angle);
    x = _round(x);
    y = _round(y);

    x /= reduceFactor;
    y /= reduceFactor;
    double distance = _max(x.abs(), y.abs());

    // const double angleMax = 80;
    // double degreesX = degrees(source.y);
    // double degreesY = degrees(source.z);
    // double angleX = degreesX <= angleMax ? degreesX : angleMax;
    // double angleY = degreesY <= angleMax ? degreesY : angleMax;

    Alignment compassAlignment = Alignment.center;

    Widget cameraWdt = Container();
    double xAngle = degrees(_absoluteOrientation.x);
    if (cameraController.value.isInitialized) {
      double yAngle = degrees(_absoluteOrientation.y);
      const double yAngleTop = 70.0;
      const double yAngleBottom = 50.0;

      if(yAngle >= yAngleBottom) {
        compassAlignment = Alignment.bottomCenter;
        // xAngle = degrees(_absoluteOrientation.z);
        xAngle = headingForCameraMode;
      }
      double opacity = yAngle < yAngleBottom ? 0 : yAngle >= yAngleTop ? 1 : yAngle/yAngleTop;
      cameraWdt = AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 250),
        child: CameraPreview(cameraController),
      );
    }

    // direction = direction < 0 ? (360 + direction) : direction;
    double direction = xAngle;
    print('direction: "$direction", x: "${degrees(_absoluteOrientation.x)}", z: "${degrees(_absoluteOrientation.z)}", z2: $headingForCameraMode');

    double diff = direction - prevValue;
    if (diff.abs() > 180) {
      if (prevValue > direction) {
        diff = 360 - (direction - prevValue).abs();
      } else {
        diff = 360 - (prevValue - direction).abs();
        diff = diff * -1;
      }
    }
    turns += (diff / 360);
    prevValue = direction;

    return Stack(
      // alignment: Alignment.center,
      children: [
        cameraWdt,
        /// X,Y,Z VALUES
        Positioned(
          top: 0.0,
          left: 0.0,
          right: 0.0,
          child: Container(
            color: Colors.white54,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('x: ${degrees(_absoluteOrientation.x).toStringAsFixed(4)}'),
                      Text('x2: ${headingForCameraMode.toStringAsFixed(4)}'),
                    ],
                  ),
                  Text(
                      'y: ${degrees(_absoluteOrientation.y).toStringAsFixed(4)}'),
                  Text(
                      'z: ${degrees(_absoluteOrientation.z).toStringAsFixed(4)}'),
                ],
              ),
            ),
          ),
        ),

        /// COMPASS
        AnimatedAlign(
          alignment: compassAlignment,
          duration: const Duration(milliseconds: 250),
          child: Stack(
            alignment: Alignment.center,
            children: [
              /// COMPASS BACKGROUND
              Padding(
                padding: const EdgeInsets.only(top: 19.0, left: 16.0),
                child: SimpleShadow(
                  color: Colors.black,
                  offset: Offset(x, y),
                  opacity: 0.3,
                  sigma: distance / 3,
                  child: Image.asset('assets/rk_compass.png'),
                ),
              ),

              /// COMPASS NEEDLE
              AnimatedRotation(
                turns: turns,
                // turns: 0,
                // turns: 0.25,
                duration: const Duration(milliseconds: 250),
                child: Image.asset('assets/needle2.png'),
                // child: Image.asset('assets/compass.jpg'),
              ),
            ],
          ),
        ),
      ],
    );

    // return StreamBuilder<CompassEvent>(
    //   stream: FlutterCompass.events,
    //   builder: (context, snapshot) {
    //     if (snapshot.hasError) {
    //       return Text('Error reading heading: ${snapshot.error}');
    //     }
    //
    //     if (snapshot.connectionState == ConnectionState.waiting) {
    //       return const Center(
    //         child: CircularProgressIndicator(),
    //       );
    //     }
    //
    //     double? direction = snapshot.data!.heading;
    //
    //     // if direction is null, then device does not support this sensor
    //     // show error message
    //     if (direction == null) {
    //       return const Center(
    //         child: Text("Device does not have sensors !"),
    //       );
    //     }
    //     // print('direction: $direction');
    //
    //
    //
    //     // return Material(
    //     //   shape: CircleBorder(),
    //     //   clipBehavior: Clip.antiAlias,
    //     //   elevation: 4.0,
    //     //   child: Container(
    //     //     padding: EdgeInsets.all(16.0),
    //     //     alignment: Alignment.center,
    //     //     decoration: BoxDecoration(
    //     //       shape: BoxShape.circle,
    //     //     ),
    //     //     // child: Transform.rotate(
    //     //     //   angle: (direction * (math.pi / 180) * -1),
    //     //     //   child: Image.asset('assets/compass.jpg'),
    //     //     // ),
    //     //     child: AnimatedRotation(
    //     //       turns: turns,
    //     //       duration: const Duration(milliseconds: 250),
    //     //       child: Image.asset('assets/rk_compass.png'),
    //     //       // child: Image.asset('assets/compass.jpg'),
    //     //     ),
    //     //   ),
    //     // );
    //   },
    // );
  }

  Widget _buildPermissionSheet() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Location Permission Required'),
          ElevatedButton(
            child: Text('Request Permissions'),
            onPressed: () {
              Permission.locationWhenInUse.request().then((ignored) {
                _fetchPermissionStatus();
              });
            },
          ),
          SizedBox(height: 16),
          ElevatedButton(
            child: Text('Open App Settings'),
            onPressed: () {
              openAppSettings().then((opened) {
                //
              });
            },
          )
        ],
      ),
    );
  }

  void _fetchPermissionStatus() {
    Permission.locationWhenInUse.status.then((status) {
      if (mounted) {
        setState(() => _hasPermissions = status == PermissionStatus.granted);
      }
    });
  }
}
