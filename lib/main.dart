import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
const navy = Color(0xFF172554);
const blue = Color(0xFF4169E1);
const pageBg = Color(0xFFF5F7FC);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeamBookApp());
}

class TeamBookApp extends StatelessWidget {
  const TeamBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeamBook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: pageBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: pageBg,
          foregroundColor: navy,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: blue, width: 1.5),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _usersKey = 'tb_auth_users_v1';
  static const _sessionKey = 'tb_auth_session_v1';
  bool _checking = true;
  bool _signedIn = false;
  String _displayName = '';
  String _email = '';
  String _role = 'employee';

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_sessionKey);
    final users = _readUsers(prefs.getString(_usersKey));
    if (email != null && users.containsKey(email)) {
      _email = email;
      _displayName = '${users[email]['name'] ?? 'Team member'}';
      _role = '${users[email]['role'] ?? 'employee'}';
      _signedIn = true;
    }
    if (mounted) setState(() => _checking = false);
  }

  Map<String, dynamic> _readUsers(String? raw) {
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map(
        (key, value) => MapEntry('$key', (value as Map).cast<String, dynamic>()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<String?> _authenticate({
    required bool isSignup,
    required String name,
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim().toLowerCase();
    final users = _readUsers(prefs.getString(_usersKey));
    final passwordHash = sha256.convert(utf8.encode(password)).toString();

    // Demo-only admin account. In production, roles must be assigned and verified by a backend.
    if (!isSignup && normalizedEmail == 'admin@teambook.demo' && password == 'Admin123') {
      users[normalizedEmail] = {'name': 'TeamBook Admin', 'passwordHash': passwordHash, 'role': 'admin'};
      await prefs.setString(_usersKey, jsonEncode(users));
      await prefs.setString(_sessionKey, normalizedEmail);
      if (mounted) setState(() { _email = normalizedEmail; _displayName = 'TeamBook Admin'; _role = 'admin'; _signedIn = true; });
      return null;
    }

    if (isSignup) {
      if (users.containsKey(normalizedEmail)) {
        return 'An account with this email already exists. Please sign in.';
      }
      users[normalizedEmail] = {
        'name': name.trim(),
        'passwordHash': passwordHash,
        'role': 'employee',
      };
      await prefs.setString(_usersKey, jsonEncode(users));
    } else {
      final account = users[normalizedEmail];
      if (account == null || account['passwordHash'] != passwordHash) {
        return 'Email or password is incorrect. If you are new, create an account first.';
      }
    }

    await prefs.setString(_sessionKey, normalizedEmail);
    if (!mounted) return null;
    setState(() {
      _email = normalizedEmail;
      _displayName = isSignup ? name.trim() : '${users[normalizedEmail]['name'] ?? 'Team member'}';
      _role = isSignup ? 'employee' : '${users[normalizedEmail]['role'] ?? 'employee'}';
      _signedIn = true;
    });
    return null;
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _displayName = '';
      _email = '';
      _role = 'employee';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_signedIn) {
      return TeamBookHome(
        key: ValueKey(_email),
        displayName: _displayName,
        email: _email,
        role: _role,
        onLogout: _logout,
      );
    }
    return AuthPage(onAuthenticate: _authenticate);
  }
}

class AuthPage extends StatefulWidget {
  final Future<String?> Function({
    required bool isSignup,
    required String name,
    required String email,
    required String password,
  }) onAuthenticate;

  const AuthPage({super.key, required this.onAuthenticate});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _signup = false;
  bool _hidePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String? _validEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!RegExp(r'^[A-Za-z0-9.!#$%&’*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$').hasMatch(v)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    String? error;
    try {
      error = await widget.onAuthenticate(
        isSignup: _signup,
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (_) {
      error = 'Something went wrong. Please try again.';
    }
    if (!mounted) return;
    setState(() { _busy = false; _error = error; });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: width < 420 ? 18 : 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 58, height: 58,
                      decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(18)),
                      child: const Icon(Icons.groups_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('TeamBook', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: navy)),
                  const SizedBox(height: 5),
                  const Text('Your team, all in one place.', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey)),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(width < 420 ? 18 : 26),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_signup ? 'Create your account' : 'Welcome back',
                              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: navy)),
                            const SizedBox(height: 6),
                            Text(_signup ? 'Set up your TeamBook workspace.' : 'Sign in to open your team directory.',
                              style: const TextStyle(color: Colors.blueGrey)),
                            const SizedBox(height: 22),
                            if (_signup) ...[
                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined)),
                              validator: _validEmail,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              obscureText: _hidePassword,
                              textInputAction: _signup ? TextInputAction.next : TextInputAction.done,
                              autofillHints: _signup ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                              onFieldSubmitted: (_) { if (!_signup) _submit(); },
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                  icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: _validPassword,
                            ),
                            if (_signup) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirmPassword,
                                obscureText: _hidePassword,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.verified_user_outlined)),
                                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(12)),
                                child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(_signup ? 'Create account' : 'Sign in'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _busy ? null : () => setState(() { _signup = !_signup; _error = null; }),
                              child: Text(_signup ? 'Already have an account? Sign in' : 'New to TeamBook? Create an account'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Demo accounts stay in this browser/device. Admin demo: admin@teambook.demo / Admin123',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class Employee {
  final int id;
  final String firstName, lastName, email, phone, image, title, department;
  final String address, city, state, postalCode, country;
  final bool isLocal;

  const Employee({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.image,
    required this.title,
    required this.department,
    required this.address,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    this.isLocal = false,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get location => [city, state, country].where((e) => e.trim().isNotEmpty).join(', ');

  Employee copyWith({
    int? id, String? firstName, String? lastName, String? email, String? phone,
    String? image, String? title, String? department, String? address,
    String? city, String? state, String? postalCode, String? country, bool? isLocal,
  }) => Employee(
    id: id ?? this.id, firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName, email: email ?? this.email,
    phone: phone ?? this.phone, image: image ?? this.image,
    title: title ?? this.title, department: department ?? this.department,
    address: address ?? this.address, city: city ?? this.city,
    state: state ?? this.state, postalCode: postalCode ?? this.postalCode,
    country: country ?? this.country, isLocal: isLocal ?? this.isLocal,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'firstName': firstName, 'lastName': lastName, 'email': email,
    'phone': phone, 'image': image, 'title': title, 'department': department,
    'address': address, 'city': city, 'state': state, 'postalCode': postalCode,
    'country': country, 'isLocal': isLocal,
  };

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    id: (j['id'] as num?)?.toInt() ?? 0,
    firstName: '${j['firstName'] ?? ''}', lastName: '${j['lastName'] ?? ''}',
    email: '${j['email'] ?? ''}', phone: '${j['phone'] ?? ''}',
    image: '${j['image'] ?? ''}', title: '${j['title'] ?? ''}',
    department: '${j['department'] ?? ''}', address: '${j['address'] ?? ''}',
    city: '${j['city'] ?? ''}', state: '${j['state'] ?? ''}',
    postalCode: '${j['postalCode'] ?? ''}', country: '${j['country'] ?? ''}',
    isLocal: j['isLocal'] == true,
  );

  factory Employee.fromApi(Map<String, dynamic> j) {
    final company = (j['company'] as Map?)?.cast<String, dynamic>() ?? {};
    final addr = (j['address'] as Map?)?.cast<String, dynamic>() ?? {};
    return Employee(
      id: (j['id'] as num?)?.toInt() ?? 0,
      firstName: '${j['firstName'] ?? ''}', lastName: '${j['lastName'] ?? ''}',
      email: '${j['email'] ?? ''}', phone: '${j['phone'] ?? ''}',
      image: '${j['image'] ?? ''}', title: '${company['title'] ?? j['role'] ?? ''}',
      department: '${company['department'] ?? ''}',
      address: '${addr['address'] ?? ''}', city: '${addr['city'] ?? ''}',
      state: '${addr['state'] ?? ''}', postalCode: '${addr['postalCode'] ?? ''}',
      country: '${addr['country'] ?? ''}',
    );
  }
}

class EmployeeStore extends ChangeNotifier {
  static const _createdKey = 'tb_created_v1';
  static const _editedKey = 'tb_edited_v1';
  static const _deletedKey = 'tb_deleted_v1';
  static const _starKey = 'tb_starred_v1';
  static const _recentKey = 'tb_recent_profiles_v1';
  static const _activityKey = 'tb_activity_v1';

  final List<Employee> _remote = [];
  final Map<int, Employee> _created = {};
  final Map<int, Employee> _edited = {};
  final Set<int> _deleted = {};
  final Set<int> _starred = {};
  final List<int> _recentProfileIds = [];
  final Map<int, String> _activity = {};
  bool loading = false;
  bool loaded = false;
  String? error;
  int _nextLocalId = -1;

  List<Employee> get employees {
    final result = <Employee>[];
    for (final e in _remote) {
      if (_deleted.contains(e.id)) continue;
      result.add(_edited[e.id] ?? e);
    }
    for (final e in _created.values) {
      if (!_deleted.contains(e.id)) result.add(e);
    }
    result.sort((a, b) => a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
    return result;
  }

  int get starredCount => _starred.length;
  bool isStarred(int id) => _starred.contains(id);
  int get totalCount => employees.length;
  List<Employee> get recentProfiles => _recentProfileIds
      .map((id) => employees.where((e) => e.id == id).firstOrNull)
      .whereType<Employee>().toList();
  List<Employee> get recentActivity => _activity.keys
      .map((id) => employees.where((e) => e.id == id).firstOrNull)
      .whereType<Employee>().toList()
    ..sort((a, b) => (_activity[b.id] ?? '').compareTo(_activity[a.id] ?? ''));
  String? activityFor(int id) => _activity[id];

  Future<void> markViewed(Employee e) async {
    _recentProfileIds.remove(e.id);
    _recentProfileIds.insert(0, e.id);
    if (_recentProfileIds.length > 12) _recentProfileIds.removeLast();
    await _persist();
    notifyListeners();
  }

  void _markActivity(int id, String label) {
    _activity[id] = '${DateTime.now().toIso8601String()}|$label';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _loadMap(prefs.getString(_createdKey), _created);
    _loadMap(prefs.getString(_editedKey), _edited);
    final deleted = prefs.getStringList(_deletedKey) ?? [];
    _deleted.addAll(deleted.map((e) => int.tryParse(e)).whereType<int>());
    final starred = prefs.getStringList(_starKey) ?? [];
    _recentProfileIds.addAll((prefs.getStringList(_recentKey) ?? []).map((e) => int.tryParse(e)).whereType<int>());
    try {
      final rawActivity = prefs.getString(_activityKey);
      if (rawActivity != null) {
        final decoded = jsonDecode(rawActivity) as Map<String, dynamic>;
        _activity.addAll(decoded.map((k, v) => MapEntry(int.tryParse(k) ?? 0, '$v')));
      }
    } catch (_) {}
    _starred.addAll(starred.map((e) => int.tryParse(e)).whereType<int>());
    final ids = _created.keys.where((id) => id < 0).toList();
    if (ids.isNotEmpty) _nextLocalId = ids.reduce((a, b) => a < b ? a : b) - 1;
    await refresh();
  }

  void _loadMap(String? raw, Map<int, Employee> target) {
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        target[int.tryParse(entry.key) ?? 0] =
            Employee.fromJson((entry.value as Map).cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_createdKey, jsonEncode(_created.map((k, v) => MapEntry('$k', v.toJson()))));
    await prefs.setString(_editedKey, jsonEncode(_edited.map((k, v) => MapEntry('$k', v.toJson()))));
    await prefs.setStringList(_deletedKey, _deleted.map((e) => '$e').toList());
    await prefs.setStringList(_starKey, _starred.map((e) => '$e').toList());
    await prefs.setStringList(_recentKey, _recentProfileIds.map((e) => '$e').toList());
    await prefs.setString(_activityKey, jsonEncode(_activity.map((k, v) => MapEntry('$k', v))));
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final response = await http.get(
        Uri.parse('https://dummyjson.com/users?limit=100'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Server returned ${response.statusCode}');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['users'] as List? ?? []);
      _remote
        ..clear()
        ..addAll(list.map((e) => Employee.fromApi((e as Map).cast<String, dynamic>())));
      loaded = true;
    } catch (e) {
      error = 'Could not connect to the employee service. Your saved local employees are still available.';
      loaded = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Employee> add(Employee draft) async {
    final employee = draft.copyWith(id: _nextLocalId--, isLocal: true);
    _created[employee.id] = employee;
    _markActivity(employee.id, 'Added');
    await _persist();
    notifyListeners();
    // DummyJSON mutations are intentionally not treated as permanent storage.
    try {
      await http.post(Uri.parse('https://dummyjson.com/users/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'firstName': employee.firstName, 'lastName': employee.lastName,
          'email': employee.email, 'phone': employee.phone})).timeout(const Duration(seconds: 8));
    } catch (_) {}
    return employee;
  }

  Future<void> update(Employee employee) async {
    if (_created.containsKey(employee.id)) {
      _created[employee.id] = employee.copyWith(isLocal: true);
      _markActivity(employee.id, 'Updated');
    } else {
      _edited[employee.id] = employee.copyWith(isLocal: false);
      _markActivity(employee.id, 'Updated');
      try {
        await http.put(Uri.parse('https://dummyjson.com/users/${employee.id}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'firstName': employee.firstName, 'lastName': employee.lastName,
            'email': employee.email, 'phone': employee.phone})).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(Employee e) async {
    _deleted.add(e.id);
    await _persist();
    notifyListeners();
  }

  Future<void> toggleStar(Employee e) async {
    if (!_starred.add(e.id)) _starred.remove(e.id);
    await _persist();
    notifyListeners();
  }

  Future<void> clearLocalData() async {
    _created.clear(); _edited.clear(); _deleted.clear(); _starred.clear(); _recentProfileIds.clear(); _activity.clear();
    await _persist();
    notifyListeners();
  }
}

class TeamBookHome extends StatefulWidget {
  final String displayName;
  final String email;
  final String role;
  final Future<void> Function() onLogout;
  const TeamBookHome({super.key, required this.displayName, required this.email, required this.role, required this.onLogout});
  @override
  State<TeamBookHome> createState() => _TeamBookHomeState();
}

class _TeamBookHomeState extends State<TeamBookHome> {
  final EmployeeStore store = EmployeeStore();
  int selectedTab = 0;
  String query = '';
  String departmentFilter = 'All departments';
  String roleFilter = 'All job roles';
  String sortBy = 'nameAsc';
  bool onlyStarred = false;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    store.addListener(_onChanged);
    store.init().then((_) { if (mounted) setState(() => ready = true); });
  }

  void _onChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() { store.removeListener(_onChanged); store.dispose(); super.dispose(); }

  List<Employee> get visibleEmployees {
    var items = store.employees;
    if (onlyStarred) items = items.where((e) => store.isStarred(e.id)).toList();
    if (departmentFilter != 'All departments') items = items.where((e) => e.department == departmentFilter).toList();
    if (roleFilter != 'All job roles') items = items.where((e) => e.title == roleFilter).toList();
    items = [...items];
    if (sortBy == 'nameDesc') { items.sort((a, b) => b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase())); }
    else if (sortBy == 'department') { items.sort((a, b) => a.department.toLowerCase().compareTo(b.department.toLowerCase())); }
    else { items.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase())); }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((e) => '${e.fullName} ${e.email} ${e.phone} ${e.department} ${e.title} ${e.location}'.toLowerCase().contains(q)).toList();
    }
    return items;
  }

  void _openProfile(Employee e) {
    store.markViewed(e);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmployeeProfilePage(
      employee: e, store: store, isAdmin: widget.role == 'admin',
      onEdit: (employee) async {
        final updated = await Navigator.of(context).push<Employee>(
          MaterialPageRoute(builder: (_) => EmployeeFormPage(store: store, employee: employee)));
        if (updated != null && mounted) {
          Navigator.of(context).pop();
          _openProfile(updated);
        }
      },
    )));
  }

  Future<void> _addEmployee() async {
    final employee = await Navigator.of(context).push<Employee>(
      MaterialPageRoute(builder: (_) => EmployeeFormPage(store: store)));
    if (employee != null && mounted) {
      setState(() { selectedTab = 1; onlyStarred = false; query = ''; });
      _openProfile(employee);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final pages = [
      _dashboard(),
      _directory(),
      _directory(starred: true),
      _settings(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.groups_rounded, color: Colors.white)),
          const SizedBox(width: 10),
          const Text('TeamBook', style: TextStyle(fontWeight: FontWeight.w800, color: navy)),
        ]),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 520)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(child: Text('Hi, ${widget.displayName.split(' ').first}',
                style: const TextStyle(color: navy, fontWeight: FontWeight.w600))),
            ),
          IconButton(tooltip: 'Refresh employees', onPressed: store.loading ? null : store.refresh,
            icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: !ready ? const Center(child: CircularProgressIndicator()) : Row(children: [
        if (wide) _sidebar(),
        Expanded(child: IndexedStack(index: selectedTab, children: pages)),
      ]),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (i) => setState(() { selectedTab = i; onlyStarred = i == 2; }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'People'),
          NavigationDestination(icon: Icon(Icons.star_outline), selectedIcon: Icon(Icons.star), label: 'Starred'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      floatingActionButton: widget.role == 'admin' && (selectedTab == 1 || selectedTab == 2)
        ? FloatingActionButton.extended(onPressed: _addEmployee, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add employee'))
        : null,
    );
  }

  Widget _sidebar() => Container(
    width: 220, margin: const EdgeInsets.fromLTRB(16, 8, 8, 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.all(12), child: Text('WORKSPACE', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.grey, fontWeight: FontWeight.bold))),
      _navItem(0, Icons.space_dashboard_outlined, 'Overview'),
      _navItem(1, Icons.people_outline, 'People'),
      _navItem(2, Icons.star_outline, 'Starred'),
      _navItem(3, Icons.settings_outlined, 'Settings'),
      const Spacer(),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(14)),
        child: const Text('One place for your people.', style: TextStyle(color: navy, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _navItem(int index, IconData icon, String label) {
    final active = selectedTab == index;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: active, selectedTileColor: const Color(0xFFEAF0FF),
      leading: Icon(icon, color: active ? blue : Colors.blueGrey),
      title: Text(label, style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? navy : Colors.blueGrey)),
      onTap: () => setState(() { selectedTab = index; onlyStarred = index == 2; }),
    ));
  }

  Widget _dashboard() {
    final items = store.employees;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [navy, Color(0xFF3658B5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR PEOPLE, CONNECTED.', style: TextStyle(color: Color(0xFFD5E1FF), letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Good work starts\nwith great teams.', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 12),
            const Text('Keep your employee directory organised and up to date.', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            if (widget.role == 'admin') FilledButton.icon(onPressed: _addEmployee, icon: const Icon(Icons.add), label: const Text('Add employee'),
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: navy)),
          ]),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, c) {
          final count = c.maxWidth < 450 ? 2 : 3;
          final cards = [
            _statCard('Employees', '${store.totalCount}', Icons.people_alt_outlined, blue),
            _statCard('Starred', '${store.starredCount}', Icons.star_outline_rounded, const Color(0xFFCB8B18)),
            _statCard('Departments', '${items.map((e) => e.department).where((e) => e.isNotEmpty).toSet().length}', Icons.apartment_rounded, const Color(0xFF159A79)),
          ];
          return GridView.count(crossAxisCount: count, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: count == 2 ? 1.8 : 1.45,
            children: cards);
        }),
        const SizedBox(height: 22),
        const Text('Department overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
        const SizedBox(height: 10),
        ..._countRows(items.map((e) => e.department).where((v) => v.trim().isNotEmpty).toList()),
        const SizedBox(height: 18),
        const Text('Employees by job role', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
        const SizedBox(height: 10),
        ..._countRows(items.map((e) => e.title).where((v) => v.trim().isNotEmpty).toList()),
        const SizedBox(height: 18),
        Row(children: [
          const Expanded(child: Text('Recently viewed profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy))),
          TextButton(onPressed: () => setState(() => selectedTab = 1), child: const Text('View people')),
        ]),
        if (store.recentProfiles.isEmpty) const Text('Profiles you open will appear here.', style: TextStyle(color: Colors.blueGrey)),
        ...store.recentProfiles.take(4).map((e) => EmployeeTile(employee: e, starred: store.isStarred(e.id),
          onTap: () => _openProfile(e), onStar: () => store.toggleStar(e))),
        const SizedBox(height: 18),
        const Text('Recently added or updated', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
        const SizedBox(height: 10),
        if (store.recentActivity.isEmpty) const Text('New or edited employee records will appear here.', style: TextStyle(color: Colors.blueGrey)),
        ...store.recentActivity.take(5).map((e) => ListTile(
          contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history, color: blue),
          title: Text(e.fullName), subtitle: Text('${store.activityFor(e.id)?.split('|').last ?? 'Changed'} · ${e.department}'),
          onTap: () => _openProfile(e),
        )),
        const SizedBox(height: 24),
        Row(children: [
          const Expanded(child: Text('Recently listed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy))),
          TextButton(onPressed: () => setState(() => selectedTab = 1), child: const Text('View all')),
        ]),
        if (store.loading && items.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (store.error != null) _errorBanner(store.error!),
        ...items.take(5).map((e) => EmployeeTile(employee: e, starred: store.isStarred(e.id),
          onTap: () => _openProfile(e), onStar: () => store.toggleStar(e))),
      ]),
    );
  }

  List<Widget> _countRows(List<String> values) {
    final counts = <String, int>{};
    for (final value in values) { counts[value] = (counts[value] ?? 0) + 1; }
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return [const Text('No data available.', style: TextStyle(color: Colors.blueGrey))];
    return entries.map((entry) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 120, child: LinearProgressIndicator(value: entry.value / values.length, minHeight: 7)),
        const SizedBox(width: 12),
        SizedBox(width: 24, child: Text('${entry.value}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    )).toList();
  }

  Future<void> _exportCsv() async {
    final rows = <List<String>>[
      ['ID', 'First name', 'Last name', 'Email', 'Phone', 'Job title', 'Department', 'City', 'State', 'Country'],
      ...visibleEmployees.map((e) => [ '${e.id}', e.firstName, e.lastName, e.email, e.phone, e.title, e.department, e.city, e.state, e.country ])
    ];
    String escape(String value) => '"${value.replaceAll('"', '""')}"';
    final csv = rows.map((row) => row.map(escape).join(',')).join('\r\n');
    try {
      await FileSaver.instance.saveFile(
        name: 'teambook_employees_${DateTime.now().millisecondsSinceEpoch}',
        bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]),
        ext: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV export ready.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    }
  }

  Widget _statCard(String title, String value, IconData icon, Color color) => Card(
    child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color)),
      const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: navy)),
      Text(title, style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
    ])),
  );

  Widget _directory({bool starred = false}) {
    final list = starred
      ? visibleEmployees.where((e) => store.isStarred(e.id)).toList()
      : visibleEmployees;
    final departments = store.employees.map((e) => e.department.trim()).where((d) => d.isNotEmpty).toSet().toList()..sort();
    final roles = store.employees.map((e) => e.title.trim()).where((d) => d.isNotEmpty).toSet().toList()..sort();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
      Text(starred ? 'Starred people' : 'Employee directory', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 6),
      Text(starred ? 'Your saved team members.' : (widget.role == 'admin' ? 'Search, filter and manage your team.' : 'Search, filter and view your colleagues.' ), style: const TextStyle(color: Colors.blueGrey)),
      const SizedBox(height: 18),
      TextField(
        onChanged: (v) => setState(() => query = v),
        decoration: const InputDecoration(hintText: 'Search name, email, phone, role or department', prefixIcon: Icon(Icons.search),),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: departmentFilter,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Filter by department', prefixIcon: Icon(Icons.apartment_outlined)),
        items: ['All departments', ...departments].map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (value) => setState(() => departmentFilter = value ?? 'All departments'),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: roles.contains(roleFilter) || roleFilter == 'All job roles' ? roleFilter : 'All job roles',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Filter by job role', prefixIcon: Icon(Icons.work_outline)),
        items: ['All job roles', ...roles].map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (value) => setState(() => roleFilter = value ?? 'All job roles'),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: sortBy,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sort employees', prefixIcon: Icon(Icons.sort_by_alpha)),
        items: const [DropdownMenuItem(value: 'nameAsc', child: Text('Name: A–Z')), DropdownMenuItem(value: 'nameDesc', child: Text('Name: Z–A')), DropdownMenuItem(value: 'department', child: Text('Department: A–Z'))],
        onChanged: (value) => setState(() => sortBy = value ?? 'nameAsc'),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Text('${list.length} people', style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
        const Spacer(),
        TextButton.icon(onPressed: () => setState(() { query = ''; departmentFilter = 'All departments'; roleFilter = 'All job roles'; sortBy = 'nameAsc'; onlyStarred = starred; }), icon: const Icon(Icons.restart_alt), label: const Text('Clear filters')),
        IconButton(tooltip: 'Export filtered employees to CSV', onPressed: _exportCsv, icon: const Icon(Icons.file_download_outlined)),
      ]),
      if (store.error != null) _errorBanner(store.error!),
      if (store.loading && store.employees.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
      if (list.isEmpty && !store.loading) Padding(padding: const EdgeInsets.all(30), child: Column(children: [
        const Icon(Icons.person_search_outlined, size: 52, color: Colors.blueGrey),
        const SizedBox(height: 12),
        Text(starred ? 'No starred employees yet' : 'No employees found', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 6),
        Text(starred ? 'Tap the star on a profile to save it here.' : 'Try another search or add a new employee.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey)),
      ])),
      ...list.map((e) => EmployeeTile(employee: e, starred: store.isStarred(e.id),
        onTap: () => _openProfile(e), onStar: () => store.toggleStar(e))),
    ]);
  }

  bool _matches(Employee e) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || '${e.fullName} ${e.email} ${e.phone} ${e.department} ${e.title} ${e.location}'.toLowerCase().contains(q);
  }

  Widget _settings() => ListView(padding: const EdgeInsets.all(22), children: [
    const Text('Settings', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: navy)),
    const SizedBox(height: 6),
    const Text('App information and local data controls.', style: TextStyle(color: Colors.blueGrey)),
    const SizedBox(height: 20),
    Card(child: ListTile(leading: const Icon(Icons.cloud_outlined, color: blue), title: const Text('Employee data source'), subtitle: const Text('DummyJSON public demo API'))),
    Card(child: const ListTile(leading: Icon(Icons.save_outlined, color: blue), title: Text('Local persistence'), subtitle: Text('New employees, edits, deleted items and starred people are saved on this device.'))),
    Card(child: const ListTile(leading: Icon(Icons.info_outline, color: blue), title: Text('About TeamBook'), subtitle: Text('Flutter employee directory demo · Version 1.0.0'))),
    Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(widget.displayName),
      subtitle: Text('${widget.email} · ${widget.role.toUpperCase()}'),
      trailing: Icon(widget.role == 'admin' ? Icons.admin_panel_settings_outlined : Icons.verified_user_outlined, color: blue),
    )),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      onPressed: () async {
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Sign out?'),
          content: const Text('You can sign in again with your TeamBook account.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
          ],
        ));
        if (ok == true) await widget.onLogout();
      },
      icon: const Icon(Icons.logout),
      label: const Text('Sign out'),
    ),
    const SizedBox(height: 16),
    if (widget.role == 'admin') OutlinedButton.icon(onPressed: () async {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Clear local app data?'),
        content: const Text('This removes locally created employees, edits, hidden employees and starred selections from this device. Remote sample employees will load again.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear data'))],
      ));
      if (ok == true) {
        await store.clearLocalData();
        await store.refresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local data cleared.')));
      }
    }, icon: const Icon(Icons.delete_outline), label: const Text('Clear local data')),
  ]);

  Widget _errorBanner(String message) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFFFF3E8), borderRadius: BorderRadius.circular(12)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.wifi_off_outlined, color: Color(0xFF9A4D00)),
      const SizedBox(width: 8), Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF794000)))),
      TextButton(onPressed: store.refresh, child: const Text('Retry')),
    ]),
  );
}

