// lib/servisler/masa/qr_menu_sunucu_servisi.dart
//
// Kullanıcı isteği: "müşteriler kendi telefonuyla masadaki QR'ı okutup
// sipariş versin." ÖNCEDEN QrMenuServisi'ndeki qrKodUrlOlustur()
// fonksiyonu 'marketplus://...' gibi özel bir uygulama şeması
// üretiyordu — bu, müşterinin telefonunda BU UYGULAMANIN kurulu
// olmasını gerektiriyordu (fiilen çalışmayan bir özellikti).
//
// Bu dosya, uygulamanın ZATEN sahip olduğu, kanıtlanmış bir mimariyi
// (sync_servisi.dart'taki yerel HTTP sunucusu — WiFi senkronizasyonu
// için kullanılıyor) TEKRAR KULLANARAK gerçek bir çözüm sunuyor:
//   1. Tablet/telefon, kendi yerel WiFi ağında basit bir HTTP sunucusu
//      çalıştırır (müşterinin telefonuyla AYNI ağda olması yeterli —
//      internet gerekmez).
//   2. QR kodu, bu sunucunun adresini (http://<yerel-ip>:8090/menu/<masaId>)
//      gösterir.
//   3. Müşteri kendi telefonunun kamerasıyla bu kodu okutur — normal
//      tarayıcısında (Chrome/Safari) sade, mobil uyumlu bir menü sayfası
//      açılır. Hiçbir uygulama kurması gerekmez.
//   4. Sipariş verdiğinde, bu sunucu isteği alır ve DOĞRUDAN
//      QrMenuServisi.musteriSiparisKaydet() (az önce düzelttiğim,
//      güvenli fonksiyon) üzerinden veritabanına yazar.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../depolar/urun_deposu.dart';
import '../log_servisi.dart';
import 'qr_menu_servisi.dart';

class QrMenuSunucuServisi {
  static final QrMenuSunucuServisi _instance = QrMenuSunucuServisi._();
  factory QrMenuSunucuServisi() => _instance;
  QrMenuSunucuServisi._();

  static const int port = 8090;
  HttpServer? _server;
  String? _yerelIp;
  bool get calisiyorMu => _server != null;
  String? get yerelIp => _yerelIp;

  // 🔴 Derin analizde bulundu: sunucu tarafında tekrar-gönderim koruması
  // yoktu — istemcideki buton kilidi (aşağıdaki JS) UI seviyesinde
  // çift-tıklamayı önler ama ağ katmanındaki gerçek bir tekrar isteğini
  // (ör. yanıt gecikip istemci zaman aşımına uğrayınca kendiliğinden
  // tekrar deneme) durduramaz. Aynı masa+gövde içerikli istek birkaç
  // saniye içinde tekrar gelirse veritabanına ikinci kez yazılmadan
  // önceki 'başarılı' yanıt aynen döndürülür.
  //
  // Pencere 60 sn: müşteri sayfası 15 sn'de zaman aşımına uğrayıp "tekrar
  // dene" dediğinde (yanıt yolda kaybolmuş ama sipariş yazılmış olabilir)
  // aynı sepet ikinci kez yazılmasın.
  final _sonIstekler = <String, DateTime>{};
  static const _tekrarPenceresi = Duration(seconds: 60);

  /// Eşzamanlı çağrılar (ekran + yazdırma) aynı başlatmayı bekler; aksi
  /// halde iki ayrı bind denemesi yarışıyordu.
  Future<String?>? _baslatma;

  /// Sunucuyu (gerekirse) başlatır ve GÜNCEL yerel IP'yi döndürür; WiFi /
  /// kablolu yerel ağ yoksa null.
  ///
  /// 🔴 DÜZELTME (derin analiz 2026-10-07): IP ilk çağrıda bulunup sonsuza
  /// dek önbellekten dönüyordu. WiFi kopup başka bir IP ile geri gelince QR
  /// ölü adresi gösteriyor, hata da çıkmadığı için "Tekrar Dene" bile
  /// görünmüyordu. Artık IP her çağrıda yeniden okunur; sunucu kapanırsa
  /// (onDone) kendini sıfırlar ve bir sonraki çağrıda yeniden açılır.
  Future<String?> baslatVeIpAl() =>
      _baslatma ??= _baslat().whenComplete(() => _baslatma = null);

