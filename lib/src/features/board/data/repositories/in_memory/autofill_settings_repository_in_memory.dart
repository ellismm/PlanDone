import '../../../domain/models/autofill_settings.dart';
import '../../../domain/repositories/autofill_settings_repository.dart';

class InMemoryAutofillSettingsRepository implements AutofillSettingsRepository {
  InMemoryAutofillSettingsRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, AutofillSettings> _settingsByUser =
      <String, AutofillSettings>{};

  @override
  Future<AutofillSettings> load() async {
    return _settingsByUser[_userId] ?? const AutofillSettings();
  }

  @override
  Future<AutofillSettings> save(AutofillSettings settings) async {
    _settingsByUser[_userId] = settings;
    return settings;
  }
}
