# stockpile_by_string.tcl

Makro Surpac untuk menghitung **volume dan tonase beberapa stockpile dalam satu file `.str`**, satu string satu
stockpile, masing-masing dengan **dasar Auto Toe** dan **berat jenisnya sendiri**.

Dasar stockpile tidak perlu survei terpisah. Untuk tiap string, titik-titik berelevasi terendah dianggap **toe**
(kaki timbunan), garis luarnya dipakai membentuk dasar, lalu volume dihitung di atas dasar itu.

Seluruh tampilan berbahasa Indonesia, termasuk format angka (`1.234,56`).

## Berkas yang dibutuhkan

Hanya satu: **`stockpile_by_string.tcl`**. Makro ini mandiri, tanpa Python dan tanpa berkas pendamping. Seluruh
hitungan ada di dalam makro (Tcl), dan file `.str` dibaca lewat perintah bawaan Surpac.

(Versi sebelumnya memanggil `stockpile_by_string.py` dan `surpac_volume.py` lewat Python. Berkas itu hilang dari
folder proyek, dan jalur Python yang tertanam di makro membuatnya mudah rusak, jadi hitungannya dipindahkan ke makro.)

## Persyaratan

- **Surpac 7.9** (makro memakai Tcl bawaan Surpac). Tidak ada yang perlu dipasang.

Tidak ada pengaturan wajib. Satu-satunya variabel di bagian atas makro:

| Variabel | Arti |
|---|---|
| `svMaxPiles` | Jumlah string maksimum yang ditampilkan di tabel langkah 2. Default `20`. |

## Cara menjalankan

1. Tekan **F6** (Macro Playback). Alternatifnya, ketik `MACRO PLAYBACK` di Function Chooser, atau klik tombol segitiga
   hijau di toolbar.
2. Ketik path makro **dengan ekstensi `.tcl`**, mis. `F:\Project\Surpac\Result\stockpile_by_string.tcl`. Tanpa
   ekstensi, Surpac menganggapnya makro lama `.cmd`.
3. Klik **Apply**, lalu ikuti tiga langkah di bawah. Menekan **Cancel** di langkah mana pun menghentikan makro
   (pesan "Dibatalkan.").

## Langkah di dalam makro

### Langkah 1: pilih file

Pilih file `.str` (teks atau biner). File harus ada. Makro membacanya dan mencari string yang ada di dalamnya.

### Langkah 2: tabel stockpile

Satu baris per string yang ditemukan. Nomor string dan jumlah titiknya terisi otomatis dan tidak bisa diubah.

| Isian | Keterangan |
|---|---|
| **Nama** (opsional) | Nama stockpile di laporan. Tanpa koma dan tanpa tanda kutip. Kosong = "Stockpile N". |
| **Berat jenis t/m3** | Antara 0,05 dan 20. Kosong = hanya volume, tanpa ton. Titik atau koma desimal sama-sama diterima (`1.8` atau `1,8`). |
| **Abaikan string** | Nomor string yang bukan stockpile, mis. `3,5`. Tidak dihitung. |
| **Jenis dasar** | Tanpa centang: **TIN** dari toe, mengikuti ketinggian toe (disarankan). Dicentang: satu **bidang best-fit**, cocok untuk tanah datar dan rata. |
| **Toleransi toe** | Kosong = otomatis (disarankan). Diisi: titik dalam ketinggian itu dari titik terendah sebuah string dianggap toe-nya, dipakai apa adanya. |
| **Garis toe** | Dicentang: toe disimpan sebagai `<nama file>_toe.str` di samping file input (satu string tertutup per stockpile, bernomor sama), lalu dibuka di Surpac sebagai layer `toe_by_string` untuk diperiksa. |
| **Simpan laporan CSV** | Opsional. |

Tabel menampilkan paling banyak `svMaxPiles` string. Jika file punya lebih banyak, yang pertama ditampilkan dan ada
catatan berwarna merah.

Makro menolak isian yang salah sebelum menghitung: nama berkoma atau bertanda kutip, berat jenis bukan angka di
atas nol, toleransi bukan angka, atau semua string diabaikan.

### Langkah 3: hasil

