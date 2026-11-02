import 'dart:io';

import 'package:cinema_client/quark/quark_account_store.dart';
import 'package:cinema_client/quark/quark_login_screen.dart';
import 'package:cinema_client/quark/quark_playback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Service extends QuarkPlaybackService {
  _Service()
    : super(
        accountStore: const QuarkAccountStore(),
        supportDirectory: Directory('unused'),
      );
  String? saved;
  @override
  Future<void> connectCookie(String cookie) async {
    saved = cookie;
  }
}

void main() {
  testWidgets('Cookie can be configured without loading a login web page', (
    tester,
  ) async {
    final service = _Service();
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QuarkLoginScreen(playbackService: service),
                ),
              ),
              child: const Text('打开账号设置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开账号设置'));
    await tester.pumpAndSettle();
    expect(find.text('夸克快传'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
    await tester.enterText(
      find.byType(TextField),
      '__uid=synthetic; __puus=synthetic',
    );
    await tester.tap(find.text('验证并保存'));
    await tester.pumpAndSettle();
    expect(service.saved, '__uid=synthetic; __puus=synthetic');
    expect(find.text('打开账号设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
