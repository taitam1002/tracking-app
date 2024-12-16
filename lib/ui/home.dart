import 'dart:async';
import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'login.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Hive
  await Hive.initFlutter();

  // Mở các hộp cần thiết
  await Hive.openBox("login");
  await Hive.openBox("accounts");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ứng dụng Giám Sát Thiết Bị',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: FutureBuilder(
        future: Hive.openBox("login"),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            bool isLoggedIn =
                Hive.box("login").get("loginStatus", defaultValue: false);
            return isLoggedIn ? Home() : Login();
          } else {
            return Scaffold(
              body: Center(
                  child:
                      CircularProgressIndicator()), // Hiển thị loading indicator
            );
          }
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Lớp Alert để lưu trữ thông tin cảnh báo
class Alert {
  final String mac;
  final DateTime time;
  final String message;

  Alert({required this.mac, required this.time, required this.message});
}

class Home extends StatefulWidget {
  Home({super.key});

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final Box _boxLogin = Hive.box("login");
  final Box _boxAccounts = Hive.box("accounts"); // Hộp để lưu MAC addresses
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  CircleMarker? _circleMarker;
  double _radius = 20.0; // Bán kính tính bằng mét
  double _currentZoom = 13.0; // Cấp độ zoom hiện tại
  final double baseZoom = 13.0; // Cấp độ zoom cơ bản

  // Thông tin kết nối MQTT
  final String broker = '6c6cbbe4c5f747b89ad5a9319b4deb08.s1.eu.hivemq.cloud';
  final int port = 8883;
  final String username = 'taitam';
  final String password = 'Taitam1002';
  final String topic = 'GPS_MAC';

  // Bản đồ lưu MACs đã nhận và thời gian nhận
  Map<String, DateTime> receivedMacs = {};

  // Bản đồ lưu tọa độ của MACs
  Map<String, LatLng> macCoordinates = {};

  late MqttServerClient mqttClient;

  // Bản đồ quản lý Timer cho mỗi MAC
  Map<String, Timer> _macAlertTimers = {};

  // Danh sách các mục thiết bị được lưu trong trạng thái widget
  List<Map<String, dynamic>> macEntries = [
    {'name': 'Thiết bị 1', 'mac': '', 'status': false, 'color': Colors.red}
  ];

  // Các controller cho các trường Tên và MAC
  List<TextEditingController> nameControllers = [];
  List<TextEditingController> macControllers = [];