  Future<String?> _baslat() async {
    _yerelIp = await _lokalIpAl();
    if (_yerelIp == null) return null;
    if (_server != null) return _yerelIp;
    try {
      final sunucu =
          await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      sunucu.listen(
        _istekIsle,
        // Tek bir bağlantının hatası sunucuyu kapatmaz; yalnız loglanır.
        onError: (Object e, StackTrace st) =>
            LogServisi().uyari('QrMenuSunucu bağlantı hatası', hata: e, yigin: st),
        onDone: () => _sunucuKapandi(sunucu),
      );
      _server = sunucu;
      if (kDebugMode) debugPrint('QrMenuSunucu: http://$_yerelIp:$port');
      return _yerelIp;
    } catch (e, st) {
      LogServisi().hata('QrMenuSunucu başlatılamadı', hata: e, yigin: st);
      return null;
    }
  }

  void _sunucuKapandi(HttpServer sunucu) {
    if (identical(_server, sunucu)) _server = null;
  }

  Future<void> durdur() async {
    final sunucu = _server;
    _server = null;
    await sunucu?.close(force: true);
  }

  /// Bir masa için tam QR URL'i ([baslatVeIpAl] başarıyla çağrılmış olmalı).
  String? masaUrlOlustur(int masaId) {
    final ip = _yerelIp;
    return ip == null ? null : yerelMasaUrl(ip, masaId);
  }

  static String yerelMasaUrl(String ip, int masaId) =>
      'http://$ip:$port/menu/$masaId';

  Future<String?> _lokalIpAl() async {
    try {
      final arayuzler = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return enIyiYerelIp([
        for (final a in arayuzler)
          (ad: a.name, adresler: [for (final adr in a.addresses) adr.address]),
      ]);
    } catch (e, st) {
      LogServisi().uyari('QrMenuSunucu ağ arayüzleri okunamadı', hata: e, yigin: st);
      return null;
    }
  }

  /// Mobil veri / VPN / sanal makine arayüzleri: müşteri telefonu bunlara
  /// erişemez. (Önceden '10.' öneki öncelikli olduğu için WiFi kapalıyken
  /// operatörün 10.x mobil veri IP'si QR'a basılıyordu.)
  static const _haricOnekler = [
    'rmnet', 'ccmni', 'pdp', 'wwan', 'radio', 'clat', 'tun', 'ppp', 'ipsec',
    'dummy', 'teredo', 'isatap', 'utun', 'awdl', 'llw',
  ];
  static const _haricIcerenler = [
    'virtual', 'vethernet', 'hyper-v', 'vmware', 'vbox', 'docker', 'wsl',
    'bluetooth', 'vpn',
  ];

  /// Müşterinin aynı ağdan erişebileceği arayüz adları (Android/Windows/
  /// macOS/Linux; Türkçe Windows adları dahil).
  static const _yerelAgArayuzleri = [
    'wlan', 'wi-fi', 'wifi', 'swlan', 'ap', 'eth', 'en', 'ethernet', 'kablosuz',
    'yerel ağ', 'local area',
  ];

  /// Arayüz listesinden QR için en uygun yerel IPv4'ü seçer; yoksa null.
  /// Öncelik: bilinen WiFi/kablolu arayüz adı, sonra özel adres aralığı
  /// (192.168 > 10. > 172.16-31). Link-local (169.254) ve loopback elenir.
  @visibleForTesting
  static String? enIyiYerelIp(List<({String ad, List<String> adresler})> arayuzler) {
    String? enIyi;
    var enIyiPuan = 0;
    for (final a in arayuzler) {
      final ad = a.ad.toLowerCase();
      if (_haricOnekler.any(ad.startsWith) || _haricIcerenler.any(ad.contains)) {
        continue;
      }
      final adBonusu = _yerelAgArayuzleri.any(ad.startsWith) ? 10 : 0;
      for (final adres in a.adresler) {
        final aralik = _ozelAralikPuani(adres);
        if (aralik == 0) continue;
        final puan = adBonusu + aralik;
        if (puan > enIyiPuan) {
          enIyi = adres;
          enIyiPuan = puan;
        }
      }
    }
    return enIyi;
  }

