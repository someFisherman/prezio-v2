class AppConstants {
  static const String appName = 'Prezio';
  static const String appVersion = '2.2.0';
  
  static const String defaultPiAddress = '192.168.4.1';
  static const int defaultPiPort = 8080;
  
  static const String pressureUnit = 'bar';
  static const String temperatureUnit = '°C';
  
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration requestTimeout = Duration(seconds: 30);

  static const double defaultRecordingInterval = 10.0;

  static const String masterPasswordHash =
      '424343bbbe4f1f33976247e6508b0cbd42e89ef1d1fa9f07c7299a1d9f4e2b29';
}

class StorageKeys {
  static const String technicianName = 'technician_name';
  static const String piAddress = 'pi_address';
  static const String piPort = 'pi_port';
  static const String lastObjectName = 'last_object_name';
  static const String lastProjectName = 'last_project_name';
  static const String outputFolderPath = 'output_folder_path';
  static const String outputFolderName = 'output_folder_name';
  static const String appUnlocked = 'app_unlocked';
}
