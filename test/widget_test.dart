import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:apatheia/main.dart'; // Βεβαιώσου ότι το όνομα στο pubspec.yaml είναι apatheia

void main() {
  testWidgets('Apatheia smoke test', (WidgetTester tester) async {
    // Φόρτωση της εφαρμογής
    await tester.pumpWidget(const MinimalApp());

    // Έλεγχος αν εμφανίζεται το κείμενο για "No tasks" όταν η λίστα είναι άδεια
    expect(find.text("No tasks.\nEnjoy the silence."), findsOneWidget);

    // Έλεγχος αν υπάρχει το κουμπί προσθήκης (CupertinoIcons.add)
    expect(find.byIcon(CupertinoIcons.add), findsOneWidget);

    // Πάτημα του κουμπιού προσθήκης
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle(); // Περιμένουμε να ανοίξει το bottom sheet

    // Έλεγχος αν άνοιξε το παράθυρο με τον τίτλο "NEW FOCUS"
    expect(find.text("NEW FOCUS"), findsOneWidget);
  });
}
