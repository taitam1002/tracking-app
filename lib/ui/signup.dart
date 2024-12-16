import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Thêm dòng này
import 'package:hive_flutter/hive_flutter.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  final GlobalKey<FormState> _formKey = GlobalKey();
  final TextEditingController _controllerEmail = TextEditingController();
  final TextEditingController _controllerPassword = TextEditingController();
  final TextEditingController _controllerConfirmPassword =
      TextEditingController();
  final Box _boxAccounts = Hive.box("accounts");

  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        // title: const Text("Đăng Ký"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back), // Biểu tượng quay lại
          onPressed: () {
            Navigator.pop(context); // Quay về trang đăng nhập
          },
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 30),
              Text(
                "Đăng Ký tài khoản",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _controllerEmail,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Vui lòng nhập email.";
                  } else if (!value.contains('@') || !value.contains('.')) {
                    return "Vui lòng nhập email hợp lệ.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _controllerPassword,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "Mật khẩu",
                  prefixIcon: const Icon(Icons.password_outlined),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Vui lòng nhập mật khẩu.";
                  } else if (value.length < 8) {
                    return "Mật khẩu phải có ít nhất 8 ký tự.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _controllerConfirmPassword,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "Xác nhận mật khẩu",
                  prefixIcon: const Icon(Icons.password_outlined),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Vui lòng xác nhận mật khẩu.";
                  } else if (value != _controllerPassword.text) {
                    return "Mật khẩu không khớp.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState?.validate() ?? false) {
                    try {
                      await FirebaseAuth.instance
                          .createUserWithEmailAndPassword(
                        email: _controllerEmail.text,
                        password: _controllerPassword.text,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Đăng ký thành công!"),
                        ),
                      );
                      Navigator.pop(context);
                    } on FirebaseAuthException catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message ?? "Đã xảy ra lỗi")),
                      );
                    }
                  }
                },
                child: const Text("Đăng Ký"),
              ),
              const SizedBox(height: 10), // Thêm khoảng cách giữa các nút
            ],
          ),
        ),
      ),
    );
  }
}
