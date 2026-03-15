import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class StorageService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String getTechnicianName() {
    return _prefs?.getString(StorageKeys.technicianName) ?? '';
  }

  Future<void> setTechnicianName(String name) async {
    await _prefs?.setString(StorageKeys.technicianName, name);
  }

  String getPiAddress() {
    return _prefs?.getString(StorageKeys.piAddress) ?? AppConstants.defaultPiAddress;
  }

  Future<void> setPiAddress(String address) async {
    await _prefs?.setString(StorageKeys.piAddress, address);
  }

  int getPiPort() {
    return _prefs?.getInt(StorageKeys.piPort) ?? AppConstants.defaultPiPort;
  }

  Future<void> setPiPort(int port) async {
    await _prefs?.setInt(StorageKeys.piPort, port);
  }

  String getLastObjectName() {
    return _prefs?.getString(StorageKeys.lastObjectName) ?? '';
  }

  Future<void> setLastObjectName(String name) async {
    await _prefs?.setString(StorageKeys.lastObjectName, name);
  }

  String getLastProjectName() {
    return _prefs?.getString(StorageKeys.lastProjectName) ?? '';
  }

  Future<void> setLastProjectName(String name) async {
    await _prefs?.setString(StorageKeys.lastProjectName, name);
  }

  String? getOutputFolderPath() {
    return _prefs?.getString(StorageKeys.outputFolderPath);
  }

  String getOutputFolderName() {
    return _prefs?.getString(StorageKeys.outputFolderName) ?? '';
  }

  Future<void> setOutputFolder(String? path, String? displayName) async {
    if (path != null) {
      await _prefs?.setString(StorageKeys.outputFolderPath, path);
      await _prefs?.setString(StorageKeys.outputFolderName, displayName ?? path.split('/').last);
    } else {
      await _prefs?.remove(StorageKeys.outputFolderPath);
      await _prefs?.remove(StorageKeys.outputFolderName);
    }
  }

  String? getOneDriveRefreshToken() {
    return _prefs?.getString(StorageKeys.oneDriveRefreshToken);
  }

  Future<void> setOneDriveRefreshToken(String? token) async {
    if (token != null) {
      await _prefs?.setString(StorageKeys.oneDriveRefreshToken, token);
    } else {
      await _prefs?.remove(StorageKeys.oneDriveRefreshToken);
    }
  }
}
