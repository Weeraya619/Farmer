import 'package:flutter/material.dart';
import 'package:project/services/auth_service.dart';
//import 'pages/start_page.dart';
import 'pages/login.dart';
import 'pages/register.dart';
import 'pages/account.dart';
//import 'pages/finance_record_page.dart';

// ตัวแปร global เดียวที่ถือ session ทั้งแอป — ใช้แทน `supabase` เดิม
// ทุกหน้าที่ต้อง signIn/signUp/signOut หรือเช็คสถานะ login ให้ import ไฟล์นี้
final authService = AuthService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // โหลด session เดิมที่อาจค้างอยู่ในเครื่อง (ถ้าเคย login ไว้แล้วไม่ได้ signOut)
  await authService.loadSession();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: authService.isLoggedIn ? '/startpage' : '/loginpage',
      routes: {
        //'/startpage': (context) => const StartPage(),
        '/loginpage': (context) => const LoginPage(),
        '/registerpage': (context) => const RegisterPage(),
        '/accountpage': (context) => const AccountPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/expense') {
          //final args = settings.arguments as Map<String, dynamic>;
          // return MaterialPageRoute(
          //   builder: (context) => FinanceRecordPage(
          //     farmService: args['farmService'],
          //     purchasedCows: args['cows'],
          //     initialRecordDate: args['recordDate'],
          //   ),
          // );
        }
        return null;
      },
    );
  }
}