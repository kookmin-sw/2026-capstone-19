class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8000',
  );
}