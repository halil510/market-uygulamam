// lib/servisler/fatura_ebelge_servisi.dart
//
// Fatura detay ekranındaki e-Belge (taslak → onay → gönderim → hata)
// durum makinesinin ekran DIŞINDAKİ mantığı — ETTN belirleme, GİB
// çağrısı, DB durum güncellemesi. Önceden bu mantık fatura_detay_ekrani
// .dart'ın _durumSorgula/_gibIptalEt/_efaturaGonderIc metodlarının
// İÇİNDE, dialog/setState/context çağrılarıyla iç içe yaşıyordu (Madde 2
// mimari denetimi: "UI içerisinde business logic var mı?"). Bu servis o
// mantığı ayırıyor — ekran artık SADECE dialog/loading/bildirim
// göstermekten, bu servisi çağırmaktan sorumlu.
//
// DAVRANIŞ DEĞİŞMEDİ — her metod, ekrandaki karşılığıyla birebir aynı
// sırayla aynı DB/GİB çağrılarını yapıyor. Dialog/context yönetimi
// BİLEREK ekranda bırakıldı (bir servisin BuildContext'e bağımlı olması
// yanlış katman olurdu).
import '../depolar/fatura_deposu.dart';
import '../modeller/fatura_model.dart';
import 'gib_servisi.dart';

class FaturaEBelgeServisi {
  final FaturaDeposu _depo;
  final GibServisi _gib;

  FaturaEBelgeServisi({FaturaDeposu? depo, GibServisi? gib})
      : _depo = depo ?? FaturaDeposu(),
        _gib = gib ?? GibServisi();

  /// GİB ayarlarını yükler ve yapılandırılmış olup olmadığını döner —
  /// "e-Fatura Gönder" akışının ilk adımı (bkz. eski _efaturaGonderIc).
  Future<bool> ayarlariYukleVeKontrolEt() async {
    await _gib.ayarlariYukle();
    return _gib.ayarliMi;
  }

  /// Cari'nin GİB'de daha önce sorgulanmış mükellefiyet durumuna göre
  /// önerilen e-belge tipini döner — bilinmiyorsa null (kullanıcı elle
  /// seçer, otomatik/sessiz bir karar VERİLMEZ).
  EFaturaTipi? onerilenTip(FaturaModel fatura) => switch (fatura.cariMukellefDurumu) {
        'efatura' => EFaturaTipi.eFatura,
        'earsiv' => EFaturaTipi.eArsiv,
        _ => null,
      };

  /// "Durum Sorgula" için sorgulanacak ETTN'i belirler. Fatura hiç
  /// gönderilmemişse (durum hazır/null ve hiç UUID'si yoksa) null döner
  /// — çağıran taraf bu durumda "Henüz gönderim yapılmamış" göstermeli.
  ///
  /// 'gonderiliyor' durumundaki bir faturanın eFaturaUuid'si DB'de null
  /// olabilir (gönderim GİB'e gitti ama yanıt hiç işlenemedi — ör. çökme)
  /// — ETTN DETERMİNİSTİK olduğundan (GibServisi.ettnHesapla), hiç
  /// saklanmamış olsa bile burada yeniden hesaplanabilir.
  String? ettnBelirle(FaturaModel fatura) {
    if (fatura.eFaturaUuid != null) return fatura.eFaturaUuid;
    if (fatura.eFaturaDurum == 'gonderiliyor') return _gib.ettnHesapla(fatura);
    return null;
  }

  /// GİB'den durum sorgular, sonucu DB'ye yazar (ETTN de bu vesileyle
  /// kalıcı olarak doldurulmuş olur) ve normalleştirilmiş durumu döner.
  /// Hata durumunda exception fırlatır — çağıran taraf yakalayıp
  /// göstermeli (GibServisi.durumSorgula ile aynı sözleşme).
  Future<String?> durumSorgula(FaturaModel fatura, String ettn) async {
    await _gib.ayarlariYukle();
    final durum = await _gib.durumSorgula(ettn);
    if (durum != null) {
      await _depo.eFaturaDurumGuncelle(fatura.id!, durum, uuid: ettn);
    }
    return durum;
  }

