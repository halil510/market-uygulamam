// lib/servisler/bulut/anlik_bulut_dinleyici.dart
//
// ANLIK SENKRON (kullanıcı isteği 2026-10-02): "bir şey ekliyorum diğer
// cihaza geç düşüyor, profesyonel ERP'lerde hemen düşüyor".
//
// Neden gecikiyordu: diğer cihazlar buluttaki değişikliği ancak 60 sn'lik
// periyodik çekmede (masa ekranlarında 5-15 sn) fark ediyordu — bulut
// "değişti" diye haber vermiyordu.
//
// Çözüm (profesyonel sistemlerin yaptığı gibi): Supabase Realtime
// (WebSocket) üzerinden "tablo X'te kayıt değişti" bildirimi dinlenir; bildirim
// gelince YALNIZ o tablolar delta olarak çekilir (≈ saniyenin altı). Bildirim
// yalnız tetikleyicidir — veri yine mevcut güvenli çekme hattından
// (FK çevirisi, LWW koruması, watermark) gelir; yani bu servis veri yazmaz.
//
// Güvenlik ağı: WebSocket kopsa / Realtime kapalı olsa bile OtomatikBulutCekme'nin
// periyodik çekmesi ve bağlantı geri geldiğinde tam çekme çalışmaya devam eder.
// Sunucu tarafında tabloların `supabase_realtime` yayınında olması gerekir
// (supabase_tam_sema.sql, bölüm I).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../log_servisi.dart';
import '../supabase_sync_servisi.dart';
import 'bulut_manager.dart';
import 'otomatik_bulut_cekme.dart';
import 'supabase_ayarlari.dart';
import 'supabase_oturum.dart';

class AnlikBulutDinleyici with WidgetsBindingObserver {
  static final AnlikBulutDinleyici _instance = AnlikBulutDinleyici._();
  factory AnlikBulutDinleyici() => _instance;
  AnlikBulutDinleyici._();

  /// Bildirimle tetiklenen çekme buluttan en az bir kayıt getirince artar —
  /// açık ekranlar (masa, mutfak…) bunu dinleyip kendini yeniler.
  final yenilemeSayaci = ValueNotifier<int>(0);

  /// WebSocket şu an bağlı ve abone mi (ekranda gösterim / teşhis).
  final bagli = ValueNotifier<bool>(false);

  static const _kanal = 'realtime:db';
  static const _kalpAtisi = Duration(seconds: 25);
  static const _tokenYenileme = Duration(minutes: 40);
  static const _bildirimBeklemesi = Duration(milliseconds: 400);

  WebSocket? _ws;
  StreamSubscription<dynamic>? _abonelik;
  Timer? _kalpZamanlayici;
  Timer? _tokenZamanlayici;
  Timer? _yenidenZamanlayici;
  Timer? _cekmeZamanlayici;
  final Set<String> _bekleyenTablolar = {};
  bool _basladi = false;
  bool _onde = true;
  bool _baglaniyor = false;
  bool _cekiyor = false;
  bool _ilkBaglanti = true;
  bool _abonelikHatasiBildirildi = false;
  int _ardisikHata = 0;
  int _ref = 1;

