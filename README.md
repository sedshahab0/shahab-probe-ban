# Shahab Probe Ban

بن خودکار IP مهاجم از روی لاگ probe در nginx — با UFW و ویزارد تعاملی **انگلیسی** (سازگار با همه ترمینال‌ها).

> **نکته:** منوی تعاملی و ویزارد اسکریپت به **انگلیسی** است تا در ترمینال‌های وب/serial مشکل RTL فارسی پیش نیاید. این README فارسی است.

وقتی ربات‌ها یا اسکنرها مسیرهای غیرمجاز (مثل `/.env`، `/wp-admin`، `/phpmyadmin`) را بزنند، nginx آن‌ها را در یک فایل لاگ جدا می‌نویسد و این اسکریپت IPشان را با فایروال UFW مسدود می‌کند.

---

## پیش‌نیاز

| مورد | توضیح |
|------|--------|
| سیستم‌عامل | اوبونتو یا دبیان (root) |
| nginx | برای نوشتن لاگ probe |
| ufw | برای اعمال بن واقعی |
| curl | برای نصب یک‌خطی |

---

## نصب سریع (یک دستور)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sedshahab0/shahab-probe-ban/main/probe-ban.sh) --wizard
```

اگر `curl` نصب نیست:

```bash
apt-get update && apt-get install -y curl
```

---

## راهنمای پله‌به‌پله

### پله ۱ — دانلود (اختیاری)

اگر می‌خواهی فایل‌ها را روی سرور داشته باشی:

```bash
git clone https://github.com/sedshahab0/shahab-probe-ban.git
cd shahab-probe-ban
sudo bash probe-ban.sh --wizard
```

---

### پله ۲ — nginx را برای لاگ probe آماده کن

اسکریپت **خودش** nginx را تنظیم نمی‌کند. باید nginx درخواست‌های مشکوک را در یک فایل لاگ جدا بنویسد.

**۲.۱** فایل `/etc/nginx/probe-security.conf` بساز:

```nginx
# فرمت لاگ: IP + درخواست
log_format probe_format '$remote_addr "$request"';

