import '../models/doc_entry.dart';
import '../models/employee.dart';
import '../models/fleet_settings.dart';
import '../utils/doc_catalog.dart';
import '../utils/role.dart' as role_utils;

DocEntry? _catalogEntry(String id) {
  for (final doc in docCatalog) {
    if (doc.id == id) return doc;
  }
  return null;
}

/// Fleet floor guides visible on mobile (mechanic + reporter).
List<DocEntry> fleetGuidesFor(Employee? employee, FleetSettings settings) {
  final guides = <DocEntry>[];
  void add(String id) {
    final entry = _catalogEntry(id);
    if (entry != null) guides.add(entry);
  }

  if (role_utils.isFleetMechanic(employee, settings)) {
    add('fleet_mechanic_guide');
  }
  if (role_utils.isFleetReporter(employee, settings)) {
    add('fleet_reporter_guide');
  }
  if (guides.isEmpty) {
    add('fleet_user_guide');
  }
  return guides;
}

/// Primary guide for the help button — most relevant single role.
DocEntry? primaryFleetGuideFor(Employee? employee, FleetSettings settings) {
  final guides = fleetGuidesFor(employee, settings);
  if (guides.isEmpty) return null;
  if (guides.length == 1) return guides.first;
  if (role_utils.isFleetMechanic(employee, settings)) {
    return _catalogEntry('fleet_mechanic_guide') ?? guides.first;
  }
  if (role_utils.isFleetReporter(employee, settings)) {
    return _catalogEntry('fleet_reporter_guide') ?? guides.first;
  }
  return guides.first;
}