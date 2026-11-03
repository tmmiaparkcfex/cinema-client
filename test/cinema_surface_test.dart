import 'package:cinema_client/widgets/cinema_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('failed poster can be replaced and unmounted without detaching a disposed stream', (tester) async {
    // Widget tests return HTTP 400. The palette must release its listener once.
    for (final url in ['https://example.invalid/first.jpg', 'https://example.invalid/second.jpg']) {
      await tester.pumpWidget(MaterialApp(home: PosterSurface(imageUrl: url,
        child: const Text('影片资料'))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
