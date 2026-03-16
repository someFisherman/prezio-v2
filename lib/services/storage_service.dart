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

  String getRecorderAddress() {
    return _prefs?.getString(StorageKeys.recorderAddress) ?? AppConstants.defaultRecorderAddress;
  }

  @Deprecated('Use getRecorderAddress')
  String getPiAddress() => getRecorderAddress();

  Future<void> setRecorderAddress(String address) async {
    await _prefs?.setString(StorageKeys.recorderAddress, address);
  }

  @Deprecated('Use setRecorderAddress')
  Future<void> setPiAddress(String address) => setRecorderAddress(address);

  int getRecorderPort() {
    return _prefs?.getInt(StorageKeys.recorderPort) ?? AppConstants.defaultRecorderPort;
  }

  @Deprecated('Use getRecorderPort')
  int getPiPort() => getRecorderPort();

  Future<void> setRecorderPort(int port) async {
    await _prefs?.setInt(StorageKeys.recorderPort, port);
  }

  @Deprecated('Use setRecorderPort')
  Future<void> setPiPort(int port) => setRecorderPort(port);

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
}
