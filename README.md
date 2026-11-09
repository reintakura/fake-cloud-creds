# fake-cloud-creds

Script Bash untuk membuat credential cloud **dummy** (tidak berfungsi) sebagai decoy atau honeytoken. Dibuat untuk adversary simulation dan purple team exercise yang **sudah mendapat izin**.

Jalan di macOS dan Linux. Setiap file yang dibuat berisi marker `ADVSIM-DUMMY` beserta run id, dan **tidak bisa** dipakai untuk login ke service mana pun.

> Gunakan hanya di mesin yang Anda kelola sendiri, untuk lab atau honeypot. Jangan jalankan di mesin bersama tanpa izin pemiliknya.

## Quick start

```bash
git clone https://github.com/reintakura/fake-cloud-creds.git
cd fake-cloud-creds
chmod +x gen-creds.sh cleanup.sh

./gen-creds.sh --dry-run                # lihat dulu apa yang akan dibuat
./gen-creds.sh --target ./decoy-home    # buat semua credential dummy
./cleanup.sh --target ./decoy-home      # hapus lagi semua file yang tadi dibuat
```

Atau tanpa clone, langsung lewat one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/reintakura/fake-cloud-creds/main/gen-creds.sh | bash -s -- --target ./decoy-home
curl -fsSL https://raw.githubusercontent.com/reintakura/fake-cloud-creds/main/cleanup.sh  | bash -s -- --target ./decoy-home
```

## Contoh pemakaian

```bash
./gen-creds.sh --only aws,gcp --target ./decoy-home       # hanya AWS dan GCP
./gen-creds.sh --target "$HOME"                           # tanam di home directory host decoy
./gen-creds.sh --target "$HOME" --only aws --append       # tambah profile [advsim-<id>] ke ~/.aws/credentials
./gen-creds.sh --profile staging --project acme-prod-123  # ganti nama profile AWS dan GCP project_id
```

## Options `gen-creds.sh`

| Option | Fungsi |
|--------|--------|
| `--target DIR` | Folder output (default `./decoy-home`). Struktur foldernya meniru `$HOME`. |
| `--only LIST` | Pilih provider: `aws`, `gcp`, `azure`, `other`, dipisah koma. Default semua. |
| `--profile NAME` | Nama dasar AWS profile (default `advsim`). |
| `--project ID` | GCP `project_id` (default `advsim-dummy-project`). |
| `--append` | Kalau `~/.aws/credentials` sudah ada, tambahkan profile `[advsim-<id>]` di file itu. |
| `--dry-run` | Hanya menampilkan rencana, tidak ada file yang ditulis. |
| `-h` / `-v` | Help / version. |

File yang sudah ada **tidak pernah ditimpa**: script akan skip dan menampilkan warning. Satu-satunya pengecualian adalah `--append` untuk AWS profile.

## File yang dibuat

Semua file dibuat di dalam `--target` (contohnya `./decoy-home`):

- `.aws/credentials`, `.aws/config`
- `.config/gcloud/advsim-sa-<runid>.json` (service account key)
- `.config/gcloud/application_default_credentials.json`
- `.azure/azureProfile.json`, `.azure/advsim-sp-<runid>.env` (service principal)
- `.kube/config`
- `.docker/config.json`
- `.git-credentials` (sengaja **tidak** memakai format token `ghp_` / `glpat_`)
- `.npmrc`
- `.config/doctl/config.yaml` (DigitalOcean), `.config/heroku/config.json`
- `.env` (database URL dan token generic)
- `.advsim-manifest-<runid>`, yaitu daftar file yang dipakai saat cleanup

## Cleanup

```bash
./cleanup.sh --target ./decoy-home            # hapus hasil run terakhir
./cleanup.sh --target ./decoy-home --all      # hapus hasil semua run
./cleanup.sh --target ./decoy-home --dry-run  # cek dulu apa yang akan dihapus
```

`cleanup.sh` hanya menghapus file yang tercatat di manifest, dan sebelum menghapus setiap file selalu dicek dulu apakah marker `ADVSIM-DUMMY` masih ada. Credential asli Anda tidak akan tersentuh. AWS profile yang ditambahkan lewat `--append` juga dihapus, dengan backup ke `.bak.advsim`.

## Canary token (opsional)

Kalau Anda punya AWS key dari [canarytokens.org](https://canarytokens.org/), pakai key itu supaya muncul alert ketika ada yang mencoba memakainya:

```bash
export AWS_CANARY_KEY_ID='AKIA...'
export AWS_CANARY_SECRET='...'
./gen-creds.sh --only aws --target "$HOME"
```

## Keamanan

- Script menolak jalan sebagai root.
- Default output ke `./decoy-home`, **bukan** `$HOME`.
- Gunakan `--target "$HOME"` hanya di host decoy milik Anda sendiri.
- Jangan commit hasil generate (sudah masuk `.gitignore`).
- Repo ini public, jadi marker `ADVSIM-DUMMY` bisa dikenali oleh attacker yang teliti. Untuk honeypot yang serius, kombinasikan dengan canary token asli.

## Kompatibilitas

Sudah dites di Bash Linux. Script ditulis supaya kompatibel dengan **Bash 3.2 bawaan macOS**: tidak memakai associative array, `${var,,}`, `mapfile`, maupun flag yang hanya ada di GNU. `openssl` bersifat opsional; kalau tidak ada, script memakai `/dev/urandom`.

## License

MIT, lihat `LICENSE`.
