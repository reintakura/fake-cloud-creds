# fake-cloud-creds

Generator kredensial **dummy** (non-fungsional) untuk simulasi adversary / purple-team yang **sudah diotorisasi**.

Membuat decoy / honeytoken berbentuk file kredensial cloud palsu di macOS dan Linux. Semua artefak mengandung penanda `ADVSIM-DUMMY` + run id, dan **tidak bisa** dipakai login ke layanan sungguhan.

> Hanya untuk latihan / honeypot di mesin yang Anda kontrol. Jangan jalankan ke mesin bersama tanpa izin.

## Cepat mulai

```bash
git clone git@github.com:reintakura/fake-cloud-creds.git
cd fake-cloud-creds
./gen-creds.sh                          # tulis ke ./decoy-home
./gen-creds.sh --target ./decoy-home    # eksplisit
./cleanup.sh --target ./decoy-home      # hapus hanya yang digenerate
```

One-liner (hanya jalan kalau repo **public**; repo ini private → pakai clone via `gh`):

```bash
curl -fsSL https://raw.githubusercontent.com/reintakura/fake-cloud-creds/main/gen-creds.sh | bash -s -- --target ./decoy-home
```

Clone private:

```bash
gh repo clone reintakura/fake-cloud-creds
```

## Opsi `gen-creds.sh`

| Opsi | Arti |
|------|------|
| `--target DIR` | Root keluaran (default `./decoy-home`). Layout seperti `$HOME`. |
| `--only LIST` | `aws`, `gcp`, `azure`, `other` (koma-pisah). Default: semua. |
| `--profile NAME` | Basis nama profil AWS (default `advsim`). |
| `--project ID` | `project_id` GCP (default `advsim-dummy-project`). |
| `--append` | Kalau `~/.aws/credentials` sudah ada, tambah profil `[advsim-<id>]`. |
| `--dry-run` | Cetak rencana, tidak menulis file. |
| `-h` / `-v` | Bantuan / versi. |

Tidak pernah menimpa file yang sudah ada (skip + warning), kecuali `--append` untuk profil AWS.

## File yang dibuat

Di bawah `--target` (contoh `./decoy-home`):

- `.aws/credentials`, `.aws/config`
- `.config/gcloud/advsim-sa-<runid>.json` (service account)
- `.config/gcloud/application_default_credentials.json`
- `.azure/azureProfile.json`, `.azure/advsim-sp-<runid>.env`
- `.kube/config`
- `.docker/config.json`
- `.git-credentials` (sengaja **bukan** format `ghp_` / `glpat_`)
- `.npmrc`
- `.config/doctl/config.yaml`, `.config/heroku/config.json`
- `.env` (DB URL + token generik)
- `.advsim-manifest-<runid>` — daftar file untuk cleanup

## Cleanup

```bash
./cleanup.sh --target ./decoy-home           # manifest terbaru
./cleanup.sh --target ./decoy-home --all     # semua manifest
./cleanup.sh --target ./decoy-home --dry-run
```

Sebelum menghapus, setiap file dicek masih mengandung `ADVSIM-DUMMY`. Profil AWS yang di-`--append` di-strip dengan backup `.bak.advsim`.

## Canary (opsional)

Kalau Anda punya canary key dari [canarytokens.org](https://canarytokens.org/):

```bash
export AWS_CANARY_KEY_ID='AKIA...'
export AWS_CANARY_SECRET='...'
./gen-creds.sh --only aws --target ./decoy-home
```

Pemakaian decoy key itu akan memicu alert canary.

## Keamanan

- Tolak dijalankan sebagai root.
- Default output = `./decoy-home`, **bukan** `$HOME`.
- `--target "$HOME"` hanya di host decoy khusus milik Anda.
- Jangan commit keluaran generator (sudah di `.gitignore`).
- Repo ini private. Jangan jadikan public tanpa review (secret scanning GitHub bisa salah flag format realistis).

## Kompatibilitas

Diuji di Linux Bash. Ditulis agar jalan di **macOS Bash 3.2** default (tanpa associative array, tanpa `${var,,}`, tanpa `mapfile`, tanpa flag GNU-only). `openssl` opsional (fallback `/dev/urandom`).

## Lisensi

MIT — lihat `LICENSE`.