# مسیرهای honeypot — هر درخواست = یک خط در probes.log
location ~* ^/(\.env|wp-admin|wp-login\.php|phpmyadmin|\.git|xmlrpc\.php) {
    access_log /var/log/nginx/probes.log probe_format;
    return 444;
}
```

**۲.۲** داخل بلوک `server { ... }` سایتت اضافه کن:

```nginx
include /etc/nginx/probe-security.conf;
```

**۲.۳** تست و reload:

```bash
nginx -t && systemctl reload nginx
```

**۲.۴** مطمئن شو فایل لاگ ساخته می‌شود:

```bash
touch /var/log/nginx/probes.log
chown www-data:adm /var/log/nginx/probes.log
```

> مسیر `/var/log/nginx/probes.log` همان پیش‌فرض ویزارد است. اگر مسیر دیگری می‌خواهی، در مرحله ۵ ویزارد همان را بده.

---

### پله ۳ — UFW را فعال کن

```bash
apt-get install -y ufw
ufw allow 22/tcp    # SSH — حتماً قبل از enable
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
ufw status
```

بدون UFW اسکریپت لاگ را می‌خواند ولی **بن واقعی اعمال نمی‌شود**.

---

### پله ۴ — ویزارد ۶ مرحله‌ای

```bash
sudo bash probe-ban.sh --wizard
```

با اجرا، بنر **SHAHAB** و منوی رنگی ظاهر می‌شود. Enter = پیش‌فرض.

#### مرحله ۱ — وایت‌لیست IP

**سؤال:** چند IP یا سرور دارید که **هرگز** نباید بن شوند؟

مثال‌ها:
- IP سرور backup
- IP مانیتورینگ (UptimeRobot و …)
- IP VPN یا دفتر
- IP سرور peer (اگر چند سرور داری)

برای هر IP یک آدرس IPv4 بده. اگر نداری، `0` بزن.

> **مهم:** IP خودت یا سرورهای داخلی را حتماً اینجا بده. وگرنه ممکن است اشتباهی بن شوند.

#### مرحله ۲ — بن خودکار

**سؤال:** بن خودکار IP مهاجم فعال باشد؟

- **بله (پیش‌فرض):** هر IP جدید در لاگ probe → UFW deny
- **خیر:** فقط لاگ خوانده می‌شود، بن نمی‌شود

#### مرحله ۳ — مدت بن

**سؤال:** مدت بن چند روز باشد؟

- **۳۰ (پیش‌فرض):** بعد از ۳۰ روز خودکار برداشته می‌شود
- **۰:** بن **دائمی** تا `--unban` دستی

#### مرحله ۴ — CDN / reverse proxy

**سؤال:** از CDN یا reverse proxy جلوی سرور استفاده می‌کنید؟

- **خیر (پیش‌فرض):** فقط IP واقعی client در لاگ است
- **بله:** CIDRهای CDN را با کاما بده

مثال (ArvanCloud):

```
185.143.232.0/22,94.101.182.0/27,188.229.116.16/30
```

> اگر CDN داری و CIDR نمی‌دهی، ممکن است IP پروکسی/CDN اشتباهی بن شود.

#### مرحله ۵ — مسیر لاگ probe

**سؤال:** مسیر فایل لاگ probe کجاست؟

پیش‌فرض: `/var/log/nginx/probes.log`

#### مرحله ۶ — تأیید نهایی

خلاصه تنظیمات در یک جدول نشان داده می‌شود. با **بله** تأیید کن.

**بعد از تأیید اسکریپت این کارها را می‌کند:**

| کار | مسیر |
|-----|------|
| ذخیره تنظیمات | `/etc/probe-ban/security.env` |
| نصب اسکریپت | `/usr/local/sbin/probe-ban.sh` |
| فعال‌سازی cron | `/etc/cron.d/probe-ban` |
| ساخت پوشه state | `/var/lib/probe-ban/` |

**زمان‌بندی cron (پیش‌فرض):**

- هر **۵ دقیقه:** خواندن لاگ و بن IP جدید
- هر روز **۴:۱۵:** حذف بن‌های منقضی‌شده

---

### پله ۵ — تست

**۵.۱ — dry-run (بدون بن واقعی):**

```bash
sudo probe-ban.sh --dry-run
```

**۵.۲ — یک probe تستی بزن** (از IP دیگری، نه IP وایت‌لیست):

```bash
curl -k "https://YOUR-DOMAIN/.env"
```

**۵.۳ — چند دقیقه صبر کن** (cron هر ۵ دقیقه) یا دستی اجرا کن:

```bash
sudo probe-ban.sh run
```

**۵.۴ — وضعیت را ببین:**

```bash
sudo probe-ban.sh --status
```

باید IP مهاجم در لیست بن‌ها و در `ufw status` دیده شود.

---

## منوی تعاملی

بدون آرگومان و با ترمینال:

```bash
sudo bash probe-ban.sh
```

| گزینه | کار |
|-------|-----|
| **۱** | راه‌اندازی / تنظیم دوباره (ویزارد) |
| **۲** | نمایش وضعیت بن‌ها |
| **۳** | dry-run (تست بدون بن) |
| **۰** | خروج |

---

## دستورات

| دستور | توضیح |
|--------|--------|
| `probe-ban.sh --wizard` | ویزارد راه‌اندازی |
| `probe-ban.sh run` | پردازش لاگ (برای cron) |
| `probe-ban.sh --status` | لیست IPهای بن‌شده |
| `probe-ban.sh --dry-run` | پیش‌نمایش — بدون بن واقعی |
| `probe-ban.sh --unban IP` | حذف بن یک IP |
| `probe-ban.sh --expire` | پاک کردن بن‌های منقضی |
| `probe-ban.sh --report` | گزارش (اگر تلگرام فعال باشد) |
| `probe-ban.sh --help` | راهنمای کوتاه |

---

## فایل‌ها و تنظیمات روی سرور

| مسیر | کار |
|------|-----|
| `/etc/probe-ban/security.env` | تنظیمات اصلی |
| `/var/lib/probe-ban/banned-ips.tsv` | لیست بن‌ها (IP + زمان + انقضا) |
| `/var/lib/probe-ban/probe-ban.log` | لاگ عملیات اسکریپت |
| `/var/lib/probe-ban/probe-ban-cron.log` | خروجی cron |
| `/var/log/nginx/probes.log` | لاگ probe nginx |
| `/usr/local/sbin/probe-ban.sh` | اسکریپت نصب‌شده |
| `/etc/cron.d/probe-ban` | زمان‌بندی |

### متغیرهای env (دستی)

نمونه کامل: [`security.env.example`](security.env.example)

| متغیر | معنی | پیش‌فرض |
|--------|------|---------|
| `PROBE_BAN_WHITELIST_IPS` | IPهای مجاز (کاما) | خالی |
| `PROBE_BAN_AUTO_BAN` | بن خودکار (۱/۰) | ۱ |
| `PROBE_BAN_TTL_DAYS` | مدت بن (روز) | ۳۰ |
| `PROBE_BAN_TRUSTED_CIDRS` | CIDRهای CDN | خالی |
| `PROBE_BAN_PROBE_LOG` | مسیر لاگ probe | `/var/log/nginx/probes.log` |
| `PROBE_BAN_SERVER_LABEL` | نام سرور در گزارش | hostname |

---

## عیب‌یابی

### بن نمی‌شود

```bash
# ufw فعال است؟
ufw status

# لاگ probe چیزی دارد؟
tail -20 /var/log/nginx/probes.log

# env درست است؟
cat /etc/probe-ban/security.env

# cron اجرا شده؟
tail -20 /var/lib/probe-ban/probe-ban-cron.log
grep probe-ban /var/log/syslog
```

### IP خودم بن شدم

```bash
sudo probe-ban.sh --unban YOUR.IP.HERE
```

IP را به `PROBE_BAN_WHITELIST_IPS` در `/etc/probe-ban/security.env` اضافه کن و دوباره `--wizard` بزن.

### nginx لاگ نمی‌نویسد

```bash
nginx -t
ls -la /var/log/nginx/probes.log
# مطمئن شو include probe-security.conf در server block هست
```

---

## حذف / غیرفعال‌سازی

```bash
# توقف cron
sudo rm -f /etc/cron.d/probe-ban

# حذف اسکریپت و تنظیمات (اختیاری)
sudo rm -f /usr/local/sbin/probe-ban.sh
sudo rm -rf /etc/probe-ban /var/lib/probe-ban

# قوانین ufw با comment probe-ban را دستی پاک کن:
sudo ufw status numbered
```

---

## لایسنس

MIT — [`LICENSE`](LICENSE)

---

## English

See [README.en.md](README.en.md).
