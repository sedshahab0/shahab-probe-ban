# Shahab Probe Ban

اسکریپت بن خودکار IP مهاجم از روی لاگ probe در nginx. وقتی کسی مسیرهای honeypot را بزند، IP با UFW مسدود می‌شود.

## نصب سریع

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sedshahab0/shahab-probe-ban/main/probe-ban.sh) --wizard
```

دسترسی root روی اوبونتو/دبیان لازم است. اگر `curl` نصب نیست:

```bash
apt-get install -y curl
```

یا:

```bash
git clone https://github.com/sedshahab0/shahab-probe-ban.git
cd shahab-probe-ban
sudo bash probe-ban.sh --wizard
```

---

## پله ۱ — nginx را برای لاگ probe آماده کن

اسکریپت فقط IPهایی را بن می‌کند که nginx در **فایل لاگ probe** ثبت کرده باشد.

یک فایل مثل `/etc/nginx/probe-security.conf`:

```nginx
# مسیرهای honeypot — هر درخواست = یک خط در probes.log
location ~* ^/(\.env|wp-admin|phpmyadmin|\.git) {
    access_log /var/log/nginx/probes.log probe_format;
    return 444;
}

log_format probe_format '$remote_addr "$request"';
```

در `server { ... }`:

```nginx
include /etc/nginx/probe-security.conf;
```

سپس:

```bash
nginx -t && systemctl reload nginx
```

مسیر لاگ را در ویزارد همان `/var/log/nginx/probes.log` بگذار (یا هر مسیری که انتخاب کردی).

---

## پله ۲ — UFW را فعال کن

```bash
apt-get install -y ufw
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

بدون UFW اسکریپت لاگ را می‌خواند ولی بن واقعی اعمال نمی‌شود.

---

## پله ۳ — ویزارد ۶ مرحله‌ای

```bash
sudo bash probe-ban.sh --wizard
```

| مرحله | سؤال | پیش‌فرض |
|-------|------|---------|
| ۱ | چند IP وایت‌لیست؟ (IP هر کدام) | ۰ |
| ۲ | بن خودکار فعال باشد؟ | بله |
| ۳ | مدت بن (روز) — ۰ = دائمی | ۳۰ |
| ۴ | CDN / reverse proxy دارید؟ → CIDRها | خیر |
| ۵ | مسیر لاگ probe | `/var/log/nginx/probes.log` |
| ۶ | تأیید نهایی | — |

بعد از تأیید:

- تنظیمات → `/etc/probe-ban/security.env`
- اسکریپت → `/usr/local/sbin/probe-ban.sh`
- cron → `/etc/cron.d/probe-ban` (هر ۵ دقیقه چک + expire روزانه)

---

## پله ۴ — تست

```bash
# بدون بن واقعی — فقط نشان می‌دهد چه IPهایی بن می‌شدند
sudo probe-ban.sh --dry-run

# وضعیت فعلی
sudo probe-ban.sh --status
```

یک درخواست تست به مسیر honeypot (مثلاً `/.env`) بزن، چند دقیقه صبر کن، دوباره `--status` بزن.

---

## دستورات روزمره

```bash
probe-ban.sh --status          # لیست بن‌ها
probe-ban.sh --unban 1.2.3.4   # حذف بن یک IP
probe-ban.sh --expire          # پاک کردن بن‌های منقضی
probe-ban.sh --dry-run         # تست بدون اعمال
probe-ban.sh --wizard          # تنظیم دوباره
probe-ban.sh                   # منوی تعاملی (با TTY)
probe-ban.sh run               # پردازش لاگ (برای cron)
```

---

## منوی تعاملی

بدون آرگومان و با ترمینال:

```bash
sudo bash probe-ban.sh
```

گزینه‌ها:

1. راه‌اندازی / تنظیم دوباره (ویزارد)
2. نمایش وضعیت
3. dry-run
0. خروج

---

## وایت‌لیست — مهم

**حتماً** IP سرورهای خودت، مانیتورینگ و VPN را در مرحله ۱ ویزارد بده. وگرنه ممکن است IP خودت بن شود.

اگر CDN دارید، CIDRهای CDN را در مرحله ۴ بده تا IP پروکسی اشتباهی بن نشود.

---

## فایل‌ها روی سرور

| مسیر | کار |
|------|-----|
| `/etc/probe-ban/security.env` | تنظیمات |
| `/var/lib/probe-ban/banned-ips.tsv` | لیست بن‌ها |
| `/var/log/nginx/probes.log` | لاگ probe (پیش‌فرض) |
| `/usr/local/sbin/probe-ban.sh` | اسکریپت نصب‌شده |
| `/etc/cron.d/probe-ban` | زمان‌بندی |

---

## عیب‌یابی

```bash
# ufw فعال است؟
ufw status

# cron اجرا شده؟
grep probe-ban /var/log/syslog
tail /var/lib/probe-ban/probe-ban-cron.log

# لاگ probe چیزی دارد؟
tail /var/log/nginx/probes.log

# env
cat /etc/probe-ban/security.env
```

---

## English

See [README.md](README.md).
