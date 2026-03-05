import '../models/autofill_settings.dart';

abstract class AutofillSettingsRepository {
  Future<AutofillSettings> load();
  Future<AutofillSettings> save(AutofillSettings settings);
}
