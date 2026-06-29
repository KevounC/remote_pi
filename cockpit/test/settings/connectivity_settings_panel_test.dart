import 'package:cockpit/app/settings/ui/categories/connectivity_settings_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connectivity settings panel is importable outside settings_page', () {
    expect(const ConnectivitySettingsPanel(), isA<ConnectivitySettingsPanel>());
  });
}
