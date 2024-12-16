import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart'; // Nhập thư viện Firebase Core
import 'firebase_options.dart'; // Nhập tệp chứa thông tin FirebaseOptions
import 'main_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Đảm bảo rằng các widget đã được khởi tạo
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Khởi tạo Firebase với thông tin từ tệp firebase_options.dart
  );
  await _initHive(); // Khởi tạo Hive
  runApp(const MainApp()); // Chạy ứng dụng
}

Future<void> _initHive() async {
  await Hive.initFlutter();  // Khởi tạo Hive
  await Hive.openBox("login");  // Mở hộp lưu trữ thông tin đăng nhập
  await Hive.openBox("accounts");  // Mở hộp lưu trữ tài khoản
}