Tabel dengan kolom **String, Nama, Luas m2, Volume bersih m3, t/m3, Ton, Cek**, plus baris **TOTAL**, dan di atasnya
ringkasan total volume bersih dan total ton. Kolom **Cek** berisi:

- `OK`: tidak ada peringatan,
- `Periksa`: ada peringatan, lihat jendela pesan,
- `GAGAL`: string itu tidak bisa dihitung (mis. kurang dari 3 titik). String lain tetap dihitung.

Laporan lengkap juga dicetak di jendela pesan Surpac:

```
String  Nama                   Luas m2    Di atas m3   Di bawah m3     Bersih m3   t/m3           Ton
     1  Stockpile 1           3.246,27      6.040,77        125,61      5.915,17   0,80       4.732,1
     2  Stockpile 2           5.967,78      8.875,28        263,08      8.612,20   0,80       6.889,8
 TOTAL                        9.214,06     14.916,05        388,68     14.527,37             11.621,9
```

*Di atas* dan *di bawah* adalah volume di atas dan di bawah dasar; *bersih* = di atas − di bawah;
**Ton = volume bersih × berat jenis**. Angka di atas dihitung dari `2 stock.str` dengan berat jenis 0,8 (ilustrasi).

## Cara kerja Auto Toe

Untuk tiap string, secara terpisah (titik satu stockpile tidak memengaruhi stockpile lain):

1. Titik yang elevasinya dalam suatu toleransi dari titik terendah string itu dianggap toe. Toleransi mulai dari 5%
   rentang tinggi.
2. **Garis luar cembung** titik-titik toe menjadi batas. Jika masih ada titik di luarnya, toleransi dilebarkan
   (×1,5) sampai semua titik tercakup. Ini perlu pada tanah miring, tempat hanya sebagian toe yang dekat dengan titik
   terendah. Pada mode otomatis, hasil akhirnya selalu garis luar cembung seluruh titik string; toleransi menentukan
   berapa titik yang dihitung sebagai "band toe" dan memicu peringatan di bawah.
3. Dasar dibentuk dari titik sudut garis toe: TIN (interpolasi linear) atau bidang best-fit (kuadrat terkecil atas
   sudut-sudut toe).
4. Titik di dalam batas ditriangulasi (Delaunay). Triangulasi menutup tepat seluruh poligon toe, jadi luas hasilnya
   sama dengan luas poligon toe.
5. Volume tiap segitiga dihitung eksak, termasuk bagian yang memotong dasar. Elevasi dasar diambil di tiap titik
   permukaan, lalu dianggap linear di dalam segitiga.

## Peringatan dan batasan

Status `Periksa` muncul jika salah satu ini terjadi:

- toleransi toe melebar lewat 50% rentang tinggi. Artinya toe praktis adalah tepi data string itu (tanah miring, atau
  data bukan satu timbunan);
- ada titik di luar garis toe yang diabaikan (hanya pada toleransi manual);
- volume di bawah dasar lebih dari 10% volume di atasnya, sehingga dasar mungkin tidak cocok.

Batasan yang perlu diingat:

- **Dasar menentukan hasil.** Dasar adalah interpolasi dari toe, jadi anggapannya tanah di bawah timbunan mulus dan
  menyambung dengan toe. Pada data contoh, memilih TIN atau bidang menggeser volume bersih sekitar 15–17%
  (string 1: −15%, string 2: +17%). Untuk angka yang lebih tegas, gambar string toe di kaki tiap timbunan.
- **Garis toe selalu cembung.** Timbunan dengan cekungan dalam (mis. berbentuk L) tercakup berlebih.
- **Satu titik rendah yang jauh** dari timbunan ikut meregangkan garis luar. Bersihkan data seperti itu dulu.
- **Satu timbunan per string.** String yang berisi seluruh stockyard memberi angka yang tidak bermakna.
- Beberapa segmen dalam satu string digabung menjadi satu kumpulan titik. Titik duplikat (X,Y sama) dipakai sekali.
  Titik dengan Z = −999 dilewati.
- TIN sedikit di bawah permukaan yang melengkung (pada kerucut uji, selisih 0,3–0,7%).
- Hasil **belum dibandingkan** dengan volume DTM Surpac. Selisih kecil wajar karena triangulasi dan batas berbeda.
  Pembandingnya di Surpac: fungsi `DTM VOLUMES`.
