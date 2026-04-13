import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'dart:html' as html;
import '../services/firestore_service.dart';
import '../models/employee.dart';
import 'copper_storage_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  // Employees tab
  final TextEditingController _employeeSearchController = TextEditingController();
  List<Employee> _allEmployees = [];
  List<Employee> _filteredEmployees = [];

  // Structures tab (keep old controllers)
  final TextEditingController deptController = TextEditingController();
  final TextEditingController areaController = TextEditingController();
  final TextEditingController machineController = TextEditingController();
  final TextEditingController structureSearchController = TextEditingController();

  String? selectedDeptForArea;
  String? selectedDeptForMachine;
  String? selectedAreaForMachine;
  Map<String, dynamic> _structure = {};

  // Settings tab
  final TextEditingController _passwordController = TextEditingController();
  String _currentPassword = '';
  String? _currentClockNo;

  // Spreadsheet state
  Set<int> _selectedRows = {};
  int? _editingIndex;
  final TextEditingController _clockNoController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _fcmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    print('AdminScreen initState'); // Debug
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _loadEmployees();
    _loadStructure();
    _loadSettings();
    _loadCurrentClockNo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _employeeSearchController.dispose();
    deptController.dispose();
    areaController.dispose();
    machineController.dispose();
    structureSearchController.dispose();
    _passwordController.dispose();
    _clockNoController.dispose();
    _nameController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _fcmController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _normalizeStructure(Map<String, dynamic> structure) {
    final normalized = <String, dynamic>{};
    structure.forEach((dept, areas) {
      if (areas is Map) {
        final normalizedAreas = <String, dynamic>{};
        (areas as Map<String, dynamic>).forEach((area, machines) {
          if (machines is List) {
            normalizedAreas[area] = machines;
          } else if (machines is String) {
            normalizedAreas[area] = [machines];
          } else {
            normalizedAreas[area] = [];
          }
        });
        normalized[dept] = normalizedAreas;
      } else {
        normalized[dept] = {};
      }
    });
    return normalized;
  }

  Future<void> _loadEmployees() async {
    try {
      _allEmployees = await _firestoreService.getAllEmployees();
      _filterEmployees();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading employees: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterEmployees() {
    final query = _employeeSearchController.text.toLowerCase();
    _filteredEmployees = _allEmployees.where((emp) =>
      emp.name.toLowerCase().contains(query) ||
      emp.department.toLowerCase().contains(query) ||
      emp.position.toLowerCase().contains(query) ||
      emp.clockNo.toLowerCase().contains(query)
    ).toList();
  }

  Future<void> _loadStructure() async {
    try {
      _structure = _normalizeStructure(await _firestoreService.getFactoryStructure());
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading structure: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      _currentPassword = await _firestoreService.getSwitchUserPassword();
      _passwordController.text = _currentPassword;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    print('Debug: Loaded ClockNo: $_currentClockNo'); // Debug
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Manage Collections'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.black,
          tabs: const [
            Tab(text: 'Employees'),
            Tab(text: 'Structures'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmployeesTab(),
          _buildStructuresTab(),
          _buildSettingsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0 ? FloatingActionButton(
        onPressed: () => _showEmployeeDialog(),
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  Widget _buildEmployeesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _employeeSearchController,
                  decoration: const InputDecoration(
                    labelText: 'Search Employees',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() => _filterEmployees()),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _exportTemplate,
                icon: const Icon(Icons.download),
                label: const Text('Export Template'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.upload),
                label: const Text('Import CSV'),
              ),
              if (_selectedRows.isNotEmpty) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _bulkDelete,
                  icon: const Icon(Icons.delete, color: Colors.white),
                  label: const Text('Delete Selected'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Employee>>(
            stream: _firestoreService.getEmployeesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && _allEmployees.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final employees = snapshot.data ?? _allEmployees;
              _allEmployees = employees;
              _filterEmployees();
              return SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Select')),
                      DataColumn(label: Text('Clock No')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Position')),
                      DataColumn(label: Text('Department')),
                      DataColumn(label: Text('On Site')),
                      DataColumn(label: Text('FCM Token')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: _filteredEmployees.map((emp) {
                      final index = _allEmployees.indexOf(emp);
                      final isEditing = _editingIndex == index;
                      return DataRow(
                        selected: _selectedRows.contains(index),
                        onSelectChanged: (selected) {
                          if (selected!) {
                            _selectedRows.add(index);
                          } else {
                            _selectedRows.remove(index);
                          }
                          setState(() {});
                        },
                        cells: [
                          DataCell(
                            Checkbox(
                              value: _selectedRows.contains(index),
                              onChanged: (v) {
                                if (v!) {
                                  _selectedRows.add(index);
                                } else {
                                  _selectedRows.remove(index);
                                }
                                setState(() {});
                              },
                            ),
                          ),
                          DataCell(isEditing ? TextField(controller: _clockNoController) : Text(emp.clockNo)),
                          DataCell(isEditing ? TextField(controller: _nameController) : Text(emp.name)),
                          DataCell(isEditing ? TextField(controller: _positionController) : Text(emp.position)),
                          DataCell(isEditing ? TextField(controller: _departmentController) : Text(emp.department)),
                          DataCell(
                            Checkbox(
                              value: emp.isOnSite,
                              onChanged: (v) => _firestoreService.updateEmployee(emp.copyWith(isOnSite: v ?? true)),
                            ),
                          ),
                          DataCell(isEditing ? SizedBox(width: 150, child: TextField(controller: _fcmController)) : SizedBox(width: 150, child: Text(emp.fcmToken != null ? (emp.fcmToken!.length > 100 ? '${emp.fcmToken!.substring(0, 100)}...' : emp.fcmToken!) : '', overflow: TextOverflow.ellipsis))),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(isEditing ? Icons.save : Icons.edit),
                                  onPressed: () => _toggleEdit(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteEmployee(emp.clockNo),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStructuresTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: structureSearchController,
            decoration: const InputDecoration(
              labelText: 'Search Structures',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                const Text('Current Structure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ..._buildStructureList(),
                const Divider(height: 20),
                const Text('Add New Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextField(
                  controller: deptController,
                  decoration: const InputDecoration(labelText: 'Department name'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (deptController.text.isEmpty) return;
                    try {
                      _structure[deptController.text] = {};
                      await _firestoreService.updateFactoryStructure(_structure);
                      deptController.clear();
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Department added')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error adding department: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Add Department'),
                ),
                const Divider(height: 20),
                const Text('Add New Area', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                FutureBuilder<Map<String, dynamic>>(
                  future: _firestoreService.getFactoryStructure(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    final data = snapshot.data!;
                    return Column(
                      children: [
                        const Text('Select Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: data.keys.map((dept) => ChoiceChip(
                            label: Text(dept),
                            selected: selectedDeptForArea == dept,
                            onSelected: (_) => setState(() => selectedDeptForArea = dept),
                            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                            labelStyle: selectedDeptForArea == dept ? const TextStyle(color: Colors.black) : const TextStyle(color: Colors.white),
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: areaController,
                          decoration: const InputDecoration(labelText: 'Area name'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (selectedDeptForArea == null || areaController.text.isEmpty) return;
                            try {
                              final structure = await _firestoreService.getFactoryStructure();
                              (structure[selectedDeptForArea] as Map<String, dynamic>)[areaController.text] = [];
                              await _firestoreService.updateFactoryStructure(structure);
                              areaController.clear();
                              _loadStructure();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Area added')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error adding area: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          child: const Text('Add Area'),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 20),
                const Text('Add New Machine / Part', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                FutureBuilder<Map<String, dynamic>>(
                  future: _firestoreService.getFactoryStructure(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    final data = snapshot.data!;
                    final areas = selectedDeptForMachine != null ? (data[selectedDeptForMachine] as Map<String, dynamic>? ?? {}).keys.toList() : <String>[];
                    return Column(
                      children: [
                        const Text('Select Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: data.keys.map((dept) => ChoiceChip(
                            label: Text(dept),
                            selected: selectedDeptForMachine == dept,
                            onSelected: (_) => setState(() {
                              selectedDeptForMachine = dept;
                              selectedAreaForMachine = null;
                            }),
                            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                            labelStyle: selectedDeptForMachine == dept ? const TextStyle(color: Colors.black) : const TextStyle(color: Colors.white),
                          )).toList(),
                        ),
                        if (selectedDeptForMachine != null) ...[
                          const SizedBox(height: 8),
                          const Text('Select Area', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: areas.map((area) => ChoiceChip(
                              label: Text(area),
                              selected: selectedAreaForMachine == area,
                              onSelected: (_) => setState(() => selectedAreaForMachine = area),
                              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
                              labelStyle: selectedAreaForMachine == area ? const TextStyle(color: Colors.black) : const TextStyle(color: Colors.white),
                            )).toList(),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: machineController,
                          decoration: const InputDecoration(labelText: 'Machine / Part name'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (selectedDeptForMachine == null || selectedAreaForMachine == null || machineController.text.isEmpty) return;
                            try {
                              final structure = await _firestoreService.getFactoryStructure();
                              (structure[selectedDeptForMachine]![selectedAreaForMachine] as List<dynamic>).add(machineController.text);
                              await _firestoreService.updateFactoryStructure(structure);
                              machineController.clear();
                              _loadStructure();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Machine added')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error adding machine: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          child: const Text('Add Machine / Part'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStructureList() {
    final query = structureSearchController.text.toLowerCase();
    final filteredStructure = <String, dynamic>{};
    _structure.forEach((dept, areas) {
      if (dept.toLowerCase().contains(query)) {
        filteredStructure[dept] = areas;
      } else {
        final filteredAreas = <String, dynamic>{};
        (areas as Map<String, dynamic>).forEach((area, machines) {
          if (area.toLowerCase().contains(query) || (machines as List).any((m) => m.toString().toLowerCase().contains(query))) {
            filteredAreas[area] = machines;
          }
        });
        if (filteredAreas.isNotEmpty) {
          filteredStructure[dept] = filteredAreas;
        }
      }
    });

    return filteredStructure.entries.map((deptEntry) {
      return ExpansionTile(
        title: Row(
          children: [
            Text(deptEntry.key),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteDepartment(deptEntry.key),
            ),
          ],
        ),
        children: (deptEntry.value as Map<String, dynamic>).entries.map((areaEntry) {
          return ExpansionTile(
            title: Row(
              children: [
                Text(areaEntry.key),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteArea(deptEntry.key, areaEntry.key),
                ),
              ],
            ),
            children: (areaEntry.value as List).map((machine) {
              return ListTile(
                title: Text(machine.toString()),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteMachine(deptEntry.key, areaEntry.key, machine.toString()),
                ),
              );
            }).toList(),
          );
        }).toList(),
      );
    }).toList();
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('App Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Switch User Password'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _updateSettings,
            child: const Text('Save Settings'),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Copper Storage'),
            onTap: () {
              if (_currentClockNo == '22') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CopperStorageScreen()));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Access denied. Only clock card 22 allowed.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showEmployeeDialog([Employee? employee]) {
    final isEdit = employee != null;
    final clockNoController = TextEditingController(text: employee?.clockNo ?? '');
    final nameController = TextEditingController(text: employee?.name ?? '');
    final positionController = TextEditingController(text: employee?.position ?? '');
    final departmentController = TextEditingController(text: employee?.department ?? '');
    final fcmTokenController = TextEditingController(text: employee?.fcmToken ?? '');
    bool isOnSite = employee?.isOnSite ?? true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Employee' : 'Add Employee'),
        content: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: clockNoController,
                  decoration: const InputDecoration(labelText: 'Clock No *'),
                  enabled: !isEdit,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: positionController,
                  decoration: const InputDecoration(labelText: 'Position *'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: departmentController,
                  decoration: const InputDecoration(labelText: 'Department *'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: fcmTokenController,
                  decoration: const InputDecoration(labelText: 'FCM Token'),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('On Site'),
                  value: isOnSite,
                  onChanged: (value) => setState(() => isOnSite = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (clockNoController.text.isEmpty || nameController.text.isEmpty || positionController.text.isEmpty || departmentController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Required fields missing'), backgroundColor: Colors.red),
                );
                return;
              }
              try {
                final emp = Employee(
                  clockNo: clockNoController.text,
                  name: nameController.text,
                  position: positionController.text,
                  department: departmentController.text,
                  fcmToken: fcmTokenController.text.isEmpty ? null : fcmTokenController.text,
                  isOnSite: isOnSite,
                  fcmTokenUpdatedAt: employee?.fcmTokenUpdatedAt,
                );
                if (isEdit) {
                  await _firestoreService.updateEmployee(emp);
                } else {
                  await _firestoreService.createEmployee(emp);
                }
                Navigator.pop(context);
                _loadEmployees();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Employee ${isEdit ? 'updated' : 'added'}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _deleteEmployee(String clockNo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _firestoreService.deleteEmployee(clockNo);
        _loadEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Employee deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _deleteDepartment(String dept) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Department'),
        content: const Text('This will delete all areas and machines in this department. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        _structure.remove(dept);
        await _firestoreService.updateFactoryStructure(_structure);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Department deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _deleteArea(String dept, String area) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Area'),
        content: const Text('This will delete all machines in this area. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        (_structure[dept] as Map).remove(area);
        await _firestoreService.updateFactoryStructure(_structure);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Area deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _deleteMachine(String dept, String area, String machine) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Machine'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final machines = _structure[dept][area] as List;
        machines.remove(machine);
        await _firestoreService.updateFactoryStructure(_structure);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Machine deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _updateSettings() async {
    try {
      await _firestoreService.updateSwitchUserPassword(_passwordController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _parseBool(String value) {
    final lower = value.toLowerCase();
    return lower == 'true' || lower == '1' || lower == 'yes' || lower == 'on';
  }

  void _exportTemplate() {
    final csv = const ListToCsvConverter().convert([
      ['clockNo', 'name', 'position', 'department', 'isOnSite', 'fcmToken'],
      ['', '', '', '', 'true', '']
    ]);
    if (kIsWeb) {
      final blob = html.Blob([csv], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)..download = 'employees_template.csv'..click();
      html.Url.revokeObjectUrl(url);
    } else {
      Share.share(csv, subject: 'Employees Template');
    }
  }

  void _importCsv() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null) {
      final file = result.files.first;
      String csvString;
      if (file.bytes != null) {
        csvString = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        csvString = await File(file.path!).readAsString();
      } else {
        return;
      }
      final csvTable = const CsvToListConverter().convert(csvString);
      if (csvTable.isEmpty || csvTable[0].length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid CSV format: found ${csvTable.isEmpty ? 0 : csvTable[0].length} columns, expected at least 6')));
        return;
      }
      final headers = csvTable[0].map((e) => e.toString().trim().toLowerCase()).toList();
      final expectedHeaders = ['clockno', 'name', 'position', 'department', 'isonsite', 'fcmtoken'];
      if (!expectedHeaders.every((h) => headers.contains(h))) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid headers: expected clockNo, name, position, department, isOnSite, fcmToken')));
        return;
      }
      final rows = csvTable.skip(1).map((row) => {
        'clockNo': row[headers.indexOf('clockno')].toString().trim(),
        'name': row[headers.indexOf('name')].toString().trim(),
        'position': row[headers.indexOf('position')].toString().trim(),
        'department': row[headers.indexOf('department')].toString().trim(),
        'isOnSite': _parseBool(row[headers.indexOf('isonsite')].toString().trim()),
        'fcmToken': row[headers.indexOf('fcmtoken')].toString().trim().isEmpty ? null : row[headers.indexOf('fcmtoken')].toString().trim(),
      }).toList();
      bool deleteAll = false;
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Preview Import'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  CheckboxListTile(
                    title: const Text('Delete all existing employees first'),
                    value: deleteAll,
                    onChanged: (v) => setState(() => deleteAll = v ?? false),
                  ),
                  Expanded(
                    child: ListView(
                      children: rows.map((row) => ListTile(
                        title: Text('${row['clockNo']} - ${row['name']}'),
                        subtitle: Text('${row['position']} - ${row['department']}'),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  if (deleteAll) {
                    await _firestoreService.deleteAllEmployees();
                  }
                  for (final row in rows) {
                    final emp = Employee(
                      clockNo: row['clockNo'] as String,
                      name: row['name'] as String,
                      position: row['position'] as String,
                      department: row['department'] as String,
                      isOnSite: row['isOnSite'] as bool,
                      fcmToken: row['fcmToken'] as String?,
                    );
                    try {
                      await _firestoreService.createEmployee(emp);
                    } catch (e) {
                      // ignore duplicates
                    }
                  }
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import completed')));
                },
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _toggleEdit(int index) {
    if (_editingIndex == index) {
      // save
      final emp = _allEmployees[index];
      final updatedEmp = emp.copyWith(
        clockNo: _clockNoController.text,
        name: _nameController.text,
        position: _positionController.text,
        department: _departmentController.text,
        fcmToken: _fcmController.text.isEmpty ? null : _fcmController.text,
      );
      _firestoreService.updateEmployee(updatedEmp);
      _editingIndex = null;
    } else {
      _editingIndex = index;
      final emp = _allEmployees[index];
      _clockNoController.text = emp.clockNo;
      _nameController.text = emp.name;
      _positionController.text = emp.position;
      _departmentController.text = emp.department;
      _fcmController.text = emp.fcmToken ?? '';
    }
    setState(() {});
  }

  void _bulkDelete() async {
    final toDelete = _selectedRows.map((i) => _allEmployees[i].clockNo).toList();
    for (final clockNo in toDelete) {
      await _firestoreService.deleteEmployee(clockNo);
    }
    _selectedRows.clear();
    setState(() {});
  }
}



