import 'package:cockpit/app/settings/ui/categories/appearance_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/language_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/notification_settings_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'app preference category panels are importable outside settings_page',
    () {
      expect(const AppearanceSettingsPanel(), isA<AppearanceSettingsPanel>());
      expect(const LanguageSettingsPanel(), isA<LanguageSettingsPanel>());
      expect(
        const NotificationSettingsPanel(),
        isA<NotificationSettingsPanel>(),
      );
    },
  );
}
