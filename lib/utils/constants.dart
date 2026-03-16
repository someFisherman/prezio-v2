class AppConstants {
  static const String appName = 'Prezio';
  static const String appVersion = '2.3.0';
  
  static const String defaultRecorderAddress = '192.168.4.1';
  static const int defaultRecorderPort = 8080;

  @Deprecated('Use defaultRecorderAddress')
  static const String defaultPiAddress = defaultRecorderAddress;
  @Deprecated('Use defaultRecorderPort')
  static const int defaultPiPort = defaultRecorderPort;
  
  static const String pressureUnit = 'bar';
  static const String temperatureUnit = '°C';
  
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration requestTimeout = Duration(seconds: 30);

  static const double defaultRecordingInterval = 10.0;
}

class StorageKeys {
  static const String technicianName = 'technician_name';
  static const String recorderAddress = 'recorder_address';
  static const String recorderPort = 'recorder_port';
  static const String lastObjectName = 'last_object_name';
  static const String lastProjectName = 'last_project_name';
  static const String outputFolderPath = 'output_folder_path';
  static const String outputFolderName = 'output_folder_name';

  @Deprecated('Use recorderAddress')
  static const String piAddress = recorderAddress;
  @Deprecated('Use recorderPort')
  static const String piPort = recorderPort;
}
