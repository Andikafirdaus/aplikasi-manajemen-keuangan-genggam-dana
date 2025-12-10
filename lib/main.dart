import 'dart:async';  // TAMBAHKAN INI
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; 
// =================== Import Firebase ===================
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ========================================================
import 'package:provider/provider.dart';

// ===================================
// Bagian 0: Inisialisasi Firebase & Main
// ===================================
void main() async {
  // Wajib: Memastikan Flutter binding siap sebelum inisialisasi asynchronous
  WidgetsFlutterBinding.ensureInitialized(); 
  
  // ===================================================
  // KODE PERBAIKAN (BYPASS): INISIALISASI FIREBASE MANUAL
  // ===================================================
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      // Data diambil dari JSON project 'genggam-dana-app' milik Anda:
      apiKey: 'AIzaSyBkiNMcY2xQcOkl0zA0vATIB6HO4_Cf3EQ', 
      appId: '1:679617301254:android:36c1156f46d841c3606c87', 
      messagingSenderId: '679617301254', 
      projectId: 'genggam-dana-app', 
      storageBucket: 'genggam-dana-app.firebasestorage.app', 
    ),
  );
  // ===================================================
  // >>> AKHIR KODE PERBAIKAN <<<
  // ===================================================
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provider untuk Database Service
        Provider<DatabaseService>(
          create: (_) => DatabaseService(),
        ),
        // StreamProvider untuk User Authentication
        StreamProvider<User?>.value(
          value: FirebaseAuth.instance.authStateChanges(),
          initialData: null,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Genggam Dana App',
        theme: ThemeData(
          primarySwatch: Colors.blue, 
          fontFamily: 'Roboto', 
        ),
        // Cek sesi user di SplashScreen
        home: const SplashScreen(),
      ),
    );
  }
}

// ===================================
// Bagian 0A: MODELS
// ===================================

class UserModel {
  final String uid;
  final String email;
  final String fullName;
  final String phoneNumber;
  final DateTime dateOfBirth;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    required this.dateOfBirth,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      fullName: map['fullName'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      dateOfBirth: DateTime.parse(map['dateOfBirth']),
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}

class TransactionModel {
  final String? id;
  final String userId;
  final String type; // 'income' atau 'expense'
  final String category;
  final double amount;
  final String description;
  final DateTime date;
  final DateTime createdAt;

  TransactionModel({
    this.id,
    required this.userId,
    required this.type,
    required this.category,
    required this.amount,
    required this.description,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'category': category,
      'amount': amount,
      'description': description,
      'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: data['type'] ?? '',
      category: data['category'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      description: data['description'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}

// ===================================
// Bagian 0B: DATABASE SERVICE
// ===================================

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // === USER OPERATIONS ===
  Future<void> saveUserData(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<UserModel?> getUserData(String uid) async {
    DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  // === TRANSACTION OPERATIONS ===
  
  // Tambah transaksi baru
  Future<String> addTransaction(TransactionModel transaction) async {
    DocumentReference docRef = await _firestore.collection('transactions').add(transaction.toMap());
    return docRef.id;
  }

  // Ambil semua transaksi user
  Stream<List<TransactionModel>> getUserTransactions(String userId) {
    return _firestore
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
  }

  // Ambil transaksi berdasarkan bulan
  Stream<List<TransactionModel>> getMonthlyTransactions(String userId, DateTime month) {
    DateTime firstDay = DateTime(month.year, month.month, 1);
    DateTime lastDay = DateTime(month.year, month.month + 1, 0);
    
    return _firestore
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(lastDay))
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
  }

  // Hitung total pemasukan
  Future<double> getTotalIncome(String userId, DateTime month) async {
    DateTime firstDay = DateTime(month.year, month.month, 1);
    DateTime lastDay = DateTime(month.year, month.month + 1, 0);
    
    QuerySnapshot snapshot = await _firestore
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'income')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(lastDay))
        .get();
    
    double total = 0;
    for (var doc in snapshot.docs) {
      total += (doc.data() as Map<String, dynamic>)['amount'].toDouble();
    }
    return total;
  }

  // Hitung total pengeluaran
  Future<double> getTotalExpense(String userId, DateTime month) async {
    DateTime firstDay = DateTime(month.year, month.month, 1);
    DateTime lastDay = DateTime(month.year, month.month + 1, 0);
    
    QuerySnapshot snapshot = await _firestore
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'expense')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(lastDay))
        .get();
    
    double total = 0;
    for (var doc in snapshot.docs) {
      total += (doc.data() as Map<String, dynamic>)['amount'].toDouble();
    }
    return total;
  }

