import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Thêm dòng này
import 'package:hive_flutter/hive_flutter.dart';
import 'home.dart';
import 'signup.dart';
import 'forgot_password.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final GlobalKey<FormState> _formKey = GlobalKey();
  final TextEditingController _controllerPassword = TextEditingController();
  final TextEditingController _controllerEmail = TextEditingController(); 
  bool _obscurePassword = true;
  final Box _boxLogin = Hive.box("login");

  @override
  Widget build(BuildContext context) {
    if (_boxLogin.get("loginStatus") ?? false) {
      return Home();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 150),
              Text(
                "Đăng nhập",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _controllerEmail,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Vui lòng nhập email.";
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
                  prefixIcon: const Icon(Icons.password),
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
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState?.validate() ?? false) {
                    try {
                      await FirebaseAuth.instance.signInWithEmailAndPassword(
                        email: _controllerEmail.text,
                        password: _controllerPassword.text,
                      );

                      _boxLogin.put("loginStatus", true);
                      _boxLogin.put("userEmail", _controllerEmail.text);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => Home()),
                      );
                    } on FirebaseAuthException catch (e) {
                      String message;
                      switch (e.code) {
                        case 'invalid-email':
                          message = "Địa chỉ Email không hợp lệ.";
                          break;
                        // Thêm các trường hợp khác nếu cần
                        default:
                          message = "Email hoặc mật khẩu không đúng.";
                      }
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    }
                  }
                },
                child: const Text("Đăng nhập"),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Bạn chưa có tài khoản?"),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const Signup()),
                      );
                    },
                    child: const Text("Đăng ký",style: TextStyle(color: Color.fromARGB(255, 236, 115, 10)),),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ForgotPassword()),
                  );
                },
                child: const Text("Quên mật khẩu?",style: TextStyle(color: Color.fromARGB(255, 236, 115, 10)),),
              ),
            ],
          ),
        ),
      ),
    );
  }
}