  // Danh sách màu cho các thiết bị
  final List<Color> deviceColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
  ];

  // Tập để theo dõi các thiết bị đã bị cảnh báo
  Set<String> devicesWarned = {};

  // Danh sách các cảnh báo hiện tại
  List<Alert> alerts = [];

  // Biến để theo dõi số lượng cảnh báo mới chưa xem
  int newAlertsCount = 0;

  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  Timer? _alertTimer;

  // Thêm biến toàn cục để lưu trữ thời gian cảnh báo gần nhất cho mỗi thiết bị
  Map<String, DateTime> lastAlertTimes = {};

  @override
  void initState() {
    super.initState();
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    _initializeNotifications();
    connectToMQTT();
    loadMacEntries();
    loadAlerts(); // Tải cảnh báo khi khởi tạo
    // Khởi tạo các controller cho mỗi thiết bị
    macEntries.forEach((entry) {
      nameControllers.add(TextEditingController(text: entry['name']));
      macControllers.add(TextEditingController(text: entry['mac']));
    });
    requestNotificationPermission();

    // Bắt đầu Timer để kiểm tra khoảng cách
    _startAlertTimer();
  }

  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // Phương thức trợ giúp để ánh xạ MAC thành tên thiết b
  Map<String, String> get macToNameMap {
    Map<String, String> map = {};
    for (var entry in macEntries) {
      String mac = entry['mac'].toUpperCase();
      String name = entry['name'];
      if (mac.isNotEmpty) {
        map[mac] = name;
      }
    }
    return map;
  }

  // Hàm để tải các mục MAC từ Hive theo người dùng hiện tại
  void loadMacEntries() {
    String userEmail = _boxLogin.get('userEmail',
        defaultValue: 'default_email'); // Lấy email người dùng
    List storedEntries = _boxAccounts.get('${userEmail}_macEntries',
        defaultValue: []); // Sử dụng email làm khóa
    print("Đã tải macEntries cho $userEmail: $storedEntries"); // Debug
    setState(() {
      macEntries = List<Map<String, dynamic>>.from(
          storedEntries.map((entry) => Map<String, dynamic>.from(entry)));
      nameControllers = macEntries
          .map((entry) => TextEditingController(text: entry['name']))
          .toList();
      macControllers = macEntries
          .map((entry) => TextEditingController(text: entry['mac']))
          .toList();
    });
  }

  // Hàm để lưu các mục MAC vào Hive theo người dùng hiện tại và xử lý cảnh báo khi thiết bị bị xóa
  void saveMacEntries() {
    String userEmail = _boxLogin.get('userEmail',
        defaultValue: 'default_email'); // Lấy email người dùng

    // Cập nhật macEntries với các giá trị hiện tại từ các controller
    for (int i = 0; i < macEntries.length; i++) {
      macEntries[i]['name'] = nameControllers[i].text.trim();
      macEntries[i]['mac'] = macControllers[i].text.trim();
      // Đảm bảo mỗi thiết bị có một màu
      if (!macEntries[i].containsKey('color') ||
          macEntries[i]['color'] == null) {
        macEntries[i]['color'] = deviceColors[i % deviceColors.length];
      }
    }

    // Lưu vào Hive dưới khóa cụ thể của người dùng
    _boxAccounts.put(
        '${userEmail}_macEntries', macEntries); // Sử dụng email làm khóa
    print("Đã lưu macEntries cho $userEmail: $macEntries"); // Debug

    // **Mã mới bắt đầu tại đây: Dọn dẹp cảnh báo và Timers cho MACs đã xóa**

    // 1. Lấy tập hợp các MAC hiện tại sau khi lưu
    Set<String> currentMacs = macEntries
        .map((entry) => entry['mac'].toString().toUpperCase())
        .where((mac) => mac.isNotEmpty)
        .toSet();

    // 2. Xác định MACs đã bị xóa (có trong devicesWarned nhưng không có trong currentMacs)
    Set<String> macsToRemove = devicesWarned
        .where((mac) => !currentMacs.contains(mac))
        .cast<String>()
        .toSet();

    // 3. Loại bỏ cảnh báo và hủy Timers cho MACs đã xóa
    for (String mac in macsToRemove) {
      devicesWarned.remove(mac);

      // Hủy và loại bỏ Timer
      _macAlertTimers[mac]?.cancel();
      _macAlertTimers.remove(mac);

      // Loại bỏ khỏi macCoordinates và receivedMacs để ng
      macCoordinates.remove(mac);
      receivedMacs.remove(mac);

      print('Đã loại bỏ MAC khỏi devicesWarned: $mac');
      print('Đã loại bỏ macCoordinates cho MAC: $mac');
      print('Đã loại bỏ receivedMacs cho MAC: $mac');
      // **Không loại bỏ các cảnh báo hiện có**
    }

    // 4. **Không** loại bỏ các cảnh báo hiện có để cho phép xem trong hộp thoại cảnh báo
    // alerts.removeWhere((alert) => !currentMacs.contains(alert.mac)); // Bỏ dòng này

    // 5. Thông báo cho người dùng về việc dọn dẹp nếu có MACs bị xóa
    if (macsToRemove.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cảnh báo đã bị tắt cho các thiết bị bị xóa.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }

    // **Mã mới kết thúc tại đây**
  }

  // Hàm để kết nối đến MQTT
  void connectToMQTT() async {
    mqttClient = MqttServerClient(broker, '');
    mqttClient.port = port;
    mqttClient.secure = true;
    mqttClient.logging(on: true);
    mqttClient.setProtocolV311();
    mqttClient.connectionMessage =
        MqttConnectMessage().authenticateAs(username, password).startClean();

    mqttClient.onConnected = () {
      print('MQTT Client đã kết nối');
    };

    mqttClient.onDisconnected = () {
      print('MQTT Client đã ngắt kết nối');
    };

    mqttClient.onSubscribed = (String topic) {
      print('Đã đăng ký chủ đề: $topic');
    };

    try {
      await mqttClient.connect();
      mqttClient.subscribe(topic, MqttQos.atLeastOnce);
      mqttClient.updates!
          .listen((List<MqttReceivedMessage<MqttMessage>> messages) {
        final MqttPublishMessage message =
            messages[0].payload as MqttPublishMessage;
        final String payload =
            MqttPublishPayload.bytesToStringAsString(message.payload.message)
                .trim();
        print('Đã nhận Payload: $payload');

        // Tách payload thành MAC, latitude và longitude
        List<String> parts = payload.split(',');
        if (parts.length >= 3) {
          String mac = parts[0].trim().toUpperCase();
          double? latitude = double.tryParse(parts[1].trim());
          double? longitude = double.tryParse(parts[2].trim());

          if (mac.isNotEmpty && latitude != null && longitude != null) {
            // Xác thực phạm vi tọa độ
            if (latitude < -90 ||
                latitude > 90 ||
                longitude < -180 ||
                longitude > 180) {
              print('Đã nhận tọa độ không hợp lệ.');
              return;
            }

            print(
                'Đã phân tích MAC: $mac, Latitude: $latitude, Longitude: $longitude');

            setState(() {
              // Chỉ cập nhật nếu MAC vẫn tồn tại trong macEntries
              bool macExists =
                  macEntries.any((entry) => entry['mac'].toUpperCase() == mac);
              if (macExists) {
                receivedMacs[mac] = DateTime.now();
                _checkConnection(mac); // Kiểm tra kết nối

                // Cập nhật tọa độ cho MAC này
                macCoordinates[mac] = LatLng(latitude, longitude);
              } else {
                // Nếu MAC đã bị xóa, không làm gì cả
                print('MAC $mac đã bị xóa khỏi danh sách thiết bị.');
              }
            });

            // Kiểm tra khoảng cách sau khi cập nhật vị trí
            checkDeviceDistances();
          } else {
            print('Định dạng payload không hợp lệ.');
          }
        } else {
          print('Payload không chứa đủ phần.');
        }
      });
    } catch (e) {
      print('Lỗi MQTT: $e');
      mqttClient.disconnect();
    }
  }

  // Hàm để kiểm tra khoảng cách giữa điện thoại và thiết bị
  void checkDeviceDistances() {
    if (_currentLocation == null) return;

    macCoordinates.forEach((mac, coord) {
      double distance = Geolocator.distanceBetween(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        coord.latitude,
        coord.longitude,
      );

      String deviceName = macToNameMap[mac] ?? mac;

      if (distance > _radius) {
        // Nếu thiết bị ra ngoài vùng an toàn
        DateTime now = DateTime.now();
        // Kiểm tra thời gian cảnh báo gần nhất
        if (!lastAlertTimes.containsKey(mac) ||
            now.difference(lastAlertTimes[mac]!).inSeconds >= 15) {
          // Cập nhật thời gian cảnh báo
          lastAlertTimes[mac] = now;

          devicesWarned.add(mac);
          alerts.insert(
              0,
              Alert(
                  mac: mac,
                  time: DateTime.now(),
                  message: 'đã ra khỏi vùng an toàn!')); // Thêm thông điệp
          newAlertsCount += 1;

          // Hiển thị Snackbar với tên thiết bị
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cảnh báo: $deviceName đã ra khỏi vùng an toàn!'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );

          // Gửi thông báo
          _showNotification(
              deviceName, 'đã ra khỏi vùng an toàn!'); // Cập nhật thông báo
        }
      } else {
        // Nếu thiết bị trong vùng an toàn
        if (devicesWarned.contains(mac)) {
          // Xóa thiết bị khỏi danh sách cảnh báo
          devicesWarned.remove(mac);

          // Thêm thông báo vào alerts với thông điệp khác
          alerts.insert(
              0,
              Alert(
                  mac: mac,
                  time: DateTime.now(),
                  message: 'đã trở lại vùng an toàn!')); // Thêm thông điệp
          newAlertsCount =
              max(newAlertsCount - 1, 0); // Giảm số lượng cảnh báo mới

          // Hiển thị Snackbar thông báo thiết bị đã trở lại vùng an toàn
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Thiết bị $deviceName đã trở lại trong vùng an toàn.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );

          // Gửi thông báo
          _showNotification(
              deviceName, 'đã trở lại vùng an toàn!'); // Cập nhật thông báo
        }
      }
    });

    setState(() {}); // Cập nhật UI để hiển thị badge cảnh báo
  }

  Future<void> _showNotification(String deviceName, String message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      // 'your_channel_id', // Thay thế bằng ID kênh của bạn
      'your_channel_name', // Thay thế bằng tên kênh của bạn
      'your_channel_description', // Thay thế bằng mô tả kênh của bạn
      channelDescription:
          'your_channel_description', // Thay thế bằng mô tả kênh của bạn
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Cảnh báo thiết bị',
      '$deviceName $message', // Cập nhật nội dung thông báo
      platformChannelSpecifics,
      payload: 'item x',
    );
  }

  // Hàm để hiển thị hộp thoại nhập MAC
  void _showMacInputDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return MacInputDialog(
          macEntries: macEntries,
          nameControllers: nameControllers,
          macControllers: macControllers,
          receivedMacs: receivedMacs,
          onUpdate: () {
            setState(() {});
            saveMacEntries(); // Lưu thay đổi vào Hive

            // Kiểm tra khoảng cách sau khi cập nhật các mục MAC
            checkDeviceDistances();
          },
          deviceColors: deviceColors,
        );
      },
    );
  }

  // Hàm để hiển thị hộp thoại nhập bán kính
  void _showRadiusInputDialog(BuildContext context) {
    TextEditingController _radiusController =
        TextEditingController(text: _radius.toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Nhập bán kính"),
          content: TextField(
            controller: _radiusController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: "Nhập bán kính (mét)"),
          ),
          actions: [
            ElevatedButton(
              child: Text(
                "Cập nhật",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color.fromARGB(255, 57, 133, 79), // Màu nền nút
              ),
              onPressed: () {
                double newRadius =
                    double.tryParse(_radiusController.text) ?? 20.0;

                // Giới hạn bán kính từ 1m đến 100m
                if (newRadius < 1.0 || newRadius > 100.0) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Bán kính phải nằm trong khoảng từ 1m đến 100m.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                    ),
                  );
                  return; // Không cập nhật nếu không hợp lệ
                }

                setState(() {
                  _radius = newRadius;
                  if (_currentLocation != null) {
                    _circleMarker = CircleMarker(
                      point: _currentLocation!,
                      color: Colors.blue.withOpacity(0.3),
                      borderStrokeWidth: 2,
                      borderColor: Colors.blue,
                      radius: _calculatePixelRadius(
                          _radius, _currentLocation!.latitude, _currentZoom),
                    );
                  }
                });

                // Kiểm tra khoảng cách sau khi cập nhật bán kính
                checkDeviceDistances();

                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Hàm để tính bán kính pixel dựa trên bán kính mét
  double _calculatePixelRadius(
      double radiusInMeters, double latitude, double zoom) {
    // Tính số mét mỗi pixel tại cấp độ zoom và vĩ độ hiện tại
    double metersPerPixel =
        156543.03392 * math.cos(latitude * math.pi / 180) / math.pow(2, zoom);
    // Tính bán kính pixel
    return radiusInMeters / metersPerPixel;
  }

  // Hàm để lấy vị trí hiện tại của điện thoại
  Future<void> _getCurrentLocation() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _currentZoom = 15.0; // Đặt cấp độ zoom ban đầu
        _circleMarker = CircleMarker(
          point: _currentLocation!,
          color: Colors.blue.withOpacity(0.3),
          borderStrokeWidth: 2,
          borderColor: Colors.blue,
          radius:
              _calculatePixelRadius(_radius, position.latitude, _currentZoom),
        );
        _mapController.move(_currentLocation!, _currentZoom);
      });

      // Kiểm tra khoảng cách sau khi cập nhật vị trí điện thoại
      checkDeviceDistances();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  // Hàm để xác thực định dng MAC address
  bool isValidMac(String mac) {
    final RegExp macRegExp =
        RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return macRegExp.hasMatch(mac);
  }

  // Hàm để kiểm tra và cập nhật trạng thái kết nối dựa trên MAC
  void _checkConnection(String mac) {
    // Tạo một bản đồ để đếm số lần xuất hiện của mỗi MAC (không phân biệt chữ hoa chữ thường)
    Map<String, int> macCount = {};
    for (var entry in macEntries) {
      String currentMac = entry['mac'];
      if (currentMac.isNotEmpty) {
        String normalizedMac = currentMac.toUpperCase();
        macCount[normalizedMac] = (macCount[normalizedMac] ?? 0) + 1;
      }
    }

    setState(() {
      for (var entry in macEntries) {
        String currentMac = entry['mac'];
        if (currentMac.isNotEmpty && isValidMac(currentMac)) {
          String normalizedMac = currentMac.toUpperCase();
          bool isDuplicate = macCount[normalizedMac]! > 1;
          bool isReceived = receivedMacs.containsKey(normalizedMac);
          if (isReceived && !isDuplicate) {
            entry['status'] = true;
          } else {
            entry['status'] = false;
            // Loại bỏ tọa độ và marker nếu thiết bị không kết nối
            macCoordinates.remove(normalizedMac);
          }
        } else {
          // MAC không hợp lệ hoặc trống
          entry['status'] = false;
          // Loại bỏ tọa độ và marker nếu thiết bị không kết nối
          macCoordinates.remove(currentMac.toUpperCase());
        }
      }
      saveMacEntries(); // Lưu các thay đổi vào Hive
    });
  }

  // Hàm để hiển thị hộp thoại danh sách cảnh báo
  void _showAlertsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("THÔNG BÁO"),
          content: AlertsPaginatedView(
            alerts: alerts,
            macToNameMap: macToNameMap, // Truyền bản đồ ở đây
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  newAlertsCount = 0; // Đặt lại số lượng cảnh báo mới
                });
              },
              child: Text("Đóng"),
            ),
            // Thêm nút xóa cảnh báo
            ElevatedButton(
              onPressed: () {
                setState(() {
                  alerts.clear(); // Xóa tất cả cảnh báo
                  newAlertsCount = 0; // Đặt lại số lượng cảnh báo mới
                });
                Navigator.of(context).pop(); // Đóng hộp thoại
              },
              child: Text(
                "Xóa tất cả cảnh báo",
                selectionColor: Color.fromARGB(255, 255, 255, 255),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 255, 255, 255), // Màu nền nút xóa
              ),
            ),
          ],
        );
      },
    );
  }

  void _startAlertTimer() {
    _alertTimer = Timer.periodic(Duration(seconds: 15), (timer) {
      checkDeviceDistances(); // Kiểm tra khoảng cách mỗi 15 giây
    });
  }

  @override
  void dispose() {
    _alertTimer?.cancel(); // Hủy Timer khi khng còn sử dụng
    mqttClient.disconnect();
    // Hủy tất cả các Timers
    _macAlertTimers.forEach((key, timer) => timer.cancel());
    _macAlertTimers.clear();
    // Giải phóng controllers
    for (var controller in nameControllers) {
      controller.dispose();
    }
    for (var controller in macControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tạo danh sách các marker dựa trên macEntries và macCoordinates
    List<Marker> activeMarkers = macEntries
    .where((entry) =>
        entry['status'] == true &&
        macCoordinates.containsKey(entry['mac'].toUpperCase()))
    .map((entry) {
  String mac = entry['mac'].toUpperCase();
  Color markerColor = entry['color'] ?? Colors.red;
  String deviceName = entry['name'];

  return Marker(
    key: Key(mac),
    point: macCoordinates[mac]!,
    width: 30, // Kích thước cố định
    height: 30,
    anchorPos: AnchorPos.align(AnchorAlign.bottom), // Neo ở dưới
    builder: (ctx) => Tooltip(
      message: deviceName, // Hiển thị tên thiết bị
      child: Container(
        width: 30, // Kích thước cố định
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: markerColor,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(
          Icons.star, // Bạn có thể thay đổi biểu tượng theo ý muốn
          color: Colors.white,
          size: 20, // Kích thước biểu tượng cố định
        ),
      ),
    ),
  );
}).toList();

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 136, 226, 136),
      appBar: AppBar(
        title: Text("Chào mừng!"),
        backgroundColor: const Color.fromRGBO(255, 157, 155, 238),
        actions: [
          // Nút Cảnh Báo với Đỏ Dấu Chấm
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.warning,
                    color: const Color.fromARGB(255, 254, 254, 254)),
                iconSize: 40,
                tooltip: "Xem Cảnh Báo",
                onPressed: _showAlertsDialog,
              ),
              if (newAlertsCount > 0)
                Positioned(
                  right: 11, // Điều chỉnh vị trí cho phù hợp
                  top: 11,
                  child: Container(
                    width: 10, // Kích thước nhỏ hơn cho một chấm
                    height: 10, // Kích thước nhỏ hơn cho một chấm
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Tooltip(
              message: "Đăng xuất",
              child: IconButton(
                onPressed: _showLogoutConfirmationDialog, // Đã sửa ở đây
                icon: const Icon(Icons.logout),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          children: [
            // Bản đồ
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  center: _currentLocation ??
                      LatLng(10.848248, 106.767519), // định vị mặc định
                  zoom: _currentZoom,
                  onPositionChanged: (MapPosition position, bool hasGesture) {
                    if (position.zoom != _currentZoom &&
                        _currentLocation != null) {
                      setState(() {
                        _currentZoom = position.zoom ?? _currentZoom;
                        _circleMarker = CircleMarker(
                          point: _currentLocation!,
                          color: Colors.blue.withOpacity(0.3),
                          borderStrokeWidth: 2,
                          borderColor: Colors.blue,
                          radius: _calculatePixelRadius(_radius,
                              _currentLocation!.latitude, _currentZoom),
                        );
                      });

                      // Kiểm tra khoảng cách sau khi thay đổi zoom
                      checkDeviceDistances();
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: ['a', 'b', 'c'],
                  ),
                  MarkerLayer(
                    markers: activeMarkers,
                  ),
                  if (_circleMarker != null)
                    CircleLayer(
                      circles: [_circleMarker!],
                    ),
                ],
              ),
            ),
            SizedBox(height: 20),
            // Nút Điều Khiển
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Nút lấy vị trí hiện tại
                Tooltip(
                  message: "Lấy vị trí hiện tại",
                  child: ElevatedButton(
                    onPressed: _getCurrentLocation,
                    child: Icon(Icons.location_on),
                  ),
                ),
                // Nút chnh sửa bán kính
                Tooltip(
                  message: "Chỉnh sửa bán kính",
                  child: ElevatedButton(
                    onPressed: () => _showRadiusInputDialog(context),
                    child: Icon(Icons.edit),
                  ),
                ),
                // Nút quản lý thiết bị
                Tooltip(
                  message: "Quản lý thiết bị",
                  child: ElevatedButton(
                    onPressed: () => _showMacInputDialog(context),
                    child: Icon(Icons.format_list_numbered),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Hàm Đã Thêm: Hiển thị Hộp Thoại Xác Nhận Đăng Xuất
  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Xác nhận đăng xuất"),
          content: Text("Bạn có chắc chắn muốn đăng xuất không?"),
          actions: [
            TextButton(
              child: Text("Không", style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop(); // Đóng hộp thoại
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color.fromARGB(255, 57, 133, 79), // Màu nền nút
              ),
            ),
            ElevatedButton(
              child: Text("Có", style: TextStyle(color: Colors.white)),
              onPressed: () {
                saveAlerts(); // Lưu cảnh báo trước khi đăng xuất
                _boxLogin.clear(); // Chỉ xóa hộp 'login'
                _boxLogin.put(
                    "loginStatus", false); // Đặt lại trạng thái đăng nhập
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => Login()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color.fromARGB(255, 57, 133, 79), // Màu nền nút
              ),
            ),
          ],
        );
      },
    );
  }

  void saveAlerts() {
    String userEmail =
        _boxLogin.get('userEmail', defaultValue: 'default_email');
    _boxAccounts.put(
        '${userEmail}_alerts',
        alerts
            .map((alert) => {
                  'mac': alert.mac,
                  'time': alert.time.toIso8601String(),
                  'message': alert.message,
                })
            .toList());
  }

  void loadAlerts() {
    String userEmail =
        _boxLogin.get('userEmail', defaultValue: 'default_email');
    List<dynamic> storedAlerts =
        _boxAccounts.get('${userEmail}_alerts', defaultValue: []);

    setState(() {
      alerts = storedAlerts
          .map((alert) => Alert(
                mac: alert['mac'],
                time: DateTime.parse(alert['time']),
                message: alert['message'],
              ))
          .toList();
    });
  }
}

// Widget cho Hiển Thị Cảnh Báo Theo Trang
class AlertsPaginatedView extends StatefulWidget {
  final List<Alert> alerts;
  final Map<String, String> macToNameMap;

  AlertsPaginatedView({required this.alerts, required this.macToNameMap});

  @override
  _AlertsPaginatedViewState createState() => _AlertsPaginatedViewState();
}

class _AlertsPaginatedViewState extends State<AlertsPaginatedView> {
  int currentPage = 0;
  late int totalPages;

  @override
  void initState() {
    super.initState();
    totalPages = (widget.alerts.length / 5).ceil();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alerts.isEmpty) {
      return Text("Không có cảnh báo nào.");
    }

    // Sắp xếp cảnh báo từ mới nhất đến cũ nhất
    List<Alert> sortedAlerts = List.from(widget.alerts);
    sortedAlerts.sort((a, b) => b.time.compareTo(a.time));

    // Tính lại tổng số trang dựa trên danh sách đã sắp xếp
    totalPages = (sortedAlerts.length / 5).ceil();

    // Lấy 5 cảnh báo tương ứng với trang hiện tại
    List<Alert> currentAlerts =
        sortedAlerts.skip(currentPage * 5).take(5).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.maxFinite,
          height: 200, // Chiều cao cố định cho ListView
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: currentAlerts.length,
            itemBuilder: (context, index) {
              final alert = currentAlerts[index];
              String deviceName = widget.macToNameMap[alert.mac] ?? alert.mac;

              return ListTile(
                leading: Icon(Icons.warning, color: Colors.red),
                title: Text("Tên: $deviceName"),
                subtitle: Text(
                    "Thời gian: ${alert.time.toLocal().toString().split('.')[0]}\n${alert.message}"),
              );
            },
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: currentPage > 0
                    ? () {
                        setState(() {
                          currentPage--;
                        });
                      }
                    : null,
                child: Text("Trang trước", style: TextStyle(fontSize: 11)),
              ),
            ),
            SizedBox(width: 7),
            Text("Trang ${currentPage + 1} / $totalPages"),
            SizedBox(width: 7),
            Expanded(
              child: ElevatedButton(
                onPressed: currentPage < totalPages - 1
                    ? () {
                        setState(() {
                          currentPage++;
                        });
                      }
                    : null,
                child: Text("Trang sau", style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Widget cho Hộp Thoại Nhập MAC
class MacInputDialog extends StatefulWidget {
  final List<Map<String, dynamic>> macEntries;
  final List<TextEditingController> nameControllers;
  final List<TextEditingController> macControllers;
  final Map<String, DateTime> receivedMacs;
  final VoidCallback onUpdate;
  final List<Color> deviceColors;

  MacInputDialog({
    required this.macEntries,
    required this.nameControllers,
    required this.macControllers,
    required this.receivedMacs,
    required this.onUpdate,
    required this.deviceColors,
  });

  @override
  _MacInputDialogState createState() => _MacInputDialogState();
}

class _MacInputDialogState extends State<MacInputDialog> {
  @override
  void initState() {
    super.initState();
    // Khởi tạo text của các controller chỉ một lần
    for (int i = 0; i < widget.macEntries.length; i++) {
      widget.nameControllers[i].text = widget.macEntries[i]['name'];
      widget.macControllers[i].text = widget.macEntries[i]['mac'];
    }
    // Tự động xác thực và cập nhật trạng thái khi hộp thoại được mở
    WidgetsBinding.instance.addPostFrameCallback((_) {
      validateMACs();
    });
  }

  // Hàm để kiểm tra xem MAC tại chỉ mục hiện tại có trùng lặp không (không phân biệt chữ hoa chữ thường)
  bool _isDuplicateMac(String mac, int currentIndex) {
    if (mac.isEmpty) return false;
    for (int i = 0; i < widget.macEntries.length; i++) {
      if (i != currentIndex &&
          widget.macEntries[i]['mac'].toUpperCase() == mac.toUpperCase()) {
        return true;
      }
    }
    return false;
  }

  // Hàm để kiểm tra xem đây có phải là lần xuất hiện đầu tiên của MAC không
  bool _isFirstOccurrence(String mac, int currentIndex) {
    String normalizedMac = mac.toUpperCase();
    for (int i = 0; i < currentIndex; i++) {
      if (widget.macEntries[i]['mac'].toUpperCase() == normalizedMac) {
        return false;
      }
    }
    return true;
  }

  // Hàm để xác thực và cập nhật trạng thái kết nối của tất cả các thiết bị
  void validateMACs() {
    // Tạo một bản đồ để đếm số lần xuất hiện của mỗi MAC (không phân biệt chữ hoa chữ thường)
    Map<String, int> macCount = {};
    for (var entry in widget.macEntries) {
      String currentMac = entry['mac'];
      if (currentMac.isNotEmpty) {
        String normalizedMac = currentMac.toUpperCase();
        macCount[normalizedMac] = (macCount[normalizedMac] ?? 0) + 1;
      }
    }

    print("MAC Counts: $macCount"); // Debug

    setState(() {
      for (int i = 0; i < widget.macEntries.length; i++) {
        var entry = widget.macEntries[i];
        String currentMac = entry['mac'];
        if (currentMac.isNotEmpty && isValidMac(currentMac)) {
          String normalizedMac = currentMac.toUpperCase();
          bool isDuplicate = macCount[normalizedMac]! > 1;
          bool isReceived = widget.receivedMacs.containsKey(normalizedMac);
          if (isReceived && !isDuplicate) {
            // MAC hợp lệ và không trùng lặp
            entry['status'] = true;
            print(
                "Đặt trạng thái BẬT cho ${entry['name']} với MAC $currentMac");
          } else {
            // MAC trùng lặp hoặc chưa nhận từ MQTT
            entry['status'] = false;
            print(
                "Đặt trạng thái TẮT cho ${entry['name']} với MAC $currentMac");
          }
        } else {
          // MAC không hợp lệ hoặc trống
          entry['status'] = false;
          print(
              "Đặt trạng thái TẮT cho ${entry['name']} với MAC không hợp lệ hoặc trống");
        }
      }
      widget.onUpdate(); // Thông báo cho parent lưu thay đổi
    });
  }

  // Hàm để xác thực định dạng MAC address
  bool isValidMac(String mac) {
    final RegExp macRegExp =
        RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return macRegExp.hasMatch(mac);
  }

  // Hàm để thêm một thiết bị mới
  void _addDevice() {
  if (widget.macEntries.length >= 5) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bạn chỉ có thể thêm tối đa 5 thiết bị.'),
      ),
    );
    return;
  }

  // Tìm màu chưa được sử dụng
  Color newColor = widget.deviceColors.firstWhere(
    (color) => !widget.macEntries.any((entry) => entry['color'] == color),
    orElse: () => widget.deviceColors[0], // Mặc định nếu tất cả màu đã được sử dụng
  );

  setState(() {
    int newIndex = widget.macEntries.length;
    widget.macEntries.add({
      'name': 'Thiết bị ${newIndex + 1}',
      'mac': '',
      'status': false,
      'color': newColor, // Gán màu mới
    });
    widget.nameControllers
        .add(TextEditingController(text: 'Thiết bị ${newIndex + 1}'));
    widget.macControllers.add(TextEditingController());
    widget.onUpdate(); // Thông báo cho parent lưu thay đổi
  });

  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Đã thêm thiết bị ${widget.macEntries.length}',
      ),
    ),
  );
}

  // Hàm kiểm tra trùng tên
  bool _isDuplicateName(String name, int index) {
    for (int i = 0; i < widget.macEntries.length; i++) {
      if (i != index && widget.macEntries[i]['name'] == name) {
        return true; // Tìm thấy tên trùng
      }
    }
    return false; // Không tìm thấy tên trùng
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Quản lý các thiết bị ESP"),
      content: SingleChildScrollView(
        child: Column(
          children: widget.macEntries.asMap().entries.map((entry) {
            int index = entry.key;
            var macEntry = entry.value;

            bool isDuplicate = _isDuplicateMac(macEntry['mac'], index);
            bool isValid = isValidMac(macEntry['mac']);
            bool isFirst = _isFirstOccurrence(macEntry['mac'], index);
            bool hasError = (macEntry['mac'].isNotEmpty &&
                    (!isValid || (isDuplicate && !isFirst))) ||
                widget.nameControllers[index].text.isEmpty;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  // Tên thiết bị
                  Expanded(
                    flex: 4, // Tăng flex cho trường dài hơn
                    child: TextField(
                      controller: widget.nameControllers[index],
                      decoration: InputDecoration(
                        labelText: "Tên thi���t bị",
                        hintText: "Nhập tên thiết bị",
                        border: OutlineInputBorder(),
                        isDense: true,
                        errorText: (() {
                          String name =
                              widget.nameControllers[index].text.trim();
                          if (name.isEmpty) return "Tên không được để trống";
                          if (_isDuplicateName(name, index)) {
                            return "Tên thiết bị đã tồn tại"; // Kiểm tra trùng tên
                          }
                          return null;
                        })(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          widget.macEntries[index]['name'] =
                              value.trim(); // Cập nhật tên thit bị
                          widget
                              .onUpdate(); // Thông báo cho parent lưu thay đổi
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 10),
                  // Địa chỉ MAC
                  Expanded(
                    flex: 4, // Tăng flex cho trường dài hơn
                    child: TextField(
                      controller:
                          widget.macControllers[index], // Sử dụng controller
                      decoration: InputDecoration(
                        labelText: "MAC",
                        hintText: "Nhập MAC",
                        border: OutlineInputBorder(),
                        isDense: true,
                        errorText: (() {
                          String mac = widget.macControllers[index].text.trim();
                          if (mac.isEmpty) return null;
                          if (!isValidMac(mac)) {
                            return "MAC không hợp lệ";
                          }
                          if (_isDuplicateMac(mac, index)) {
                            // Kiểm tra nếu đây không phải là lần xuất hiện đầu tiên
                            if (!_isFirstOccurrence(mac, index)) {
                              return "MAC đã được sử dụng";
                            }
                          }
                          return null;
                        })(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          widget.macEntries[index]['mac'] =
                              value.trim(); // Giữ định dạng gốc
                          // Sau khi cập nht MAC, xác thực và cập nhật trạng thái kết nối của tất cả các thiết bị
                          validateMACs();
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 10),
                  // Trạng thái kết nối
                  Icon(
                    macEntry['status'] ? Icons.toggle_on : Icons.toggle_off,
                    color: macEntry['status'] ? Colors.green : Colors.grey,
                    size: 24, // Giảm kích thước biểu tượng xuống 24
                  ),
                  SizedBox(width: 5),
                  // Nút kiểm tra kết nối
                  IconButton(
                    icon: Icon(Icons.check,
                        color: Colors.blue,
                        size: 24), // Giảm kích thước biểu tượng xuống 24
                    tooltip: "Kiểm tra kết nối",
                    onPressed: hasError
                        ? null // Vô hiệu hóa nếu có lỗi
                        : () {
                            // Không tiến hành nếu có lỗi
                            String mac =
                                widget.macControllers[index].text.trim();
                            if (mac.isEmpty ||
                                !isValidMac(mac) ||
                                _isDuplicateMac(mac, index)) {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Vui lòng sửa lỗi trước khi kiểm tra kết nối'),
                                ),
                              );
                              return;
                            }

                            // Chuẩn hóa MAC để so sánh
                            String normalizedMac = mac.toUpperCase();

                            setState(() {
                              if (widget.receivedMacs
                                  .containsKey(normalizedMac)) {
                                widget.macEntries[index]['status'] = true;
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${widget.macEntries[index]['name']} đang kết nối'),
                                  ),
                                );
                              } else {
                                widget.macEntries[index]['status'] = false;
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${widget.macEntries[index]['name']} không kết nối'),
                                  ),
                                );
                              }
                              widget.onUpdate();
                              // Lưu thay đổi vào Hive
                            });
                          },
                  ),
                  // Nút xóa thiết bị
                  IconButton(
                    icon: Icon(Icons.delete,
                        color: Colors.red,
                        size: 24), // Giảm kích thước biểu tượng xuống 24
                    tooltip: "Xóa thiết bị",
                    onPressed: () {
                      String deviceName = widget.macEntries[index]
                          ['name']; // Lấy tên thiết bị trước khi xóa
                      setState(() {
                        // Lấy MAC của thiết bị đang xóa
                        String macToDelete =
                            widget.macEntries[index]['mac'].toUpperCase();

                        // Loại bỏ thiết b khỏi danh sách
                        widget.macEntries.removeAt(index);
                        widget.nameControllers[index].dispose();
                        widget.macControllers[index]
                            .dispose(); // Giải phóng controller
                        widget.nameControllers.removeAt(index);
                        widget.macControllers.removeAt(index);
                      });

                      // Hiển thị Snackbar với tên thiết bị chính xác
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Đã xóa thiết bị $deviceName'), // Sử dụng tên thiết bị đã lấy
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        // Nút thêm thiết bị mới
        ElevatedButton.icon(
          onPressed: widget.macEntries.length >= 5
              ? null
              : () {
                  String newDeviceName =
                      "Tên thiết bị mới"; // Lấy tên thiết bị mới từ input
                  if (_isDuplicateName(newDeviceName, -1)) {
                    // Kiểm tra trùng tên
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tên thiết bị đã tồn tại!'),
                      ),
                    );
                    return; // Không thêm thiết bị nếu trùng tên
                  }
                  _addDevice(); // Gọi hàm thêm thiết bị nếu không trùng tên
                },
          icon: Icon(Icons.add),
          label: Text("Thêm thiết bị", style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                const Color.fromARGB(255, 57, 133, 79), // Màu nền nút
            foregroundColor: Colors.white, // Màu chữ khi được kích hoạt
          ),
        ),
        // Nút đóng hộp thoại
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("Đóng", style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                const Color.fromARGB(255, 57, 133, 79), // Màu nền nút
          ),
        ),
      ],
    );
  }
}

void requestNotificationPermission() async {
  if (await Permission.notification.request().isGranted) {
    // Quyền đã được cấp
    print("Quyền thông báo đã được cấp.");
  } else {
    // Quyền chưa được cấp
    print("Quyền thông báo chưa được cấp.");
  }
}
