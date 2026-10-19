# 🍊 Mandalina — UYAP (`.udf`) & Çok Sayfalı TIFF Dönüştürücü (macOS & Windows)

<p align="center">
  <img src="AppIcon.png" width="148" alt="Mandalina App Icon" />
</p>

Avukatlar ve hukuk büroları için **Tangerine** etkileşim mimarisiyle geliştirilmiş; **UYAP (`.udf`)**, **Çok Sayfalı TIFF (`.tiff`)**, **PDF**, **Microsoft Word (`.docx`)** ve görsel dosyalarını **%100 çevrimdışı (offline) ve yerel** olarak dönüştüren, sıkıştıran, birleştiren ve Türkçe OCR uygulayan **macOS ve Windows** masaüstü uygulaması.

---

## 🍏 macOS Hızlı Kurulum (Tek Komutla Sıfır Bağımlılık)

macOS bilgisayarınızda **Terminal** uygulamasını açıp aşağıdaki tek satır komutu yapıştırıp `Enter` tuşuna basmanız yeterlidir:

```bash
curl -fsSL https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/install.sh | bash
```

> **⚡ Sıfır Bağımlılık (Universal Binary: Apple Silicon + Intel):**
> Sisteminizde Xcode veya ek bir kütüphane kurulu olmasına gerek yoktur. Kurulum betiği eksik bileşenleri kontrol eder, uygulamayı imzalar, **Uygulamalar (`/Applications/Mandalina.app`)** klasörüne, **Masaüstünüze** ve **macOS Menü Çubuğuna (`🍊`)** yerleştirerek otomatik olarak başlatır.
> *(Dilerseniz klasör içindeki `Kurulum.command` dosyasına çift tıklayarak da kurabilirsiniz.)*

### macOS Güncelleme & Kaldırma
```bash
# Güncelleme:
curl -fsSL https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/update.sh | bash

# Kaldırma:
curl -fsSL https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/uninstall.sh | bash
```

---

## 🪟 Windows Hızlı Kurulum (Windows 10 & Windows 11)

Windows bilgisayarınızda **PowerShell** penceresini açıp aşağıdaki tek satır komutu yapıştırıp `Enter` tuşuna basmanız yeterlidir:

```powershell
irm https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/install.ps1 | iex
```

> **⚡ Otomatik Bileşen Kurulumu:**
> - Bilgisayarınızda Python 3 veya dönüşüm bileşenleri kurulu değilse `install.ps1` otomatik olarak (`winget` veya resmi Python paketi üzerinden) eksik bileşenleri kurar.
> - **Masaüstüne (`Mandalina.lnk`)**, **Başlat Menüsüne**, **Windows Sistem Tepsisine (Saatin yanındaki Görev Çubuğu Tepsisi)** ve **Sağ Tık → Gönder (`Send To -> Mandalina UDF Dönüştürücü`)** menüsüne özel ikonuyla yerleşir.
> - *(Dilerseniz repo içerisindeki **`Kurulum_Windows.bat`** dosyasına çift tıklayarak da tek tıkla kurabilirsiniz.)*

### Windows Güncelleme & Kaldırma
Masaüstünüzdeki **`Mandalina Güncelle.bat`** dosyasına çift tıklayabilir veya PowerShell'de şu komutları çalıştırabilirsiniz:

```powershell
# Güncelleme:
irm https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/update.ps1 | iex

# Kaldırma:
irm https://raw.githubusercontent.com/ssayoglu/mandalina-udf-converter/main/uninstall.ps1 | iex
```

---

## ✨ Öne Çıkan Özellikler (macOS & Windows)

### 🎯 1. Radyal Dönüşüm Çarkı & Menü Çubuğu / Sistem Tepsisi
- **macOS:** Dosya sürüklerken **`⇧ Shift`** (Format Dönüştürme Çarkı), **`⌘ Command`** (UYAP Araçları Çarkı), **`⌃ Control`** (Dosya İşlemleri Çarkı) veya üst menü çubuğundaki **`🍊`** simgesine sürükle-bırak.
- **Windows:** Herhangi bir yerde **`Shift + Alt + M`** (veya uygulama içinde **`Ctrl + Shift + M`**) kısayolu ile imlecinizin altında **12 dilimli Tangerine Radyal Çarkı** açılır. Dosyaları doğrudan çark dilimlerinin üzerine sürükleyip bırakabilir veya sağ alt **Windows Sistem Tepsisindeki (`🍊`)** simgeden tüm araçlara erişebilirsiniz.

### ⚖️ 2. Tam Uyumlu Yerel UYAP (`.udf`) Motoru
- **`UDF → PDF`:** Tüm paragraf hizalamalarını, kalın/italik/altı çizili biçimlendirmeleri ve tabloları (`<table>`) koruyarak Türkçe karakter uyumlu A4 PDF üretir.
- **`UDF → Word (`.docx`), HTML, RTF, TXT, Markdown`:** Tablo kenarlıklarını, hizalamaları ve yazı tiplerini koruyan standart belgeler oluşturur.
- **`DOCX / PDF / TIFF → UDF`:** Word, PDF ve görsel belgelerini UYAP Doküman Editörü'nde doğrudan açılabilen `.udf` formatına çevirir.

### 📑 3. Çok Sayfalı TIFF (`Multi-Page TIFF`) & UYAP Araçları
- **Çok Sayfalı `TIFF → PDF / UDF / DOCX`:** İcra ve mahkeme dosyalarındaki çok sayfalı `.tiff` / `.tif` taramalarının tüm sayfalarını tek hareketle A4 PDF'e veya UYAP `.udf` formatına dönüştürür.
- **UYAP Boyut Sıkıştır (`< 5 MB`):** Büyük PDF ve TIFF dosyalarını UYAP yükleme sınırına uygun şekilde sıkıştırır.
- **PDF & Evrak Birleştir (`Merge`):** Birden fazla `.udf`, `.tiff`, `.pdf` ve görsel dosyasını tek bir PDF belgesinde birleştirir.
- **Sayfaları Ayır (`Split`):** Çok sayfalı `.tiff` veya `.pdf` belgelerini tekil sayfa dosyalarına ayırır.

### 🔍 4. Dahili UDF & Çok Sayfalı TIFF Önizleyici + E-İmza Denetçisi
- `.udf` belgelerini UYAP Doküman Editörü açmadan e-imza (`sign.sgn`) sertifika bilgileri, SHA-256 özeti ve A4 sayfa görünümüyle anında görüntüleyin.
- Çok sayfalı `.tiff` dosyalarının sayfaları arasında ileri/geri gezinin.

---

## ⚖️ Lisans ve Geliştirici

- **Geliştirici:** Av. Lütfi Serkan SAYOĞLU
- **Lisans:** MIT
