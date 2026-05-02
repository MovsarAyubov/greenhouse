import 'package:flutter/widgets.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('ru'), Locale('en')];

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    return localizations ?? const AppLocalizations(Locale('ru'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  bool get isRu => locale.languageCode.toLowerCase() == 'ru';

  String get appTitle => isRu ? 'Теплица SCADA' : 'Greenhouse SCADA';
  String get dashboard => isRu ? 'Панель' : 'Dashboard';
  String zone(int zoneId) => isRu ? 'Зона $zoneId' : 'Zone $zoneId';
  String get weather => isRu ? 'Погода' : 'Weather';
  String get settings => isRu ? 'Настройки' : 'Settings';
  String get connected => isRu ? 'ПОДКЛЮЧЕНО' : 'CONNECTED';
  String get disconnected => isRu ? 'ОТКЛЮЧЕНО' : 'DISCONNECTED';
  String get language => isRu ? 'Язык' : 'Language';
  String get russian => isRu ? 'Русский' : 'Russian';
  String get english => isRu ? 'Английский' : 'English';
  String get yes => isRu ? 'да' : 'yes';
  String get no => isRu ? 'нет' : 'no';
  String get loaded => isRu ? 'загружено' : 'loaded';
  String get missing => isRu ? 'отсутствует' : 'missing';
  String get unsupported => isRu ? 'не поддерживается' : 'unsupported';
  String get notAvailable => isRu ? 'Н/Д' : 'N/A';

  String get session => isRu ? 'Сессия' : 'Session';
  String state(String value) => isRu ? 'Состояние: $value' : 'State: $value';
  String lastError(String value) =>
      isRu ? 'Последняя ошибка: $value' : 'Last error: $value';
  String rtc(String value) => isRu ? 'RTC: $value' : 'RTC: $value';

  String get deviceTopology =>
      isRu ? 'Топология устройства' : 'Device topology';
  String active(bool value) =>
      isRu ? 'Активна: ${_yesNo(value)}' : 'Active: ${_yesNo(value)}';
  String version(String value) => isRu ? 'Версия: $value' : 'Version: $value';
  String generation(String value) =>
      isRu ? 'Поколение: $value' : 'Generation: $value';
  String sizeBytes(String value) =>
      isRu ? 'Размер: $value байт' : 'Size: $value bytes';

  String get localTopology => isRu ? 'Локальная топология' : 'Local topology';
  String manifest(bool value) => isRu
      ? 'Манифест: ${_loadedMissing(value)}'
      : 'Manifest: ${_loadedMissing(value)}';
  String manifestError(String value) =>
      isRu ? 'Ошибка манифеста: $value' : 'Manifest error: $value';
  String semanticCatalog(bool value) => isRu
      ? 'Семантический каталог: ${_loadedMissing(value)}'
      : 'Semantic catalog: ${_loadedMissing(value)}';
  String semanticPath(String value) =>
      isRu ? 'Путь семантики: $value' : 'Semantic path: $value';
  String semanticError(String value) =>
      isRu ? 'Ошибка семантики: $value' : 'Semantic error: $value';
  String blob(bool value) => isRu
      ? 'Blob: ${_loadedMissing(value)}'
      : 'Blob: ${_loadedMissing(value)}';
  String blobError(String value) =>
      isRu ? 'Ошибка blob: $value' : 'Blob error: $value';

  String get topologyInventory =>
      isRu ? 'Состав топологии' : 'Topology inventory';
  String moduleSummary({
    required int moduleId,
    required int slaveId,
    required int points,
    required bool schedule,
  }) => isRu
      ? 'module_id=$moduleId, slave=$slaveId, точки=$points, расписание=${_yesNo(schedule)}'
      : 'module_id=$moduleId, slave=$slaveId, points=$points, schedule=${_yesNo(schedule)}';

  String moduleIdSlave(int moduleId, int slaveId) => isRu
      ? 'module_id=$moduleId, slave_id=$slaveId'
      : 'module_id=$moduleId, slave_id=$slaveId';
  String zoneCapability(int zoneId, String capabilityHex) => isRu
      ? 'zone_id=$zoneId, возможности=0x$capabilityHex'
      : 'zone_id=$zoneId, capability=0x$capabilityHex';
  String onlineStale({required bool online, required bool stale}) => isRu
      ? 'онлайн=${_yesNo(online)} устарело=${_yesNo(stale)}'
      : 'online=${_yesNo(online)} stale=${_yesNo(stale)}';
  String slaveAgeErrors({
    required int age,
    required int timeout,
    required int crc,
    required int exception,
  }) => isRu
      ? 'возраст=$age таймаут/crc/искл=$timeout/$crc/$exception'
      : 'age=${age}s timeout/crc/exc=$timeout/$crc/$exception';

  String get lightingFeedback =>
      isRu ? 'Обратная связь освещения' : 'Lighting feedback';
  String get telemetry => isRu ? 'Телеметрия' : 'Telemetry';
  String pointRow({
    required int publishIndex,
    required Object quality,
    required Object age,
  }) => isRu
      ? 'publish_index=$publishIndex качество=$quality возраст=$age'
      : 'publish_index=$publishIndex quality=$quality age=${age}s';
  String fieldRow({
    required int publishIndex,
    required Object quality,
    required Object age,
    required String flags,
  }) => isRu
      ? 'publish_index=$publishIndex качество=$quality возраст=$age flags=$flags'
      : 'publish_index=$publishIndex quality=$quality age=${age}s flags=$flags';
  String get pointContractMissing =>
      isRu ? 'Контракт точки отсутствует' : 'Point contract missing';

  String get lightingSetpoints => isRu ? 'Освещение' : 'Lighting setpoints';
  String get relay1 => isRu ? 'Реле 1' : 'Relay 1';
  String get relay2 => isRu ? 'Реле 2' : 'Relay 2';
  String get enabled => isRu ? 'Включено' : 'Enabled';
  String onAt(String value) => isRu ? 'ВКЛ $value' : 'ON $value';
  String offAt(String value) => isRu ? 'ВЫКЛ $value' : 'OFF $value';
  String get threshold => isRu ? 'Порог' : 'Threshold';
  String get dliLimit => isRu ? 'Лимит DLI' : 'DLI limit';
  String get hysteresis => isRu ? 'Гистерезис' : 'Hysteresis';
  String get recommendedWrite => isRu
      ? 'Рекомендуемый режим: полная запись 13 слов'
      : 'Recommended mode: full 13-word payload write';
  String get sendSetpoints => isRu ? 'Отправить' : 'Send setpoints';
  String scheduleStatus({
    required String phase,
    required int trigger,
    required int applied,
    required int result,
    required int io,
  }) => isRu
      ? 'фаза=$phase триггер=$trigger применено=$applied результат=$result/$io'
      : 'phase=$phase trigger=$trigger applied=$applied result=$result/$io';
  String outputPct(int value) => isRu ? 'Выход $value%' : 'Output $value%';
  String get outputNa => isRu ? 'Выход Н/Д' : 'Output N/A';
  String relayState(int relay, bool on) => isRu
      ? 'Реле $relay ${on ? 'ВКЛ' : 'ВЫКЛ'}'
      : 'Relay $relay ${on ? 'ON' : 'OFF'}';

  String get host => isRu ? 'Хост' : 'Host';
  String get port => isRu ? 'Порт' : 'Port';
  String get unitId => isRu ? 'Unit ID' : 'Unit ID';
  String get addressMode => isRu ? 'Режим адресации' : 'Address mode';
  String get topologyManifestPath =>
      isRu ? 'Путь к манифесту топологии' : 'Topology manifest path';
  String get topologyBlobPath =>
      isRu ? 'Путь к blob топологии' : 'Topology blob path';
  String get semanticCatalogPath =>
      isRu ? 'Путь к семантическому каталогу' : 'Semantic catalog path';
  String get telemetryPollMs =>
      isRu ? 'Опрос телеметрии, мс' : 'Telemetry poll ms';
  String get diagPollMs => isRu ? 'Опрос диагностики, мс' : 'Diag poll ms';
  String get responseTimeoutMs =>
      isRu ? 'Таймаут ответа, мс' : 'Response timeout ms';
  String get retryCount => isRu ? 'Количество повторов' : 'Retry count';
  String get retryBackoffMs =>
      isRu ? 'Пауза между повторами, мс' : 'Retry backoff ms';
  String get pausePollingDuringWrites => isRu
      ? 'Приостанавливать опрос во время записи'
      : 'Pause polling during write workflows';
  String get save => isRu ? 'Сохранить' : 'Save';
  String get reloadTopology =>
      isRu ? 'Перезагрузить топологию' : 'Reload topology';
  String get reconnect => isRu ? 'Переподключиться' : 'Reconnect';
  String get uploadTopology => isRu ? 'Загрузить топологию' : 'Upload topology';
  String get settingsSaved => isRu ? 'Настройки сохранены' : 'Settings saved';
  String get hour => isRu ? 'Час' : 'Hour';
  String get minute => isRu ? 'Минута' : 'Minute';
  String get rtcSection => 'RTC';
  String get setRtc => isRu ? 'Установить RTC' : 'Set RTC';
  String get rtcUpdated => isRu ? 'RTC обновлен' : 'RTC updated';
  String rtcFailed(String value) =>
      isRu ? 'RTC ошибка: $value' : 'RTC failed: $value';
  String rtcError(String value) =>
      isRu ? 'Ошибка RTC: $value' : 'RTC error: $value';
  String get diagnostics => isRu ? 'Диагностика' : 'Diagnostics';
  String pollingPaused(bool value) => isRu
      ? 'Опрос приостановлен: ${_yesNo(value)}'
      : 'Polling paused: ${_yesNo(value)}';
  String updated(String value) =>
      isRu ? 'Обновлено: $value' : 'Updated: $value';
  String tcpLastErr(int value) =>
      isRu ? 'Последняя TCP ошибка: $value' : 'TCP last err: $value';
  String tcpCounters({
    required int accept,
    required int recvTimeout,
    required int stale,
    required int malformed,
    required int send,
  }) => isRu
      ? 'TCP accept/recvTimeout/stale/malformed/send=$accept/$recvTimeout/$stale/$malformed/$send'
      : 'TCP accept/recvTimeout/stale/malformed/send=$accept/$recvTimeout/$stale/$malformed/$send';
  String bootCounters({
    required int boot,
    required int power,
    required int error,
    required int watchdog,
    required int fault,
  }) => isRu
      ? 'Загрузка/питание/ошибка/wdg/fault=$boot/$power/$error/$watchdog/$fault'
      : 'Boot/power/error/wdg/fault=$boot/$power/$error/$watchdog/$fault';
  String diagnosticsError(String value) =>
      isRu ? 'Ошибка диагностики: $value' : 'Diagnostics error: $value';
  String get trace => isRu ? 'Трассировка' : 'Trace';
  String dli(String value) => 'DLI $value';

  String _yesNo(bool value) => value ? yes : no;
  String _loadedMissing(bool value) => value ? loaded : missing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((item) {
        return item.languageCode == locale.languageCode.toLowerCase();
      });

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final normalized = isSupported(locale) ? locale : const Locale('ru');
    return AppLocalizations(normalized);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