  /// GİB'de iptal eder; başarılıysa DB'yi 'gib_iptal' olarak günceller.
  Future<bool> iptalEt(FaturaModel fatura) async {
    await _gib.ayarlariYukle();
    final basarili = await _gib.iptalEt(uuid: fatura.eFaturaUuid!);
    if (basarili) {
      await _depo.eFaturaDurumGuncelle(fatura.id!, 'gib_iptal', uuid: fatura.eFaturaUuid);
    }
    return basarili;
  }

  /// Faturayı GİB'e gönderir:
  ///  - daha önce REDDEDİLMİŞSE önce yeniden gönderime hazırlar (deneme
  ///    sayacını artırır ki GibServisi çakışmayan bir ETTN üretsin),
  ///  - ağ isteğinden ÖNCE 'gonderiliyor' işaretler (uygulama tam bu
  ///    sırada kapanırsa fatura sessizce eski durumda görünmeye devam
  ///    etmesin, "Durum Sorgula" ile netleştirilebilsin),
  ///  - sonucu (başarı/hata) DB'ye yazar.
  /// Sonuç ne olursa olsun DB güncellenmiş olarak döner — çağıran taraf
  /// sadece kullanıcıya göstermekle sorumludur.
  Future<GibGonderimSonucu> gonder(FaturaModel fatura, EFaturaTipi tip) async {
    var gonderilecek = fatura;
    if (fatura.eFaturaDurum == 'reddedildi') {
      await _depo.eFaturaYenidenGondermeyeHazirla(fatura.id!);
      final tazelenen = await _depo.idileGetir(fatura.id!);
      if (tazelenen != null) gonderilecek = tazelenen;
    }
    await _depo.eFaturaDurumGuncelle(gonderilecek.id!, 'gonderiliyor');
    // 🔴 DÜZELTME (kritik — bağımsız yeniden denetimde bulundu): GibServisi.
    // gonder() içindeki try/catch SADECE ağ isteği/yanıt ayrıştırma
    // bloğunu sarıyor — ondan ÖNCEKİ adımlar (ayarlariYukle, ETTN
    // hesaplama, ublXmlOlustur — ör. eksik firma bilgisi/KDV Muaf/
    // Tevkifat engelleri burada Exception fırlatır) try/catch DIŞINDA
    // kalıyordu. Durum yukarıda 'gonderiliyor' yapıldıktan SONRA bu
    // fırlarsa, hiçbir kod yolu 'hata'ya güncellemiyor, fatura SONSUZA
    // KADAR 'gonderiliyor'da takılı kalıyordu — tam olarak bu oturumda
    // GibServisi içinde kapatılmaya çalışılan bug sınıfının aynısı,
    // sadece bir katman daha yukarıda. Artık BURADA da (tüm çağrı
    // zincirini kapsayacak şekilde) yakalanıyor.
    try {
      final sonuc = await _gib.gonder(fatura: gonderilecek, tip: tip);
      if (sonuc.basarili) {
        await _depo.eFaturaDurumGuncelle(fatura.id!, 'gonderildi', uuid: sonuc.uuid);
      } else {
        // 🔴 DÜZELTME (erp_roadmap madde 38 — e-Belge durum makinesi):
        // ÖNCEDEN gönderim başarısız olduğunda DB'ye HİÇBİR ŞEY
        // yazılmıyordu — fatura sessizce 'hazir' (Beklemede) görünmeye
        // devam ediyordu. efatura_log tablosu zaten (GibServisi içinde)
        // başarısız denemeyi kaydediyordu, ama fatura kaydının kendisi hiç
        // işaretlenmiyordu.
        await _depo.eFaturaDurumGuncelle(fatura.id!, 'hata');
      }
      return sonuc;
    } catch (e) {
      await _depo.eFaturaDurumGuncelle(fatura.id!, 'hata');
      return GibGonderimSonucu(basarili: false, hata: 'Beklenmeyen hata: $e');
    }
  }
}