  Future<void> baslat() async {
    if (_basladi) return;
    _basladi = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_baglan());
  }

  void durdur() {
    _basladi = false;
    WidgetsBinding.instance.removeObserver(this);
    _yenidenZamanlayici?.cancel();
    _cekmeZamanlayici?.cancel();
    _kapat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final onceOnde = _onde;
    _onde = state == AppLifecycleState.resumed;
    if (!_basladi) return;
    if (_onde && !onceOnde) {
      // Arka planda soket sessizce ölmüş olabilir — tazele ve kaçanları çek.
      _kapat();
      unawaited(_baglan());
    } else if (!_onde && onceOnde) {
      _yenidenZamanlayici?.cancel();
      _kapat();
    }
  }

  Future<void> _baglan() async {
    if (!_basladi || !_onde || _ws != null || _baglaniyor) return;
    _baglaniyor = true;
    try {
      if (BulutManager().durum.value == BulutDurum.yapilandirilmamis) {
        _yenidenPlanla(const Duration(seconds: 30));
        return;
      }
      final url = await SupabaseAyarlari.urlOku();
      final key = await SupabaseAyarlari.keyOku();
      if (url == null || url.isEmpty || key == null || !SupabaseOturum.gonderimeHazir(key)) {
        _yenidenPlanla(const Duration(seconds: 30));
        return;
      }
      final temel = Uri.parse(url);
      final wsUri = Uri(
        scheme: temel.scheme == 'http' ? 'ws' : 'wss',
        host: temel.host,
        port: temel.hasPort ? temel.port : null,
        path: '/realtime/v1/websocket',
        queryParameters: {'apikey': key, 'vsn': '1.0.0'},
      );
      // Soket _ws alanında tutulur ve _kapat() içinde kapatılır.
      // ignore: close_sinks
      final ws = await WebSocket.connect(wsUri.toString())
          .timeout(const Duration(seconds: 15));
      _ws = ws;
      _abonelik = ws.listen(_mesaj, onDone: _koptu, onError: (_) => _koptu(), cancelOnError: true);
      _gonder(_kanal, 'phx_join', {
        'config': {
          'broadcast': {'ack': false, 'self': false},
          'presence': {'key': ''},
          'postgres_changes': [
            {'event': '*', 'schema': 'public'}
          ],
        },
        'access_token': SupabaseOturum.bearer(key),
      });
      _kalpZamanlayici = Timer.periodic(_kalpAtisi, (_) => _gonder('phoenix', 'heartbeat', {}));
      // Erişim anahtarı ~1 saatte dolar; dolmadan yeni anahtarla yeniden bağlan.
      // Süre anahtarın GERÇEK bitişine göre (canlı test 2026-10-08): sabit
      // 40 dk, anahtarın son 20 dakikasında kurulan bağlantıda anahtar önce
      // doluyor, Realtime kanalı kapatıyordu.
      var yenilemeSuresi = _tokenYenileme;
      final bitis = SupabaseOturum().erisimBitis;
      if (bitis != null && !SupabaseOturum.gizliAnahtarMi(key)) {
        final kalan = bitis.difference(DateTime.now()) - const Duration(minutes: 3);
        if (kalan < yenilemeSuresi) {
          yenilemeSuresi =
              kalan > const Duration(seconds: 30) ? kalan : const Duration(seconds: 30);
        }
      }
      _tokenZamanlayici = Timer(yenilemeSuresi, () {
        _kapat();
        unawaited(_baglan());
      });
    } catch (e) {
      if (kDebugMode) debugPrint('AnlikBulutDinleyici bağlanamadı: $e');
      _ardisikHata++;
      _kapat();
      _yenidenPlanla(_geriCekilme());
    } finally {
      _baglaniyor = false;
    }
  }

  Duration _geriCekilme() {
    final sn = 2 << (_ardisikHata > 5 ? 5 : _ardisikHata);
    return Duration(seconds: sn > 60 ? 60 : sn);
  }

  void _yenidenPlanla(Duration sure) {
    _yenidenZamanlayici?.cancel();
    if (!_basladi || !_onde) return;
    _yenidenZamanlayici = Timer(sure, () => unawaited(_baglan()));
  }

  void _gonder(String konu, String olay, Map<String, dynamic> yuk) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.add(jsonEncode({'topic': konu, 'event': olay, 'payload': yuk, 'ref': '${_ref++}'}));
    } catch (_) {
      _koptu();
    }
  }

  void _mesaj(dynamic ham) {
    try {
      final m = jsonDecode(ham as String) as Map<String, dynamic>;
      final olay = m['event'];
      final yuk = m['payload'];
      switch (olay) {
        case 'phx_reply':
          if (m['topic'] == _kanal && yuk is Map) {
            if (yuk['status'] == 'ok') {
              final yeniden = !_ilkBaglanti;
              _ilkBaglanti = false;
              _ardisikHata = 0;
              bagli.value = true;
              // Kopukken kaçan değişiklikleri yakalamak için bir tam çekme.
              if (yeniden) unawaited(OtomatikBulutCekme().simdiCek());
            } else {
              LogServisi().uyari('AnlikBulutDinleyici: kanala katılınamadı',
                  ek: jsonEncode(yuk));
            }
          }
          break;
        case 'postgres_changes':
          final veri = yuk is Map ? yuk['data'] : null;
          final tablo = veri is Map ? veri['table'] : null;
          if (tablo is String) {
            _bekleyenTablolar.add(tablo);
            _cekmeyiPlanla();
          }
          break;
        case 'system':
          final sistemMesaji = yuk is Map ? '${yuk['message'] ?? ''}' : '';
          if (yuk is Map &&
              yuk['status'] == 'error' &&
              RegExp('token|jwt|expired|unauthorized', caseSensitive: false)
                  .hasMatch(sistemMesaji)) {
            // Erişim anahtarı doldu/geçersiz: kalıcı ret değil — oturumu
            // tazeleyip yeniden bağlan (önceden kanal, uygulama yeniden
            // açılana kadar ölü kalıyordu).
            _koptu();
            break;
          }
          if (yuk is Map && yuk['status'] == 'error' && !_abonelikHatasiBildirildi) {
            // En sık neden: tablolar supabase_realtime yayınında değil.
            _abonelikHatasiBildirildi = true;
            bagli.value = false;
            LogServisi().uyari(
                'AnlikBulutDinleyici: Realtime aboneliği reddedildi — supabase_tam_sema.sql '
                'bölüm I (yayın) çalıştırılmamış olabilir; periyodik çekme devam ediyor',
                ek: '${yuk['message']}');
          }
          break;
        case 'phx_error':
        case 'phx_close':
          if (m['topic'] == _kanal) _koptu();
          break;
      }
    } catch (_) {
      // Bozuk/beklenmeyen çerçeve — yut; veri akışı periyodik çekmeyle sürer.
    }
  }

  /// Aynı anda gelen birçok bildirim tek çekmeye toplanır (ilk bildirimden
  /// itibaren kısa bekleme, sonrakiler beklemeyi uzatmaz — yoğun yazımda
  /// çekme aç kalmaz).
  void _cekmeyiPlanla() {
    if (_cekmeZamanlayici?.isActive ?? false) return;
    _cekmeZamanlayici = Timer(_bildirimBeklemesi, () => unawaited(_cek()));
  }

  Future<void> _cek() async {
    if (_cekiyor) {
      _cekmeyiPlanla();
      return;
    }
    if (_bekleyenTablolar.isEmpty) return;
    _cekiyor = true;
    final tablolar = Set<String>.of(_bekleyenTablolar);
    _bekleyenTablolar.clear();
    try {
      final key = await SupabaseAyarlari.keyOku();
      if (key == null || !SupabaseOturum.gonderimeHazir(key)) return;
      final sonuc = await SupabaseSyncServisi.yerelBuluttanAl(sadeceTablolar: tablolar);
      if (!sonuc.basarili) {
        // Başarısız tablolar bir sonraki bildirimde ya da periyodik çekmede alınır.
        LogServisi().uyari('AnlikBulutDinleyici: anlık çekme hatası',
            ek: sonuc.hatalar.take(2).join(' | '));
        return;
      }
      final gelen = sonuc.toplamEklenen + sonuc.toplamGuncellenen + sonuc.toplamSilinen;
      if (gelen > 0) {
        OtomatikBulutCekme().sonDegisiklik.value = DateTime.now();
        yenilemeSayaci.value++;
      }
    } catch (e, st) {
      LogServisi().hata('AnlikBulutDinleyici._cek', hata: e, yigin: st);
    } finally {
      _cekiyor = false;
      if (_bekleyenTablolar.isNotEmpty) _cekmeyiPlanla();
    }
  }

  void _koptu() {
    if (_ws == null && !_baglaniyor) {
      if (_basladi && _onde) _yenidenPlanla(_geriCekilme());
      return;
    }
    _kapat();
    _ardisikHata++;
    _yenidenPlanla(_geriCekilme());
  }

  void _kapat() {
    _kalpZamanlayici?.cancel();
    _tokenZamanlayici?.cancel();
    _kalpZamanlayici = null;
    _tokenZamanlayici = null;
    final ws = _ws;
    _ws = null;
    _abonelik?.cancel();
    _abonelik = null;
    bagli.value = false;
    try {
      ws?.close();
    } catch (_) {}
  }
}