class EmployeeTile extends StatelessWidget {
  final Employee employee;
  final bool starred;
  final VoidCallback onTap, onStar;
  const EmployeeTile({super.key, required this.employee, required this.starred, required this.onTap, required this.onStar});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(13), child: Row(children: [
        Avatar(employee: employee, size: 52),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(employee.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
          const SizedBox(height: 3),
          Text(employee.title.isEmpty ? 'Team member' : employee.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(employee.department.isEmpty ? employee.email : employee.department, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ])),
        IconButton(onPressed: onStar, tooltip: starred ? 'Remove from starred' : 'Add to starred',
          icon: Icon(starred ? Icons.star_rounded : Icons.star_outline_rounded, color: starred ? const Color(0xFFCB8B18) : Colors.blueGrey)),
        const Icon(Icons.chevron_right_rounded, color: Colors.blueGrey),
      ])),
    ),
  );
}

class Avatar extends StatelessWidget {
  final Employee employee;
  final double size;
  const Avatar({super.key, required this.employee, this.size = 80});
  @override
  Widget build(BuildContext context) {
    final initials = '${employee.firstName.isNotEmpty ? employee.firstName[0] : ''}${employee.lastName.isNotEmpty ? employee.lastName[0] : ''}'.toUpperCase();
    return ClipRRect(borderRadius: BorderRadius.circular(size * .28),
      child: Container(width: size, height: size, color: const Color(0xFFEAF0FF),
        child: employee.image.isNotEmpty
          ? Image.network(employee.image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(initials, style: TextStyle(color: navy, fontWeight: FontWeight.w800, fontSize: size * .28))))
          : Center(child: Text(initials, style: TextStyle(color: navy, fontWeight: FontWeight.w800, fontSize: size * .28))),
      ),
    );
  }
}