- Kecepatan: kira-kira 1–2 detik untuk 30.000 titik per string pada Tcl 9; Tcl 8.5 milik Surpac mungkin beberapa
  kali lebih lambat. Antarmuka Surpac tidak merespons selama menghitung.

## File yang dibaca dan dihasilkan

**Dibaca:** hanya `.str`. Makro memakai string sebagai pembeda stockpile. `.str` teks dibaca langsung
(rekaman `string, Y, X, Z, deskripsi`, urutan Surpac: Y dulu); `.str` biner dibaca lewat perintah Surpac
`SclSwaOpenFile`, jadi tata letak biner tidak perlu ditebak.

**Dihasilkan:**

- `<nama file>_toe.str`, bila "Garis toe" dicentang. Layer `toe_by_string` di Surpac diganti pada tiap jalan.
- Laporan CSV, bila Anda mengisi namanya. Nama kolomnya tetap Inggris dan angkanya memakai titik desimal (format data):
  `string, name, points, toe_band_points, toe_tolerance, toe_vertices, plan_area_m2, surface_area_m2, volume_above_m3,
  volume_below_m3, net_volume_m3, density_t_m3, tonnes, status`, ditambah baris `TOTAL`.

Tidak ada file sementara.

## Pemecahan masalah

Jika makro gagal, buka jendela pesan Surpac dan gulir ke atas: pesan galat dan nomor barisnya ada di sana.

| Gejala | Penyebab dan solusi |
|---|---|
| `Tidak ada string berisi titik di ...` | File kosong, atau tidak bisa dibaca. Pesan galat dari Surpac ada di baris berikutnya; simpan sebagai `.str` teks di Surpac. |
| `berat jenis ... harus angka di atas nol` | Isi angka positif, mis. `1.8` atau `1,8`. |
| `Tidak ada yang dihitung: semua string diabaikan` | Isian "Abaikan string" mencakup semua string di tabel. |
| Status `Periksa` pada semua stockpile | Toe praktis adalah tepi data. Periksa dengan "Garis toe", atau gambar string toe sendiri. |
| `GAGAL: toleransi toe terlalu kecil` | Toleransi manual hanya menjangkau kurang dari 3 titik. Naikkan, atau kosongkan untuk otomatis. |
| `CATATAN: toe tersimpan ... tetapi tidak bisa ditampilkan otomatis` | Hitungan tetap benar. Buka file `*_toe.str` itu dengan fungsi `OPEN FILE` secara manual. |
| Tabel hanya menampilkan sebagian string | Naikkan `svMaxPiles` di bagian atas makro. |

## Status pengujian

**Teruji** (di luar Surpac, dengan Tcl yang sama bahasanya dan perintah Surpac dipalsukan):

- Mesin hitung direkonstruksi lalu dibandingkan dengan keluaran mesin Python sebelumnya pada `2 stock.str`. Laporan
  CSV dan file toe yang dihasilkan makro **identik** dengan keluaran lama (CSV sama persis per byte; poligon toe tanpa
  selisih).
- Triangulasi Delaunay diperiksa pada titik acak, bergerombol, grid (kocircular), hampir segaris, dan 30.000 titik:
  jumlah segitiga, luas (sama dengan luas garis luar cembung), sifat lingkaran kosong, dan orientasi semuanya benar.
- Hasil Tcl sama dengan implementasi Python independen hingga 1e-11 pada timbunan sintetis.
- Alur dialog (tiga langkah, batal, isian salah, file kosong, toleransi manual, bidang best-fit, jalur baca biner).

**Belum dikonfirmasi di Surpac sungguhan:**

- tampilan form (langkah 1–3; kolom "Titik" baru di langkah 2),
- pembacaan `.str` biner lewat `SclSwaOpenFile` dan penampilan toe sebagai layer. Keduanya mengikuti contoh di manual
  Surpac 7.9, tetapi belum dijalankan di Surpac,
- mode **bidang best-fit**: angkanya wajar (selisih 15–17% dari TIN, sesuai catatan lama), tetapi tidak bisa
  dibandingkan dengan mesin lama karena keluaran lamanya hanya ada untuk TIN.

Jika ada yang tidak tampil seperti yang dimaksud, salin pesan dari jendela pesan Surpac.
