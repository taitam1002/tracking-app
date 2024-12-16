import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Thêm dòng này

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final GlobalKey<FormState> _formKey = GlobalKey();
  final TextEditingController _controllerEmail = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 253, 253, 253),
       appBar: AppBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 150),
              Text(
                "Quên Mật Khẩu",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _controllerEmail,
                decoration: InputDecoration(
                  labelText: "Email",
                  prefixIcon: const Icon(Icons.email_outlined),
                  // Đường viền luôn hiển thị
                  border: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey), // Màu mặc định
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue, width: 2.0), // Màu khi được chọn
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey, width: 2.0), // Màu khi không được chọn
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Vui lòng nhập email.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState?.validate() ?? false) {
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(
                        email: _controllerEmail.text,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Email đặt lại mật khẩu đã được gửi!"),
                        ),
                      );
                      Navigator.pop(context);
                    } on FirebaseAuthException catch (e) {
                      // Xử lý lỗi
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message ?? "Đã xảy ra lỗi")),
                      );
                    }
                  }
                },
                child: const Text("Đặt Lại Mật Khẩu"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}