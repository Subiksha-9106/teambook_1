import 'package:flutter_test/flutter_test.dart';
import 'package:teambook/main.dart';

void main() {
  test('Employee model builds full name and location', () {
    const employee = Employee(
      id: 1, firstName: 'Ada', lastName: 'Lovelace', email: 'ada@example.com',
      phone: '', image: '', title: 'Engineer', department: 'Technology',
      address: '10 Main Street', city: 'Chennai', state: 'Tamil Nadu',
      postalCode: '600001', country: 'India',
    );
    expect(employee.fullName, 'Ada Lovelace');
    expect(employee.location, 'Chennai, Tamil Nadu, India');
  });
}