Future<void> _launchContact(BuildContext context, String value) async {
  final uri = Uri.parse(value);
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No compatible app was found.')));
    }
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the contact app.')));
  }
}

Future<void> _copyContact(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
}

class EmployeeProfilePage extends StatelessWidget {
  final Employee employee;
  final EmployeeStore store;
  final bool isAdmin;
  final Future<void> Function(Employee) onEdit;
  const EmployeeProfilePage({super.key, required this.employee, required this.store, required this.isAdmin, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final e = store.employees.where((x) => x.id == employee.id).firstOrNull ?? employee;
    return Scaffold(
      appBar: AppBar(title: const Text('Employee profile'), actions: [
        if (isAdmin) IconButton(tooltip: 'Edit employee', onPressed: () => onEdit(e), icon: const Icon(Icons.edit_outlined)),
        if (isAdmin) PopupMenuButton<String>(onSelected: (v) async {
          if (v == 'delete') {
            final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Remove employee?'), content: Text('Remove ${e.fullName} from this directory on this device?'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))],
            ));
            if (yes == true && context.mounted) {
              await store.remove(e);
              if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee removed from this device.'))); }
            }
          }
        }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove employee'))]),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey.shade200)),
          child: Column(children: [
            Avatar(employee: e, size: 104), const SizedBox(height: 16),
            Text(e.fullName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: navy)),
            const SizedBox(height: 5),
            Text(e.title.isEmpty ? 'Team member' : e.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey)),
            if (e.department.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Chip(label: Text(e.department))),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: () => store.toggleStar(e), icon: Icon(store.isStarred(e.id) ? Icons.star : Icons.star_outline),
              label: Text(store.isStarred(e.id) ? 'Starred' : 'Add to starred')),
            const SizedBox(height: 8),
            if (e.isLocal) const Text('Saved on this device', style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 18),
        _section('Quick contact actions', [
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed: e.phone.trim().isEmpty ? null : () => _launchContact(context, 'tel:${e.phone.replaceAll(RegExp(r'[^+0-9]'), '')}'),
              icon: const Icon(Icons.call_outlined), label: const Text('Call')),
            FilledButton.tonalIcon(onPressed: e.email.trim().isEmpty ? null : () => _launchContact(context, 'mailto:${e.email}'),
              icon: const Icon(Icons.email_outlined), label: const Text('Email')),
            OutlinedButton.icon(onPressed: e.phone.trim().isEmpty ? null : () => _copyContact(context, e.phone),
              icon: const Icon(Icons.copy), label: const Text('Copy phone')),
            OutlinedButton.icon(onPressed: e.email.trim().isEmpty ? null : () => _copyContact(context, e.email),
              icon: const Icon(Icons.copy), label: const Text('Copy email')),
            OutlinedButton.icon(onPressed: () => Share.share('${e.fullName}\\n${e.title}\\n${e.department}\\nPhone: ${e.phone}\\nEmail: ${e.email}'),
              icon: const Icon(Icons.share_outlined), label: const Text('Share contact')),
          ]),
        ]),
        const SizedBox(height: 14),
        _section('Contact information', [
          _detail(Icons.email_outlined, 'Email', e.email),
          _detail(Icons.phone_outlined, 'Phone', e.phone),
        ]),
        const SizedBox(height: 14),
        _section('Address', [
          _detail(Icons.home_outlined, 'Street address', e.address),
          _detail(Icons.location_city_outlined, 'City', e.city),
          _detail(Icons.map_outlined, 'State / Region', e.state),
          _detail(Icons.markunread_mailbox_outlined, 'Postal code', e.postalCode),
          _detail(Icons.public_outlined, 'Country', e.country),
        ]),
        const SizedBox(height: 20),
        if (isAdmin) FilledButton.icon(onPressed: () => onEdit(e), icon: const Icon(Icons.edit_outlined), label: const Text('Edit employee')),
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 12), ...children,
    ])),
  );

  Widget _detail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: blue, size: 20), const SizedBox(width: 10),
      SizedBox(width: 105, child: Text(label, style: const TextStyle(color: Colors.blueGrey, fontSize: 12))),
      Expanded(child: Text(value.isEmpty ? 'Not provided' : value, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );
}