  // Hapus transaksi
  Future<void> deleteTransaction(String transactionId) async {
    await _firestore.collection('transactions').doc(transactionId).delete();
  }

  // Update transaksi
  Future<void> updateTransaction(TransactionModel transaction) async {
    if (transaction.id == null) return;
    await _firestore
        .collection('transactions')
        .doc(transaction.id!)
        .update(transaction.toMap());
  }
}

// ===================================
// Bagian 1: Widget Splash Screen (Pengecekan Sesi User)
// ===================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      
      User? user = FirebaseAuth.instance.currentUser;
      
      if (user != null) {
        // Jika sudah login, langsung ke Beranda
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        // Jika belum login, ke Halaman Registrasi Awal
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const RegistrationScreen1()), 
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(
              height: 100,
              child: Center(
                child: Icon(
                  Icons.account_balance_wallet, 
                  size: 55, 
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 10), 
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Genggam',
                    style: TextStyle(
                      color: Colors.black, 
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: 'Dana',
                    style: TextStyle(
                      color: Colors.blue.shade800, 
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================
// Bagian 2A: Halaman REGISTRASI Langkah 1 (Email Input)
// ===================================
class RegistrationScreen1 extends StatefulWidget { 
  const RegistrationScreen1({super.key});

  @override
  State<RegistrationScreen1> createState() => _RegistrationScreen1State();
}

class _RegistrationScreen1State extends State<RegistrationScreen1> {
  final TextEditingController _emailController = TextEditingController();

  void _onContinuePressed() {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && email.contains('@') && email.contains('.')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => RegistrationDetailsScreen(email: email),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan email yang valid')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Colors.blue.shade700;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, 
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 50),
            const Center(
              child: SizedBox( 
                height: 80, width: 80,
                child: Center(
                  child: Icon(Icons.account_balance_wallet, color: Colors.blueGrey, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Center( 
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Genggam',
                      style: TextStyle(
                        color: Colors.black, 
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                        letterSpacing: -0.5,
                      ),
                    ),
                    TextSpan(
                      text: 'Dana',
                      style: TextStyle(
                        color: Colors.blue.shade800, 
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 50),
            
            const Text(
              'Ayo Gabung dan Mulai Kelola Keuangan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Masukkan Email Anda',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            
            TextField(
              controller: _emailController, 
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'email@domain.com',
                hintText: 'email@domain.com',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: Colors.grey)
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: Colors.black54, width: 1.5)
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
              ),
            ),
            const SizedBox(height: 30),
            
            ElevatedButton(
              onPressed: _onContinuePressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor, 
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Lanjutkan', 
                style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
            
            const Row(
              children: [
                Expanded(child: Divider(color: Colors.grey)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10.0),
                  child: Text('atau', style: TextStyle(color: Colors.grey)), 
                ),
                Expanded(child: Divider(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 20),
            
            OutlinedButton(
              onPressed: () {
                print('Initiating Google Sign-In...');
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: BorderSide(color: Colors.grey.shade300, width: 1.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.person, color: Colors.black54, size: 20), 
                  SizedBox(width: 10),
                  Text(
                    'Daftar dengan Google', 
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const SignInPage()),
                  );
                },
                child: Text.rich(
                  TextSpan(
                    text: 'Sudah punya akun? ',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    children: [
                      TextSpan(
                        text: 'Masuk di sini',
                        style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Center(
              child: Text.rich(
                TextSpan(
                  text: 'Dengan mendaftar, Anda menyetujui ', 
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  children: [
                    TextSpan(
                      text: 'Ketentuan Layanan', 
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold), 
                    ),
                    const TextSpan(text: ' dan '),
                    TextSpan(
                      text: 'Kebijakan Privasi', 
                      style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold), 
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
              const SizedBox(height: 40), 
          ],
        ),
      ),
    );
  }
}

// ===================================
// Bagian 2B: Halaman REGISTRASI Langkah 2 (Detail User & Password)
// ===================================
class RegistrationDetailsScreen extends StatefulWidget {
  final String email;

  const RegistrationDetailsScreen({super.key, required this.email});

  @override
  State<RegistrationDetailsScreen> createState() => _RegistrationDetailsScreenState();
}

class _RegistrationDetailsScreenState extends State<RegistrationDetailsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  DateTime? _selectedDate;
  bool _isLoading = false; // TAMBAHKAN LOADING STATE
  
  final Color primaryColor = Colors.blue.shade700;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }
  
  // LOGIKA REGISTRASI FIREBASE (Auth & Firestore) - UPDATE DENGAN DATABASE SERVICE
  void _onRegisterPressed() async {
    // Validasi Sederhana
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || _passwordController.text.length < 8 || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mohon lengkapi semua data dan pastikan password minimal 8 karakter.')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // 1. Buat Akun User di Firebase Authentication
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: widget.email.trim(),
        password: _passwordController.text,
      );
      
      final userId = credential.user!.uid;

      // 2. Buat User Model
      final user = UserModel(
        uid: userId,
        email: widget.email,
        fullName: _nameController.text,
        phoneNumber: _phoneController.text,
        dateOfBirth: _selectedDate!,
        createdAt: DateTime.now(),
      );

      // 3. Simpan ke Firestore menggunakan DatabaseService
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      await databaseService.saveUserData(user);
          
      // 4. Registrasi Sukses
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registrasi Berhasil! Silakan Masuk.'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigasi kembali ke Halaman Login (SignInPage)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SignInPage()),
        (Route<dynamic> route) => false,
      );

    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'weak-password') {
        message = 'Password terlalu lemah.';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email ini sudah terdaftar.';
      } else if (e.code == 'invalid-email') {
        message = 'Format email tidak valid.';
      } else {
        message = 'Pendaftaran gagal: ${e.message}'; 
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Terjadi error tak terduga: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lengkapi Pendaftaran', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white), 
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Anda mendaftar sebagai ${widget.email}', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 20),

                  // 1. Input Nama
                  const Text('Nama Lengkap', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildTextField(controller: _nameController, hintText: 'Masukkan nama Anda'),
                  const SizedBox(height: 20),

                  // 2. Input Tanggal Lahir
                  const Text('Tanggal Lahir', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDate == null
                                ? 'Pilih Tanggal'
                                : DateFormat('dd MMMM yyyy').format(_selectedDate!),
                            style: TextStyle(fontSize: 16, color: _selectedDate == null ? Colors.grey : Colors.black87),
                          ),
                          Icon(Icons.calendar_today, color: primaryColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Input Nomor Telepon
                  const Text('Nomor Telepon', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _phoneController, 
                    hintText: 'Cth: 0812345678',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 20),

                  // 4. Input Password
                  const Text('Buat Kata Sandi', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildPasswordField(controller: _passwordController, hintText: 'Minimal 8 Karakter'),
                  const SizedBox(height: 40),

                  // Tombol Daftar
                  ElevatedButton(
                    onPressed: _isLoading ? null : _onRegisterPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor, 
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Daftar Sekarang', 
                            style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildTextField({required TextEditingController controller, required String hintText, TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hintText,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: primaryColor, width: 1.5)
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
      ),
    );
  }

  Widget _buildPasswordField({required TextEditingController controller, required String hintText}) {
    return TextField(
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(
        hintText: hintText,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: primaryColor, width: 1.5)
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
      ),
    );
  }
}


// ===================================
// Bagian 3: Halaman MASUK (SignInPage)
// ===================================
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false; // TAMBAHKAN LOADING STATE
  
  final Color primaryColor = Colors.blue.shade700;

  // LOGIKA LOGIN FIREBASE (Auth)
  void _onLoginPressed() async {
    // Validasi Sederhana
    if (_emailController.text.isEmpty || _passwordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email atau Password tidak lengkap.')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Panggil fungsi Login dari Firebase Authentication
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      // Login Sukses
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login Berhasil! Mengarahkan ke Beranda.'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigasi ke Home Screen setelah Login Sukses
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (Route<dynamic> route) => false,
      );

    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        message = 'Kombinasi Email dan Password tidak valid.';
      } else if (e.code == 'invalid-email') {
        message = 'Format email tidak valid.';
      } else {
        message = 'Login gagal: ${e.message}';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Terjadi error tak terduga: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masuk ke Akun', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white), 
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 50),
            
            const Text(
              'Masuk untuk Mengelola Keuangan Anda',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),

            // Input Email
            const Text('Email', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController, 
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'email@domain.com',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                contentPadding: EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
              ),
            ),
            const SizedBox(height: 20),

            // Input Password
            const Text('Kata Sandi', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController, 
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Minimal 8 Karakter',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                contentPadding: EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
              ),
            ),
            const SizedBox(height: 40),

            // Tombol Masuk
            ElevatedButton(
              onPressed: _isLoading ? null : _onLoginPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor, 
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Masuk', 
                      style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
            ),
            
            const SizedBox(height: 20),
            
            TextButton(
              onPressed: () => print('Aksi: Lupa Password'),
              child: Text('Lupa Kata Sandi?', style: TextStyle(color: primaryColor)),
            ),

            const SizedBox(height: 40),
            
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const RegistrationScreen1()),
                  );
                },
                child: Text.rich(
                  TextSpan(
                    text: 'Belum punya akun? ',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    children: [
                      TextSpan(
                        text: 'Daftar sekarang',
                        style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ===================================
// Bagian 4: Halaman Dashboard / Beranda (HomeScreen)
// ===================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0; 
  final Color primaryColor = Colors.blue.shade800;

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      const DashboardScreen(), 
      const StatisticsScreen(), 
      const Center(child: Text('Placeholder Transaksi Baru (dihandle modal)', style: TextStyle(fontSize: 20))), 
      const BudgetNotificationScreen(), 
      const AccountManagementScreen(), 
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      if (index == 2) {
        _showNewTransactionModal(context);
        return;
      }
      _selectedIndex = index;
    });
  }
  
  void _showNewTransactionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return const NewTransactionModal();
      },
    ).then((_) {
      // Optional: Refresh data setelah modal ditutup
      print('Modal transaksi ditutup');
    });
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Beranda';
      case 1:
        return 'Statistik';
      case 3:
        return 'Notifikasi & Anggaran'; 
      case 4:
        return 'Akun';
      default:
        return 'GenggamDana';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        automaticallyImplyLeading: false, 
      ),
      
      body: _widgetOptions.elementAt(_selectedIndex),

      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Beranda'),
          BottomNavigationBarItem(icon: Icon(Icons.insert_chart), label: 'Statistik'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle, size: 35), label: 'Transaksi'), 
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Anggaran'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Akun'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true, 
        onTap: _onItemTapped,
      ),
    );
  }
}

