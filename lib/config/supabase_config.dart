/// Supabase-Konfiguration fuer Prezio.
/// URL und Key aus dem Supabase-Dashboard eintragen.
class SupabaseConfig {
  static const String url = 'https://ndqisdqdhzeenvjkkuxd.supabase.co';
  static const String anonKey = 'sb_publishable_7_dV2GvFjTKAu3cH9XPTXg_L69KyAT_';

  /// Storage-Bucket Name fuer PDFs
  static const String bucket = 'protokolle';

  static bool get isConfigured =>
      url.isNotEmpty && anonKey.isNotEmpty;
}
