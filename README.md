# 🚀 LaraNova API Engine — by Faiz

[![Laravel Version](https://img.shields.io/badge/Laravel-10%20%7C%2011%20%7C%2012-FF2D20?style=for-the-badge&logo=laravel)](https://laravel.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

**LaraNova API Engine** adalah bash script premium yang dirancang khusus untuk membangun **Pure Laravel API** dengan standar industri tertinggi (*Best Practices*). Lupakan konfigurasi manual yang membosankan—LaraNova menangani segalanya untuk Anda.

![LaraNova](https://github.com/faiz5437/setup-API-laravel-installer/assets/75693797/8a89c14d-15e2-4f1e-8cc7-34d63d872b3a)
---

## 🔥 Fitur Unggulan

- **🔐 Enterprise API Auth**: Integrasi **Laravel Sanctum** dengan sistem **OTP Berbasis Database** dan **Secure Password Reset Token**.
- **🆔 UUID by Default**: Otomatis mengonfigurasi UUID sebagai primary key untuk semua migrasi dan model demi keamanan data yang lebih baik.
- **🏗️ smart API CRUD Generator**: Cukup masukkan nama model dan field, LaraNova akan membuatkan Model, Migration, Controller (Base API), dan Route secara instan.
- **🛠️ Expert API Helpers**: Dilengkapi dengan `ResponseHelper` untuk standarisasi JSON response dan `ApiRequest` helper.
- **📬 Postman Collection Auto-Sync**: Setiap kali Anda membuat CRUD, LaraNova otomatis memperbarui file Postman Collection JSON Anda.
- **📦 Mandatory Packages**: Pre-installed **Laravel Telescope** (untuk debugging API) dan **Spatie Permission**.
- **🐳 Docker Optimized**: Disertai dengan `Dockerfile` dan `docker-compose.yml` yang sudah di-tuning untuk performa API.

---

## 🚀 Cara Instalasi (Magic Command)

Anda bisa langsung menjalankan LaraNova tanpa perlu download manual:

```bash
curl -sSL https://raw.githubusercontent.com/muhamadfaiz/LaraNova/main/laravel-installer.sh | bash
```

---

## 🛠️ Opsi Perintah

| Perintah | Deskripsi |
| :--- | :--- |
| `./laravel-installer.sh` | Mode Interaktif (Wizard) |
| `./laravel-installer.sh --quick` | Install cepat dengan konfigurasi default terbaik |
| `./laravel-installer.sh --help` | Menampilkan bantuan |

---

## 📊 Kebutuhan Sistem

- **PHP** >= 8.2
- **Composer**
- **Git**

---

<p align="center">Crafted with ❤️ by <b>Faiz</b></p>
