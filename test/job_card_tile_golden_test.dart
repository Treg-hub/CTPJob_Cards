import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/job_card.dart';
import 'package:ctp_job_cards/theme/app_theme.dart';
import 'package:ctp_job_cards/widgets/job_card_tile.dart';

ThemeData _previewTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: kBrandOrange,
      onPrimary: Colors.black,
      surface: Colors.white,
      onSurface: Colors.black87,
      onSurfaceVariant: Colors.black54,
      outlineVariant: Color(0xFFE0E0E0),
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    extensions: const [lightAppColors],
  );
}

JobCard _sampleJob() {
  return JobCard(
    jobCardNumber: 1847,
    department: 'Production',
    area: 'Flexo Line 2',
    machine: 'Press A',
    part: 'Main Drive Roller',
    type: JobType.mechanicalElectrical,
    priority: 3,
    operator: 'J. Smith',
    description: 'Bearing noise on main drive roller — intermittent grinding',
    comments: 'Checked lubrication levels\n\nNeeds replacement ASAP',
    notes: 'Spare bearing in store room B',
    correctiveAction: 'Ordered replacement part #BR-4421',
    status: JobStatus.inProgress,
    assignedNames: const ['Mike Smith', 'Jane Doe'],
    photos: const [{}, {}],
    createdAt: DateTime(2026, 6, 30, 14, 30),
  );
}

void main() {
  testWidgets('JobCardTile preview golden', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: _previewTheme(),
        home: Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                JobCardTile(job: _sampleJob()),
                JobCardTile(
                  job: JobCard(
                    jobCardNumber: 2103,
                    department: 'Pre Press',
                    area: 'Plate Room',
                    machine: 'CTP 3',
                    part: 'Laser Head',
                    type: JobType.electrical,
                    priority: 5,
                    operator: 'A. Jones',
                    description: 'Laser output dropping — urgent production hold',
                    status: JobStatus.open,
                    createdAt: DateTime(2026, 7, 1, 9, 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/job_card_tile_preview.png'),
    );
  });
}