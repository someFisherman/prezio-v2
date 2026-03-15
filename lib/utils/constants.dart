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

  /// Azure AD Application (Client) ID for OneDrive integration.
  /// Register at: https://portal.azure.com > App registrations
  /// Set redirect URI to: prezio://auth (Mobile/Desktop)
  /// API permissions: Microsoft Graph > Files.ReadWrite (delegated)
  static const String azureClientId = 'eb002767-9d98-4f11-a67e-99e499edd3db';  // TODO: Fill in after Azure registration
}

class StorageKeys {
  static const String technicianName = 'technician_name';
  static const String piAddress = 'pi_address';
  static const String piPort = 'pi_port';
  static const String lastObjectName = 'last_object_name';
  static const String lastProjectName = 'last_project_name';
  static const String outputFolderPath = 'output_folder_path';
  static const String outputFolderName = 'output_folder_name';
  static const String oneDriveRefreshToken = 'onedrive_refresh_token';
}
