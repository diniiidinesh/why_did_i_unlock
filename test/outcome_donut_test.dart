import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/insights/outcome_donut.dart';

void main() {
  testWidgets('renders a legend entry with percentage for each slice', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OutcomeDonut(
          slices: [
            DonutSlice(label: 'Done', value: 3, color: Colors.green),
            DonutSlice(label: 'Abandoned', value: 1, color: Colors.red),
          ],
        ),
      ),
    ));
    await tester.pump();

    // 3 of 4 -> 75%, 1 of 4 -> 25%.
    expect(find.text('Done · 75%'), findsOneWidget);
    expect(find.text('Abandoned · 25%'), findsOneWidget);
    expect(find.text('No data yet'), findsNothing);
  });

  testWidgets('renders centerLabel inside the ring when provided', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OutcomeDonut(
          slices: [DonutSlice(label: 'Done', value: 5, color: Colors.green)],
          centerLabel: '5',
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('empty slice list renders the empty state, not a crash', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OutcomeDonut(slices: []),
      ),
    ));
    await tester.pump();

    expect(find.text('No data yet'), findsOneWidget);
  });

  testWidgets('slices that sum to zero also render the empty state', (tester) async {
    // A real shape this can take: every count-bearing slice legitimately
    // zero (e.g. a windowed query with no rows yet) rather than an empty
    // list — must not divide by zero in the painter or the legend.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OutcomeDonut(
          slices: [
            DonutSlice(label: 'Done', value: 0, color: Colors.green),
            DonutSlice(label: 'Abandoned', value: 0, color: Colors.red),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('No data yet'), findsOneWidget);
  });

  testWidgets('a single non-zero slice among zero slices still renders correctly', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OutcomeDonut(
          slices: [
            DonutSlice(label: 'Done', value: 2, color: Colors.green),
            DonutSlice(label: 'Abandoned', value: 0, color: Colors.red),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Done · 100%'), findsOneWidget);
    expect(find.text('Abandoned · 0%'), findsOneWidget);
  });
}
