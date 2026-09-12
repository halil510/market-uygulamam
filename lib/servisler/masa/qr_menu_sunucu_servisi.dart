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

  /// Sunucuyu başlatır (zaten çalışıyorsa hiçbir şey yapmaz).
  /// Dönen değer: yerel IP adresi (QR kod URL'i oluşturmak için), veya
  /// null (WiFi bağlantısı bulunamadıysa).
  Future<String?> baslatVeIpAl() async {
    if (_server != null && _yerelIp != null) return _yerelIp;
    try {
      _yerelIp = await _lokalIpAl();
      if (_yerelIp == null) return null;
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      if (kDebugMode) debugPrint('QrMenuSunucu: http://$_yerelIp:$port');
      _server!.listen(_istekIsle, onError: (_) {});
      return _yerelIp;
    } catch (e) {
      if (kDebugMode) debugPrint('QrMenuSunucu başlatma hatası: $e');
      _server = null;
      return null;
    }
  }

  Future<void> durdur() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Bir masa için tam QR URL'i döndürür (sunucu zaten çalışıyor olmalı).
  String? masaUrlOlustur(int masaId) {
    if (_yerelIp == null) return null;
    return 'http://$_yerelIp:$port/menu/$masaId';
  }

  Future<String?> _lokalIpAl() async {
    try {
      final arayuzler = await NetworkInterface.list(type: InternetAddressType.IPv4);
      const oncelikli = ['192.168', '10.', '172.'];
      for (final on in oncelikli) {
        for (final a in arayuzler) {
          for (final adr in a.addresses) {
            if (!adr.isLoopback && adr.address.startsWith(on)) return adr.address;
          }
        }
      }
      for (final a in arayuzler) {
        for (final adr in a.addresses) {
          if (!adr.isLoopback) return adr.address;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
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

async function yukle() {
  const r = await fetch('/api/menu/urunler');
  const d = await r.json();
  urunler = d.urunler;
  render();
}

function render() {
  const gruplar = {};
  urunler.forEach(u => { (gruplar[u.grup] = gruplar[u.grup] || []).push(u); });
  let html = '';
  for (const grup in gruplar) {
    html += '<div class="grup">' + grup + '</div>';
    gruplar[grup].forEach(u => {
      const adet = sepet[u.id] ? sepet[u.id].adet : 0;
      html += '<div class="urun">' +
        '<div><div class="urun-ad">' + u.ad + '</div>' +
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
    '<div class="sepet-satir"><span>' + k.adet + 'x ' + k.urun.ad + '</span><span>' +
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

async function gonder() {
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
    const r = await fetch('/api/menu/siparis', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(gövde)
    });
    if (r.ok) {
      document.getElementById('modalIcerik').innerHTML =
        '<div class="basarili"><div style="font-size:48px;">✅</div>' +
        '<h2>Siparişiniz Alındı!</h2><p style="margin-top:8px;color:#6B7280;">Teşekkür ederiz, hazırlanıyor.</p></div>';
      sepet = {}; render();
      setTimeout(kapat, 2500);
    } else { alert('Bir hata oluştu, lütfen personelden yardım isteyin.'); }
  } catch (e) { alert('Bağlantı hatası, lütfen personelden yardım isteyin.'); }
}

yukle();
</script>
</body>
</html>
''';
}
