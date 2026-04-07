import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/job_card.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Employee operations
  Future<Employee?> getEmployee(String clockNo) async {
    try {
      final doc = await _firestore.collection('employees').doc(clockNo).get();
      if (!doc.exists) return null;
      return Employee.fromFirestore(doc.data()!, clockNo);
    } catch (e) {
      throw Exception('Failed to load employee: $e');
    }
  }

  Future<void> updateEmployee(Employee employee) async {
    try {
      await _firestore.collection('employees').doc(employee.clockNo).set(
            employee.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      throw Exception('Failed to update employee: $e');
    }
  }

  Future<List<Employee>> getAllEmployees() async {
    try {
      final snapshot = await _firestore.collection('employees').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Employee.fromFirestore(data, doc.id);
      }).toList();
    } catch (e) {
      throw Exception('Failed to load employees: $e');
    }
  }

  Stream<List<Employee>> getEmployeesStream() {
    return _firestore.collection('employees').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Employee.fromFirestore(data, doc.id);
      }).toList();
    });
  }

  // Job Card operations
  Future<void> createJobCard(JobCard jobCard) async {
    try {
      await _firestore.collection('job_cards').add(jobCard.toFirestore());
    } catch (e) {
      throw Exception('Failed to create job card: $e');
    }
  }

  Future<void> updateJobCard(String jobCardId, JobCard jobCard) async {
    try {
      await _firestore.collection('job_cards').doc(jobCardId).update(jobCard.toFirestore());
    } catch (e) {
      throw Exception('Failed to update job card: $e');
    }
  }

  Stream<List<JobCard>> getOpenJobCards() {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  Stream<List<JobCard>> getAssignedJobCards(String employeeClockNo) {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'open')
        .where('assignedTo', isEqualTo: employeeClockNo)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  Stream<List<JobCard>> getCompletedJobCards() {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  Future<List<String>> getDepartmentsForJobCards(String status) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: status)
          .get();

      final departments = <String>{};
      for (var doc in snapshot.docs) {
        final dept = doc['department'] as String?;
        if (dept != null && dept.isNotEmpty) departments.add(dept);
      }
      return departments.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load departments: $e');
    }
  }

  Future<List<String>> getAreasForJobCards(String status, String department) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: status)
          .where('department', isEqualTo: department)
          .get();

      final areas = <String>{};
      for (var doc in snapshot.docs) {
        final area = doc['area'] as String?;
        if (area != null && area.isNotEmpty) areas.add(area);
      }
      return areas.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load areas: $e');
    }
  }

  Future<List<String>> getMachinesForJobCards(String status, String department, String area) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: status)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .get();

      final machines = <String>{};
      for (var doc in snapshot.docs) {
        final machine = doc['machine'] as String?;
        if (machine != null && machine.isNotEmpty) machines.add(machine);
      }
      return machines.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load machines: $e');
    }
  }

  Future<List<String>> getPreviousParts(String department, String area, String machine) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .get();

      final parts = snapshot.docs
          .map((doc) => (doc.data()['part'] as String? ?? '').trim())
          .where((part) => part.isNotEmpty)
          .toSet()
          .toList();
      return parts;
    } catch (e) {
      throw Exception('Failed to load previous parts: $e');
    }
  }

  // Factory structure operations
  Future<Map<String, dynamic>> getFactoryStructure() async {
    try {
      final doc = await _firestore.collection('structures').doc('factory').get();
      return doc.data()?['data'] as Map<String, dynamic>? ?? {};
    } catch (e) {
      throw Exception('Failed to load factory structure: $e');
    }
  }

  Future<void> updateFactoryStructure(Map<String, dynamic> structure) async {
    try {
      await _firestore.collection('structures').doc('factory').set({'data': structure});
    } catch (e) {
      throw Exception('Failed to update factory structure: $e');
    }
  }

  // Settings operations
  Future<void> initializeSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('app').get();
      if (!doc.exists) {
        await _firestore.collection('settings').doc('app').set({
          'switchUserPassword': 'admin123',
          'initialized': true,
        });
      }
    } catch (e) {
      throw Exception('Failed to initialize settings: $e');
    }
  }

  Future<String> getSwitchUserPassword() async {
    try {
      final doc = await _firestore.collection('settings').doc('app').get();
      return doc.data()?['switchUserPassword'] as String? ?? 'admin123';
    } catch (e) {
      throw Exception('Failed to get switch user password: $e');
    }
  }

  Future<void> updateSwitchUserPassword(String newPassword) async {
    try {
      await _firestore.collection('settings').doc('app').set({
        'switchUserPassword': newPassword,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update switch user password: $e');
    }
  }

  // Authentication persistence
  Future<void> saveLoggedInEmployee(String clockNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loggedInClockNo', clockNo);
  }

  Future<String?> getLoggedInEmployeeClockNo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('loggedInClockNo');
  }

  Future<void> clearLoggedInEmployee() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedInClockNo');
  }
}