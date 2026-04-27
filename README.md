# 🚀 LaraNova API Engine — by Faiz

[![Laravel Version](https://img.shields.io/badge/Laravel-10%20%7C%2011%20%7C%2012-FF2D20?style=for-the-badge&logo=laravel)](https://laravel.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)

**LaraNova API Engine** adalah bash script premium yang dirancang khusus untuk membangun **Pure Laravel API** dengan standar industri tertinggi (*Best Practices*). Lupakan konfigurasi manual yang membosankan—LaraNova menangani segalanya untuk Anda dalam hitungan menit.

![LaraNova](https://github.com/faiz5437/setup-API-laravel-installer/assets/75693797/8a89c14d-15e2-4f1e-8cc7-34d63d872b3a)

---

## 🔥 Fitur Unggulan

- **🔐 Enterprise API Auth**: Integrasi **Laravel Sanctum** dengan sistem **OTP Berbasis Database** dan **Secure Password Reset Token**.
- **🆔 UUID by Default**: Otomatis mengonfigurasi UUID sebagai primary key untuk semua migrasi dan model demi keamanan data yang lebih baik.
- **🏗️ Smart API CRUD Generator**: Cukup masukkan nama model dan field, LaraNova akan membuatkan Model, Migration, Controller (Base API), dan Route secara instan.
- **🛠️ Expert API Helpers**: Dilengkapi dengan `ResponseHelper` untuk standarisasi JSON response dan `ApiRequest` helper untuk komunikasi antar-layanan.
- **📬 Postman Collection Auto-Sync**: Setiap kali Anda membuat CRUD, LaraNova otomatis memperbarui file Postman Collection JSON Anda.
- **📦 Mandatory Packages**: Pre-installed **Laravel Telescope** (untuk debugging API) dan **Spatie Permission** (Roles & Permissions).
- **🐳 Docker Optimized**: Disertai dengan `Dockerfile` dan `docker-compose.yml` yang sudah di-tuning untuk performa API.
- **🔄 Existing Project Support**: Tidak hanya untuk project baru, Anda bisa menjalankan script ini di project Laravel yang sudah ada untuk menambah fitur atau CRUD.

---

## 🚀 Cara Instalasi (Magic Command)

Anda bisa langsung menjalankan LaraNova tanpa perlu download manual:

```bash
curl -sSL https://raw.githubusercontent.com/faiz5437/setup-API-laravel-installer/main/laravel-installer.sh | bash
```

### 🛠️ Opsi Perintah

| Perintah | Deskripsi |
| :--- | :--- |
| `./laravel-installer.sh` | **Interactive Mode**: Wizard langkah-demi-langkah (Direkomendasikan) |
| `./laravel-installer.sh --quick` | **Quick Mode**: Install kilat dengan best-practice default |
| `./laravel-installer.sh --help` | Menampilkan bantuan & daftar environment variables |

---

## 📖 Cara Penggunaan

### 1. Membuat Project Baru
Jalankan magic command di atas, pilih **[1] Install Laravel Baru**, dan ikuti wizardnya. Script akan menanyakan versi Laravel, konfigurasi database, dan fitur yang ingin diaktifkan.

### 2. Menggunakan di Project Existing
Jika Anda sudah punya project Laravel, copy script ini ke root project Anda dan jalankan. Anda bisa memilih **[2] Generate CRUD Baru** untuk membuat modul API secara instan.

### 3. Otomasi (CI/CD atau Scripting)
Gunakan environment variables untuk instalasi tanpa interaksi:
```bash
INSTALL_PATH=my-api \
DB_NAME=my_db \
GENERATE_CRUD=y \
CRUD_MODEL=Product \
CRUD_FIELDS=name:string,price:integer \
./laravel-installer.sh --no-interaction
```

---

## 📊 Kebutuhan Sistem

- **PHP** >= 8.1
- **Composer** (Latest)
- **Git**
- **Docker** (Opsional, untuk fitur Docker setup)

---

## 🤝 Kontribusi
Punya ide untuk fitur baru? Silakan buka **Issue** atau kirim **Pull Request**. Mari kita buat development Laravel API jadi lebih menyenangkan!

<p align="center">Crafted with ❤️ by <b>Faiz</b></p>
