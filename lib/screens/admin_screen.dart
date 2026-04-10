import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/employee.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    _loadEmployees();
    _loadStructure();
    _loadSettings();
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
    super.dispose();
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
      _structure = await _firestoreService.getFactoryStructure();
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _employeeSearchController,
            decoration: const InputDecoration(
              labelText: 'Search Employees',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() => _filterEmployees()),
          ),
          const SizedBox(height: 16),
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
                return ListView.builder(
                  itemCount: _filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final emp = _filteredEmployees[index];
                    return Card(
                      child: ListTile(
                        title: Text(emp.displayName),
                        subtitle: Text('${emp.department} - ${emp.isOnSite ? 'On Site' : 'Off Site'}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEmployeeDialog(emp),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteEmployee(emp.clockNo),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
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
    return Padding(
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
}