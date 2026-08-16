// lib/modeller/yazici_model.dart
class YaziciModel {
  final int? id;
  final String tur; // bluetooth | ag | usb
  final String adi;
  final String? cihazId;
  final String? ip;
  final int port;
  final String kategori; // fis | etiket | a4
  final bool varsayilan;
  final bool aktif;

  const YaziciModel({
    this.id, required this.tur, required this.adi,
    this.cihazId, this.ip, this.port = 9100,
    this.kategori = 'fis', this.varsayilan = false, this.aktif = true,
  });

  factory YaziciModel.fromMap(Map<String, dynamic> m) => YaziciModel(
    id: m['id'] as int?,
    tur: m['tur'] as String? ?? 'bluetooth',
    adi: m['adi'] as String? ?? '',
    cihazId: m['cihaz_id'] as String?,
    ip: m['ip'] as String?,
    port: (m['port'] as int?) ?? 9100,
    kategori: m['kategori'] as String? ?? 'fis',
    varsayilan: (m['varsayilan'] as int?) == 1,
    aktif: (m['aktif'] as int?) == 1,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'tur': tur, 'adi': adi,
    if (cihazId != null) 'cihaz_id': cihazId,
    if (ip != null) 'ip': ip,
    'port': port, 'kategori': kategori,
    'varsayilan': varsayilan ? 1 : 0,
    'aktif': aktif ? 1 : 0,
  };
}