class EmployeeFormPage extends StatefulWidget {
  final EmployeeStore store;
  final Employee? employee;
  const EmployeeFormPage({super.key, required this.store, this.employee});
  @override
  State<EmployeeFormPage> createState() => _EmployeeFormPageState();
}

class _EmployeeFormPageState extends State<EmployeeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = {};
  bool saving = false;
  bool get editing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    final values = <String, String>{
      'firstName': e?.firstName ?? '', 'lastName': e?.lastName ?? '',
      'email': e?.email ?? '', 'phone': e?.phone ?? '', 'title': e?.title ?? '',
      'department': e?.department ?? '', 'address': e?.address ?? '',
      'city': e?.city ?? '', 'state': e?.state ?? '', 'postalCode': e?.postalCode ?? '',
      'country': e?.country ?? '', 'image': e?.image ?? '',
    };
    for (final entry in values.entries) { c[entry.key] = TextEditingController(text: entry.value); }
  }

  @override
  void dispose() { for (final v in c.values) { v.dispose(); } super.dispose(); }

  String? _required(String? v) => v == null || v.trim().isEmpty ? 'This field is required' : null;
  String? _email(String? v) {
    if (_required(v) != null) return 'Email is required';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim()) ? null : 'Enter a valid email';
  }

  Widget _field(String key, String label, {bool required = false, TextInputType? keyboard, int lines = 1, String? Function(String?)? validator}) =>
    Padding(padding: const EdgeInsets.only(bottom: 14), child: TextFormField(
      controller: c[key], keyboardType: keyboard, maxLines: lines,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: lines > 1),
      validator: validator ?? (required ? _required : null),
    ));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final enteredEmail = c['email']!.text.trim().toLowerCase();
    final duplicate = widget.store.employees.any((e) =>
      e.email.trim().toLowerCase() == enteredEmail && e.id != (widget.employee?.id ?? 0));
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An employee with this email already exists.')));
      return;
    }
    setState(() => saving = true);
    try {
      final old = widget.employee;
      final draft = Employee(
        id: old?.id ?? 0,
        firstName: c['firstName']!.text.trim(), lastName: c['lastName']!.text.trim(),
        email: c['email']!.text.trim(), phone: c['phone']!.text.trim(),
        image: c['image']!.text.trim(), title: c['title']!.text.trim(),
        department: c['department']!.text.trim(), address: c['address']!.text.trim(),
        city: c['city']!.text.trim(), state: c['state']!.text.trim(),
        postalCode: c['postalCode']!.text.trim(), country: c['country']!.text.trim(),
        isLocal: old?.isLocal ?? true,
      );
      Employee result;
      if (editing) {
        await widget.store.update(draft);
        result = draft;
      } else {
        result = await widget.store.add(draft);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(editing ? 'Employee updated successfully.' : 'Employee added successfully.')));
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save employee: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(editing ? 'Edit employee' : 'Add employee')),
    body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.badge_outlined, size: 34, color: navy), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(editing ? 'Update team member' : 'Create team member', style: const TextStyle(fontWeight: FontWeight.w800, color: navy, fontSize: 17)),
            const SizedBox(height: 3), const Text('Fields marked required must be completed.', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
          ])),
        ])),
      const SizedBox(height: 22),
      const Text('Personal details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 12),
      _field('firstName', 'First name *', required: true),
      _field('lastName', 'Last name *', required: true),
      _field('email', 'Work email *', keyboard: TextInputType.emailAddress, validator: _email),
      _field('phone', 'Phone number', keyboard: TextInputType.phone),
      _field('image', 'Profile image URL (optional)', keyboard: TextInputType.url),
      const SizedBox(height: 8),
      const Text('Work details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 12),
      _field('title', 'Job title *', required: true),
      _field('department', 'Department *', required: true),
      const SizedBox(height: 8),
      const Text('Address', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
      const SizedBox(height: 12),
      _field('address', 'Street address', lines: 2),
      _field('city', 'City'),
      _field('state', 'State / Region'),
      _field('postalCode', 'Postal code', keyboard: TextInputType.text),
      _field('country', 'Country'),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: saving ? null : _save,
        icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
        label: Text(saving ? 'Saving...' : editing ? 'Save changes' : 'Add employee'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
    ])),
  );
}