// ===================================
// Bagian 5: Halaman BERANDA UTAMA (DashboardScreen) - ✅ PERBAIKAN UTAMA DISINI
// ===================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DatabaseService _databaseService;
  late User? _currentUser;
  double _totalIncome = 0;
  double _totalExpense = 0;
  List<TransactionModel> _recentTransactions = [];
  DateTime _currentMonth = DateTime.now();
  var _transactionSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _databaseService = Provider.of<DatabaseService>(context);
    _currentUser = Provider.of<User?>(context);
    _loadDashboardData();
  }

  void _loadDashboardData() {
    if (_currentUser == null) return;

    // Batalkan subscription sebelumnya jika ada
    _transactionSubscription?.cancel();

    _transactionSubscription = _databaseService
        .getUserTransactions(_currentUser!.uid)
        .listen((transactions) {
      // PERHITUNGAN REAL-TIME DARI SEMUA TRANSAKSI
      double income = 0;
      double expense = 0;
      
      // Filter hanya transaksi bulan ini
      final monthlyTransactions = transactions.where((transaction) {
        return transaction.date.year == _currentMonth.year &&
               transaction.date.month == _currentMonth.month;
      }).toList();
      
      // Hitung total pemasukan dan pengeluaran
      for (var transaction in monthlyTransactions) {
        if (transaction.type == 'income') {
          income += transaction.amount;
        } else if (transaction.type == 'expense') {
          expense += transaction.amount;
        }
      }
      
      if (mounted) {
        setState(() {
          _totalIncome = income;
          _totalExpense = expense;
          _recentTransactions = transactions.take(5).toList();
        });
        
        // Debug print untuk memastikan perhitungan
        print('=== Dashboard Data Update ===');
        print('Total transactions: ${transactions.length}');
        print('Monthly transactions: ${monthlyTransactions.length}');
        print('Income: $_totalIncome, Expense: $_totalExpense');
        print('Saldo: ${income - expense}');
      }
    }, onError: (error) {
      print('Error loading transaction stream: $error');
    });
  }

  @override
  void dispose() {
    _transactionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Colors.blue.shade800;
    final double totalBalance = _totalIncome - _totalExpense;
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Card(
            color: primaryColor,
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Saldo Total Anda',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(_currentMonth),
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatter.format(totalBalance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _BalanceSummary(
                        icon: Icons.arrow_downward, 
                        label: 'Pemasukan', 
                        amount: formatter.format(_totalIncome), 
                        color: Colors.lightGreenAccent,
                      ),
                      _BalanceSummary(
                        icon: Icons.arrow_upward, 
                        label: 'Pengeluaran', 
                        amount: formatter.format(_totalExpense), 
                        color: Colors.redAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 25),

          const Text(
            'Aksi Cepat',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQuickActionButton(
                context, 
                icon: Icons.account_balance_wallet, 
                label: 'Rekening', 
                onTap: () => print('Aksi: Manajemen Rekening'),
              ),
              _buildQuickActionButton(
                context, 
                icon: Icons.category, 
                label: 'Kategori', 
                onTap: () => print('Aksi: Edit Kategori'),
              ),
              _buildQuickActionButton(
                context, 
                icon: Icons.bar_chart, 
                label: 'Lihat Grafik', 
                onTap: () {
                    final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                    homeState?._onItemTapped(1); 
                },
              ),
              _buildQuickActionButton(
                context, 
                icon: Icons.savings, 
                label: 'Tabungan', 
                onTap: () => print('Aksi: Manajemen Tabungan'),
              ),
            ],
          ),

          const SizedBox(height: 30),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transaksi Terbaru',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  print('Lihat semua transaksi');
                },
                child: Text(
                  'Lihat Semua',
                  style: TextStyle(color: primaryColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          if (_recentTransactions.isEmpty)
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300)
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long, size: 50, color: Colors.grey),
                    SizedBox(height: 10),
                    Text(
                      'Belum ada transaksi',
                      style: TextStyle(color: Colors.grey),
                    ),
                    Text(
                      'Tambahkan transaksi pertama Anda!',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: _recentTransactions.map((transaction) {
                return _TransactionTile(transaction: transaction);
              }).toList(),
            ),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }
  
  Widget _buildQuickActionButton(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Icon(icon, color: Colors.blue.shade700, size: 28),
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  final Color color;

  const _BalanceSummary({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Text(
              amount,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final bool isIncome = transaction.type == 'income';
    final Color color = isIncome ? Colors.green.shade700 : Colors.red.shade700;
    final IconData icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
    final String amountText = '${isIncome ? '+' : '-'} Rp ${NumberFormat('#,###').format(transaction.amount)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          transaction.description,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          '${transaction.category} • ${DateFormat('dd MMM').format(transaction.date)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          amountText,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        onTap: () {
          // Aksi ketika transaksi ditekan
          print('Transaksi ${transaction.id} ditekan');
        },
      ),
    );
  }
}

