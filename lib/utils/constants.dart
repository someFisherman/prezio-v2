class AppConstants {
  static const String appName = 'Prezio';
  static const String appVersion = '2.0.0';
  
  static const String defaultPiAddress = '192.168.4.1';
  static const int defaultPiPort = 8080;
  
  static const String pressureUnit = 'bar';
  static const String temperatureUnit = '°C';
  
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration requestTimeout = Duration(seconds: 30);
}

class StorageKeys {
  static const String technicianName = 'technician_name';
  static const String piAddress = 'pi_address';
  static const String piPort = 'pi_port';
  static const String lastObjectName = 'last_object_name';
  static const String lastProjectName = 'last_project_name';
}