  /// Özel (RFC 1918) adres aralığı puanı; erişilemeyecek adreslerde 0.
  static int _ozelAralikPuani(String adres) {
    if (adres.startsWith('192.168.')) return 3;
    if (adres.startsWith('10.')) return 2;
    final parca = adres.split('.');
    if (parca.length == 4 && parca[0] == '172') {
      final ikinci = int.tryParse(parca[1]) ?? 0;
      if (ikinci >= 16 && ikinci <= 31) return 1;
    }
    return 0; // loopback, 169.254 link-local, genel IP
  }

  Future<void> _istekIsle(HttpRequest req) async {
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    req.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }
    try {
      final yol = req.uri.path;
      if (req.method == 'GET' && yol.startsWith('/menu/')) {
        final masaId = int.tryParse(yol.substring('/menu/'.length)) ?? 0;
        req.response.headers.set('Content-Type', 'text/html; charset=utf-8');
        req.response.write(_menuHtml(masaId));
        await req.response.close();
      } else if (req.method == 'GET' && yol == '/api/menu/urunler') {
        final urunler = await UrunDeposu().tumunuGetir();
        // ÖNCEDEN burada TÜM aktif ürünler gösteriliyordu — ama
        // kullanıcının ZATEN sahip olduğu "QR Menü Ürün Seçimi"
        // ekranı, hangi ürünlerin QR menüde görünmesi gerektiğini
        // (qrMenude alanı) belirliyor. Artık sadece işaretlenen
        // ürünler gösteriliyor.
        final liste = urunler.where((u) => u.aktif && u.qrMenude).map((u) => {
              'id': u.id,
              'ad': u.urunAdi,
              'fiyat': u.satisFiyati,
              'kdv': double.tryParse(u.kdvOran) ?? 18,
              'grup': u.anaGrup ?? 'Diğer',
            }).toList();
        req.response.headers.set('Content-Type', 'application/json; charset=utf-8');
        req.response.write(jsonEncode({'urunler': liste}));
        await req.response.close();
      } else if (req.method == 'POST' && yol == '/api/menu/siparis') {
        final body = await utf8.decoder.bind(req).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final masaId = data['masa_id'] as int?;
        final kalemler = (data['kalemler'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // 🔴 Derin analizde bulundu: masa_id'nin gerçekten var olan bir
        // masaya ait olduğu hiç doğrulanmıyordu, ve kalem sayısında
        // hiçbir üst sınır yoktu — kimlik doğrulaması olmayan bu
        // uçnokta (bkz. fiyat güvenliği düzeltmesi — QrMenuServisi)
        // rastgele/aşırı büyük istekler için de sertleştirildi.
        if (masaId == null) {
          req.response.statusCode = 400;
          req.response.write(jsonEncode({'hata': 'masa_id gerekli'}));
          await req.response.close();
          return;
        }
        final db = await UrunDeposu().db;
        final masaVarMi = await db.query('masalar',
            columns: ['id'], where: 'id = ? AND is_deleted = 0', whereArgs: [masaId], limit: 1);
        if (masaVarMi.isEmpty) {
          req.response.statusCode = 404;
          req.response.write(jsonEncode({'hata': 'Masa bulunamadı'}));
          await req.response.close();
          return;
        }
        if (kalemler.isEmpty || kalemler.length > 100) {
          req.response.statusCode = 400;
          req.response.write(jsonEncode({'hata': 'Geçersiz kalem sayısı'}));
          await req.response.close();
          return;
        }
        final now = DateTime.now();
        _sonIstekler.removeWhere((_, t) => now.difference(t) > _tekrarPenceresi);
        final istekAnahtari = '$masaId:${body.hashCode}';
        if (_sonIstekler.containsKey(istekAnahtari)) {
          req.response.headers.set('Content-Type', 'application/json; charset=utf-8');
          req.response.write(jsonEncode({'basarili': true}));
          await req.response.close();
          return;
        }
        _sonIstekler[istekAnahtari] = now;
        await QrMenuServisi().musteriSiparisKaydet(
          masaId: masaId,
          kalemler: kalemler,
          musteriAdi: (data['musteri_adi'] as String?) ?? '',
          musteriTel: (data['musteri_tel'] as String?) ?? '',
          not: data['not'] as String?,
        );
        req.response.headers.set('Content-Type', 'application/json; charset=utf-8');
        req.response.write(jsonEncode({'basarili': true}));
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    } catch (e) {
      try {
        req.response.statusCode = 500;
        req.response.headers.set('Content-Type', 'application/json; charset=utf-8');
        req.response.write(jsonEncode({'hata': e.toString()}));
        await req.response.close();
      } catch (_) { /* istemci bağlantısı koptu — sunucu ayakta kalmalı */ }
    }
  }

  /// Müşterinin telefonunda açılan sade, mobil-uyumlu menü sayfası.
  String _menuHtml(int masaId) => '''
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title>Menü</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, Roboto, sans-serif; background: #F4F6FB; color: #1A1D2E; padding-bottom: 90px; }
  .baslik { background: linear-gradient(135deg, #4E342E, #6D4C41); color: white; padding: 20px 16px; }
  .baslik h1 { font-size: 20px; font-weight: 700; }
  .baslik p { font-size: 13px; opacity: 0.85; margin-top: 2px; }
  .grup { padding: 14px 16px 4px; font-size: 13px; font-weight: 700; color: #6D4C41; text-transform: uppercase; }
  .urun { background: white; margin: 6px 12px; border-radius: 14px; padding: 12px 14px;
          display: flex; justify-content: space-between; align-items: center;
          box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
  .urun-ad { font-size: 15px; font-weight: 600; }
  .urun-fiyat { font-size: 13px; color: #6B7280; margin-top: 2px; }
  .miktar-kutu { display: flex; align-items: center; gap: 10px; }
  .btn-yuvarlak { width: 32px; height: 32px; border-radius: 16px; border: none;
                  background: #4E342E; color: white; font-size: 18px; font-weight: 700; }
  .btn-yuvarlak:disabled { background: #D1D5DB; }
  .miktar-sayi { font-size: 15px; font-weight: 700; min-width: 18px; text-align: center; }
  .sepet-cubuk { position: fixed; bottom: 0; left: 0; right: 0; background: #4E342E;
                 color: white; padding: 14px 18px; display: none;
                 justify-content: space-between; align-items: center;
                 box-shadow: 0 -2px 10px rgba(0,0,0,0.2); }
  .sepet-cubuk.gorunur { display: flex; }
  .sepet-buton { background: white; color: #4E342E; border: none; border-radius: 10px;
                 padding: 10px 20px; font-weight: 700; font-size: 14px; }
  .modal { position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: none;
           align-items: flex-end; z-index: 10; }
  .modal.acik { display: flex; }
  .modal-icerik { background: white; width: 100%; border-radius: 20px 20px 0 0;
                  padding: 20px; max-height: 80vh; overflow-y: auto; }
  .modal-icerik h2 { font-size: 17px; margin-bottom: 12px; }
  .sepet-satir { display: flex; justify-content: space-between; padding: 8px 0;
                 border-bottom: 1px solid #eee; font-size: 14px; }
  input, textarea { width: 100%; padding: 10px; border: 1px solid #E5E7EB;
                     border-radius: 10px; font-size: 14px; margin-top: 6px; margin-bottom: 12px; }
  .gonder-btn { width: 100%; background: #2E7D32; color: white; border: none;
                border-radius: 12px; padding: 14px; font-size: 15px; font-weight: 700; }
  .kapat-btn { width: 100%; background: #F3F4F6; color: #374151; border: none;
               border-radius: 12px; padding: 12px; font-size: 14px; margin-top: 8px; }
  .basarili { text-align: center; padding: 60px 20px; }
  .basarili h2 { color: #2E7D32; font-size: 20px; margin-top: 12px; }
  .bilgi { text-align: center; padding: 48px 20px; color: #6B7280; font-size: 14px; line-height: 1.6; }
  .bilgi .sepet-buton { margin-top: 16px; background: #4E342E; color: white; }
</style>
</head>
<body>
  <div class="baslik"><h1>📋 Masa Menüsü</h1><p>Ürün seçip sepete ekleyin, siparişinizi gönderin</p></div>
  <div id="menuAlani"></div>
  <div class="sepet-cubuk" id="sepetCubuk">
    <span id="sepetOzet">0 ürün · 0 ₺</span>
    <button class="sepet-buton" onclick="sepetiAc()">Sepeti Gör</button>
  </div>
  <div class="modal" id="modal">
    <div class="modal-icerik">
      <div id="modalIcerik"></div>
    </div>
  </div>
<script>
const MASA_ID = $masaId;
let urunler = [];
let sepet = {};

// 🔴 DÜZELTME (güvenlik — XSS, qr_menu_sayfasi.html'deki AYNI düzeltme):
// ürün adı/grup gibi metinler escape edilmeden innerHTML'e ekleniyordu —
// biri "<" veya bir HTML etiketi içeren bir ürün adı girerse sayfa bozulur
// ya da (teorik olarak) tarayıcıda kod çalıştırılır.
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

// Ağ yavaş/kopuksa istek sonsuza dek beklemesin.
async function zamanAsimliFetch(url, secenekler, ms) {
  const iptal = new AbortController();
  const zamanlayici = setTimeout(() => iptal.abort(), ms);
  try {
    return await fetch(url, Object.assign({}, secenekler, { signal: iptal.signal }));
  } finally {
    clearTimeout(zamanlayici);
  }
}

function bilgiGoster(metin, tekrarDene) {
  document.getElementById('menuAlani').innerHTML =
    '<div class="bilgi">' + esc(metin) +
    (tekrarDene ? '<br><button class="sepet-buton" onclick="yukle()">Tekrar Dene</button>' : '') +
    '</div>';
}

// Önceden hata yakalanmıyordu: ağ yavaş/kopuksa müşteri boş beyaz sayfa görüyordu.
async function yukle() {
  bilgiGoster('Menü yükleniyor…', false);
  try {
    const r = await zamanAsimliFetch('/api/menu/urunler', {}, 15000);
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const d = await r.json();
    urunler = Array.isArray(d.urunler) ? d.urunler : [];
    if (urunler.length === 0) { bilgiGoster('Menüde henüz ürün yok. Lütfen personelden yardım isteyin.', true); return; }
    render();
  } catch (e) {
    bilgiGoster('Menü yüklenemedi. İşletmenin WiFi ağına bağlı olduğunuzdan emin olun.', true);
  }
}

function render() {
  const gruplar = {};
  urunler.forEach(u => { (gruplar[u.grup] = gruplar[u.grup] || []).push(u); });
  let html = '';
  for (const grup in gruplar) {
    html += '<div class="grup">' + esc(grup) + '</div>';
    gruplar[grup].forEach(u => {
      const adet = sepet[u.id] ? sepet[u.id].adet : 0;
      html += '<div class="urun">' +
        '<div><div class="urun-ad">' + esc(u.ad) + '</div>' +
        '<div class="urun-fiyat">' + u.fiyat.toFixed(2) + ' ₺</div></div>' +
        '<div class="miktar-kutu">' +
        '<button class="btn-yuvarlak" onclick="degistir(' + u.id + ',-1)" ' + (adet===0?'disabled':'') + '>−</button>' +
        '<span class="miktar-sayi">' + adet + '</span>' +
        '<button class="btn-yuvarlak" onclick="degistir(' + u.id + ',1)">+</button>' +
        '</div></div>';
    });
  }
  document.getElementById('menuAlani').innerHTML = html;
  sepetCubuguGuncelle();
}

function degistir(urunId, delta) {
  const u = urunler.find(x => x.id === urunId);
  if (!sepet[urunId]) sepet[urunId] = { urun: u, adet: 0 };
  sepet[urunId].adet = Math.max(0, sepet[urunId].adet + delta);
  if (sepet[urunId].adet === 0) delete sepet[urunId];
  render();
}

function sepetCubuguGuncelle() {
  const adetler = Object.values(sepet);
  const toplamAdet = adetler.reduce((s, k) => s + k.adet, 0);
  const toplamTutar = adetler.reduce((s, k) => s + k.adet * k.urun.fiyat, 0);
  const cubuk = document.getElementById('sepetCubuk');
  if (toplamAdet > 0) {
    cubuk.classList.add('gorunur');
    document.getElementById('sepetOzet').textContent = toplamAdet + ' ürün · ' + toplamTutar.toFixed(2) + ' ₺';
  } else {
    cubuk.classList.remove('gorunur');
  }
}

function sepetiAc() {
  const adetler = Object.values(sepet);
  const toplam = adetler.reduce((s, k) => s + k.adet * k.urun.fiyat, 0);
  let satirlar = adetler.map(k =>
    '<div class="sepet-satir"><span>' + k.adet + 'x ' + esc(k.urun.ad) + '</span><span>' +
    (k.adet * k.urun.fiyat).toFixed(2) + ' ₺</span></div>').join('');
  document.getElementById('modalIcerik').innerHTML =
    '<h2>Siparişiniz</h2>' + satirlar +
    '<div class="sepet-satir" style="font-weight:700;border-bottom:none;padding-top:10px;">' +
    '<span>Toplam</span><span>' + toplam.toFixed(2) + ' ₺</span></div>' +
    '<input id="adSoyad" placeholder="Adınız (opsiyonel)">' +
    '<input id="not" placeholder="Sipariş notu (opsiyonel)">' +
    '<button class="gonder-btn" onclick="gonder()">Siparişi Gönder</button>' +
    '<button class="kapat-btn" onclick="kapat()">Vazgeç</button>';
  document.getElementById('modal').classList.add('acik');
}

function kapat() { document.getElementById('modal').classList.remove('acik'); }

let gonderiliyor = false;

async function gonder() {
  // 🔴 Derin analizde bulundu: buton, istek sürerken devre dışı
  // bırakılmıyordu — müşteri "Siparişi Gönder"e art arda dokunursa
  // (ya da yavaş ağda sabırsızlanırsa) aynı sepet İKİ KEZ POST
  // edilebiliyordu (çift sipariş, çift tutar).
  if (gonderiliyor) return;
  gonderiliyor = true;
  const btn = document.querySelector('.gonder-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Gönderiliyor...'; }
  const kalemler = Object.values(sepet).map(k => ({
    urun_id: k.urun.id, urun_adi: k.urun.ad, miktar: k.adet,
    birim_fiyat: k.urun.fiyat, kdv_oran: k.urun.kdv,
    not: document.getElementById('not').value
  }));
  const gövde = {
    masa_id: MASA_ID, kalemler: kalemler,
    musteri_adi: document.getElementById('adSoyad').value,
    musteri_tel: '', not: document.getElementById('not').value
  };
  try {
    // Sunucu aynı sepeti 60 sn içinde ikinci kez yazmaz — zaman aşımından
    // sonra "tekrar dene" çift sipariş üretmez.
    const r = await zamanAsimliFetch('/api/menu/siparis', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(gövde)
    }, 15000);
    if (r.ok) {
      document.getElementById('modalIcerik').innerHTML =
        '<div class="basarili"><div style="font-size:48px;">✅</div>' +
        '<h2>Siparişiniz Alındı!</h2><p style="margin-top:8px;color:#6B7280;">Teşekkür ederiz, hazırlanıyor.</p></div>';
      sepet = {}; render();
      setTimeout(kapat, 2500);
    } else {
      alert('Bir hata oluştu, lütfen personelden yardım isteyin.');
      gonderiliyor = false;
      if (btn) { btn.disabled = false; btn.textContent = 'Siparişi Gönder'; }
    }
  } catch (e) {
    alert('Bağlantı hatası, lütfen personelden yardım isteyin.');
    gonderiliyor = false;
    if (btn) { btn.disabled = false; btn.textContent = 'Siparişi Gönder'; }
  }
}

yukle();
</script>
</body>
</html>
''';
}