// ===================================
// Bagian 6: Halaman MANAJEMEN AKUN (AccountManagementScreen) - UPDATE DENGAN DATA USER
// ===================================
class AccountManagementScreen extends StatelessWidget {
  const AccountManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final User? currentUser = Provider.of<User?>(context);
    final DatabaseService databaseService = Provider.of<DatabaseService>(context);
    
    return FutureBuilder<UserModel?>(
      future: currentUser != null ? databaseService.getUserData(currentUser.uid) : Future.value(null),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final userName = user?.fullName ?? 'Nama Pengguna';
        final userEmail = user?.email ?? currentUser?.email ?? 'user@email.com';
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(15.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.blueGrey,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      userName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      userEmail,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
              
              _buildOptionGroup(
                title: 'Informasi Akun',
                children: [
                  _buildAccountTile(
                    context,
                    icon: Icons.edit,
                    title: 'Edit Profil',
                    subtitle: 'Ubah nama dan foto profil Anda',
                    onTap: () => print('Navigasi ke Edit Profil'),
                  ),
                  const Divider(height: 0), 
                  _buildAccountTile(
                    context,
                    icon: Icons.email_outlined,
                    title: 'Ganti Email',
                    subtitle: 'Perbarui alamat email akun Anda',
                    onTap: () => print('Navigasi ke Ganti Email'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              _buildOptionGroup(
                title: 'Keamanan & Privasi',
                children: [
                  _buildAccountTile(
                    context,
                    icon: Icons.lock_outline,
                    title: 'Ganti Password',
                    subtitle: 'Perbarui kata sandi Anda secara berkala',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
                      );
                    },
                  ),
                  const Divider(height: 0), 
                  _buildAccountTile(
                    context,
                    icon: Icons.notifications_none,
                    title: 'Pengaturan Notifikasi',
                    subtitle: 'Atur notifikasi anggaran dan transaksi',
                    onTap: () => print('Navigasi ke Pengaturan Notifikasi'),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    // Logout Firebase
                    await FirebaseAuth.instance.signOut();

                    Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const SignInPage()),
                        (Route<dynamic> route) => false,
                    );
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    'Keluar (Logout)',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      }
    );
  }
  
  Widget _buildOptionGroup({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        Card(
          elevation: 2, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildAccountTile(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue.shade700),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }
}

// ===================================
// Bagian 7: Halaman GANTI PASSWORD (ChangePasswordScreen)
// ===================================
class ChangePasswordScreen extends StatelessWidget {
  const ChangePasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ganti Password', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue.shade800,
        iconTheme: const IconThemeData(color: Colors.white), 
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Perbarui kata sandi Anda untuk menjaga keamanan akun.',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 30),

            const Text('Password Lama', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildPasswordField(hintText: 'Masukkan password lama Anda'),
            
            const SizedBox(height: 20),

            const Text('Password Baru', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildPasswordField(hintText: 'Minimal 8 Karakter'),

            const SizedBox(height: 20),

            const Text('Konfirmasi Password Baru', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildPasswordField(hintText: 'Ketik ulang password baru'),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password sedang diproses untuk diganti...')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Simpan Password Baru',
                style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPasswordField({required String hintText}) {
    return TextField(
      obscureText: true,
      decoration: InputDecoration(
        hintText: hintText,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 1.5)
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
      ),
    );
  }
}


// ===================================
// Bagian 8: Halaman STATISTIK & GRAFIK (StatisticsScreen) - UPDATE DENGAN DATA REAL
// ===================================
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late DatabaseService _databaseService;
  late User? _currentUser;
  double _totalIncome = 0;
  double _totalExpense = 0;
  List<TransactionModel> _recentTransactions = [];
  var _transactionSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _databaseService = Provider.of<DatabaseService>(context);
    _currentUser = Provider.of<User?>(context);
    _loadStatisticsData();
  }

  void _loadStatisticsData() {
    if (_currentUser == null) return;

    // Batalkan subscription sebelumnya
    _transactionSubscription?.cancel();

    final now = DateTime.now();
    
    _transactionSubscription = _databaseService
        .getMonthlyTransactions(_currentUser!.uid, now)
        .listen((transactions) {
      double income = 0;
      double expense = 0;
      
      for (var transaction in transactions) {
        if (transaction.type == 'income') {
          income += transaction.amount;
        } else if (transaction.type == 'expense') {
          expense += transaction.amount;
        }
      }
      
      if (mounted) {
        setState(() {
          _totalIncome = income;
          _totalExpense = expense;
          _recentTransactions = transactions.take(10).toList();
        });
      }
    }, onError: (error) {
      print('Error loading statistics data: $error');
    });
  }

  @override
  void dispose() {
    _transactionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Colors.blue.shade800;
    
    final double total = _totalIncome + _totalExpense;
    final double incomePercentage = total > 0 ? (_totalIncome / total) * 100 : 0;
    final double expensePercentage = total > 0 ? (_totalExpense / total) * 100 : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                child: Column(
                  children: [
                    Text(
                      'Statistik Pengeluaran vs Pemasukan',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                    ),
                    const SizedBox(height: 15),
                    
                    if (total > 0)
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            height: 150,
                            width: 150,
                            child: CircularProgressIndicator(
                              value: _totalExpense / total, 
                              strokeWidth: 20,
                              backgroundColor: Colors.lightGreen, 
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent), 
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Sisa Dana', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                'Rp ${NumberFormat('#,###').format(_totalIncome - _totalExpense)}',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          Icon(Icons.pie_chart_outline, size: 80, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          const Text(
                            'Belum ada data transaksi',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    
                    const SizedBox(height: 15),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegend(color: Colors.lightGreen, label: 'Pemasukan (${incomePercentage.toStringAsFixed(0)}%)'),
                        const SizedBox(width: 15),
                        _buildLegend(color: Colors.redAccent, label: 'Pengeluaran (${expensePercentage.toStringAsFixed(0)}%)'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 30),

          Text(
            'Riwayat Transaksi Terbaru',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
          ),
          const SizedBox(height: 10),
          
          if (_recentTransactions.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long, size: 50, color: Colors.grey),
                    SizedBox(height: 10),
                    Text(
                      'Belum ada transaksi',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentTransactions.length,
              itemBuilder: (context, index) {
                final transaction = _recentTransactions[index];
                final isIncome = transaction.type == 'income';
                final amountText = isIncome ? '+ Rp ${NumberFormat('#,###').format(transaction.amount)}' : '- Rp ${NumberFormat('#,###').format(transaction.amount)}';
                final color = isIncome ? Colors.green.shade700 : Colors.red.shade700;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Card(
                    margin: EdgeInsets.zero,
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.1),
                        child: Icon(
                          isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                          color: color,
                        ),
                      ),
                      title: Text(transaction.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${transaction.category} • ${DateFormat('dd MMM').format(transaction.date)}'),
                      trailing: Text(
                        amountText,
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
  
  Widget _buildLegend({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}


// ===================================
// Bagian 9: Halaman ANGGARAN & NOTIFIKASI (BudgetNotificationScreen)
// ===================================
class BudgetNotificationScreen extends StatelessWidget {
  const BudgetNotificationScreen({super.key});
  
  final List<Map<String, dynamic>> financialNotifications = const [
    {'title': 'Gaji Masuk', 'subtitle': 'Rp 10.000.000 telah masuk ke Rekening Utama.', 'icon': Icons.arrow_downward, 'color': Colors.green},
    {'title': 'Anggaran Pakaian Habis', 'subtitle': 'Anda telah menghabiskan 95% dari anggaran Pakaian bulan ini.', 'icon': Icons.warning, 'color': Colors.orange},
  ];
  
  final List<Map<String, dynamic>> promoNotifications = const [
    {'title': 'PROMO 50% Cashback', 'subtitle': 'Dapatkan diskon 50% untuk transaksi di kafe partner kami.', 'icon': Icons.local_offer, 'color': Colors.blue},
    {'title': 'Tips Keuangan', 'subtitle': 'Pelajari cara mengelola utang dengan cerdas di artikel terbaru.', 'icon': Icons.lightbulb_outline, 'color': Colors.amber},
  ];
  
  final List<Map<String, dynamic>> activeBudgets = const [
    {'category': 'Makanan', 'used': 800000, 'total': 1500000, 'icon': Icons.restaurant},
    {'category': 'Transportasi', 'used': 300000, 'total': 500000, 'icon': Icons.directions_bus},
  ];


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[

          _buildHeader('Notifikasi Penting', Icons.notifications_active, Colors.red),
          const SizedBox(height: 10),
          ...financialNotifications.map((notif) => _buildNotificationTile(
            title: notif['title'] as String,
            subtitle: notif['subtitle'] as String,
            icon: notif['icon'] as IconData,
            color: notif['color'] as Color,
          )).toList(),

          const Divider(height: 40),
          
          _buildHeader('Anggaran Bulan Ini', Icons.money, Colors.blue),
          const SizedBox(height: 10),
          // Pastikan penggunaan spread operator (...) di sini
          ...activeBudgets.map((budget) => _buildBudgetCard(budget)).toList(),

          const Divider(height: 40),

          _buildHeader('Penawaran & Info Lain', Icons.info_outline, Colors.grey),
          const SizedBox(height: 10),
            ...promoNotifications.map((notif) => _buildNotificationTile(
            title: notif['title'] as String,
            subtitle: notif['subtitle'] as String,
            icon: notif['icon'] as IconData,
            color: notif['color'] as Color,
            isPromo: true,
          )).toList(),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }
  
  Widget _buildHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildNotificationTile({
    required String title, 
    required String subtitle, 
    required IconData icon, 
    required Color color, 
    bool isPromo = false
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(fontWeight: isPromo ? FontWeight.normal : FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
        trailing: isPromo ? const Icon(Icons.chevron_right) : null,
        onTap: () => print('Notifikasi $title ditekan'),
      ),
    );
  }
  
  Widget _buildBudgetCard(Map<String, dynamic> budget) {
    double progress = (budget['used'] as int) / (budget['total'] as int);
    Color progressColor = progress > 0.8 ? Colors.red.shade700 : Colors.green.shade700;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(budget['icon'] as IconData, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  budget['category'] as String,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Rp ${NumberFormat('#,###').format(budget['used'])}/${NumberFormat('#,###').format(budget['total'])}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
            const SizedBox(height: 5),
            Text(
              'Sudah terpakai ${((progress * 100).toStringAsFixed(0))}% dari total anggaran.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}


// ===================================
// Bagian 10: Modal TRANSAKSI BARU (NewTransactionModal) - ✅ PERBAIKAN UTAMA DISINI
// ===================================
class NewTransactionModal extends StatefulWidget {
  const NewTransactionModal({super.key});

  @override
  State<NewTransactionModal> createState() => _NewTransactionModalState();
}

class _NewTransactionModalState extends State<NewTransactionModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DatabaseService _databaseService;
  late User? _currentUser;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedCategory = 'Lainnya';
  
  int _transactionType = 0; // 0 = expense, 1 = income
  
  // Daftar kategori
  final List<String> _expenseCategories = [
    'Makanan & Minuman',
    'Transportasi',
    'Belanja',
    'Hiburan',
    'Kesehatan',
    'Pendidikan',
    'Tagihan',
    'Lainnya'
  ];
  
  final List<String> _incomeCategories = [
    'Gaji',
    'Bonus',
    'Investasi',
    'Hadiah',
    'Lainnya'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _databaseService = Provider.of<DatabaseService>(context);
    _currentUser = Provider.of<User?>(context);
  }

  void _handleTabSelection() {
    setState(() {
      _transactionType = _tabController.index;
      // Reset kategori saat ganti tab
      _selectedCategory = _transactionType == 0 
          ? _expenseCategories.first 
          : _incomeCategories.first;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
  
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _saveTransaction() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan login terlebih dahulu!')),
      );
      return;
    }
    
    if (_amountController.text.isEmpty || _descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal dan deskripsi tidak boleh kosong!')),
      );
      return;
    }
    
    try {
      final amount = double.tryParse(_amountController.text);
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Masukkan nominal yang valid!')),
        );
        return;
      }
      
      final transaction = TransactionModel(
        userId: _currentUser!.uid,
        type: _transactionType == 1 ? 'income' : 'expense',
        category: _selectedCategory,
        amount: amount,
        description: _descriptionController.text,
        date: _selectedDate,
        createdAt: DateTime.now(),
      );
      
      await _databaseService.addTransaction(transaction);
      
      // TAMPILKAN NOTIFIKASI DULU
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_transactionType == 1 ? 'Pemasukan' : 'Pengeluaran'} berhasil dicatat!',
          ),
          backgroundColor: _transactionType == 1 ? Colors.green : Colors.blue,
          duration: const Duration(seconds: 2), // Durasi 2 detik
        ),
      );
      
      // TUNGGU SEBENTAR AGAR NOTIFIKASI TERLIHAT, BARU TUTUP MODAL
      await Future.delayed(const Duration(milliseconds: 2200));
      
      // TUTUP MODAL (JENDELA TURUN)
      Navigator.pop(context);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final modalHeight = MediaQuery.of(context).size.height * 0.85;
    final primaryColor = _transactionType == 1 ? Colors.green.shade700 : Colors.red.shade700;
    final currentCategories = _transactionType == 0 ? _expenseCategories : _incomeCategories;

    return Container(
      height: modalHeight,
      padding: EdgeInsets.only(
        top: 15,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transaksi Baru',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryColor),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 15),
          
          Container(
            height: 45,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: primaryColor,
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.black54,
              tabs: const [
                Tab(text: 'Pengeluaran'),
                Tab(text: 'Pemasukan'),
              ],
            ),
          ),
          
          const SizedBox(height: 25),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pilih Kategori
                  Text('Kategori', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: currentCategories.length,
                      itemBuilder: (context, index) {
                        final category = currentCategories[index];
                        final isSelected = category == _selectedCategory;
                        
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                            selectedColor: primaryColor,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 20),

                  // Input Nominal
                  Text('Nominal Uang (Rp)', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Cth: 50000',
                      prefixText: 'Rp ',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Input Deskripsi
                  Text('Deskripsi Transaksi', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      hintText: _transactionType == 0 
                          ? 'Cth: Beli makan siang, Bayar listrik' 
                          : 'Cth: Gaji bulanan, Bonus proyek',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Pilih Tanggal
                  Text('Tanggal Transaksi', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: primaryColor),
                          const SizedBox(width: 10),
                          Text(
                            DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate),
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Spacer(),
                          Icon(Icons.arrow_drop_down, color: primaryColor),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // Tombol Simpan
          ElevatedButton(
            onPressed: _saveTransaction,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Simpan Transaksi',
              style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}