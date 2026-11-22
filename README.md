<div dir="rtl">

# Kashi (کاشی)

قالب صفحه اشتراک برای پنل **PasarGuard**، با طراحی تخت و رنگی، زمینه کرم، قاب‌های ضخیم و بلوک‌های رنگی شبیه کاشی‌کاری.

<p align="center">
  <img src="preview.png" width="360" alt="Kashi">
</p>

## امکانات

- نمایش نام کاربر و وضعیت اشتراک
- حجم و زمان باقیمانده با نوار پیشرفت
- لیست کانفیگ‌ها با دکمه کپی، نمایش QR و کپی همه کانفیگ‌ها
- معرفی و لینک دانلود اپلیکیشن Happ برای اندروید و آیفون
- فونت Vazirmatn و چیدمان راست‌به‌چپ
- سازگار با موبایل

## دو نسخه قالب

| نسخه | فایل | توضیح |
|------|------|-------|
| **v1** | `index.html` (ریشه ریپو) | قالب ساده، بدون منوی بالا |
| **v2** | `v2/index.html` | v1 به‌علاوه تب **تمدید آنلاین** (ارسال عکس فیش واریزی) |

---

## نسخه ۱ (بدون تب)

### نصب با یک دستور

این دستور قالب را دانلود می‌کند و تنظیمات `.env` را خودکار انجام می‌دهد و پنل را ری‌استارت می‌کند:

</div>

```bash
sudo mkdir -p /var/lib/pasarguard/templates/subscription/ && \
sudo wget -N -O /var/lib/pasarguard/templates/subscription/index.html \
https://raw.githubusercontent.com/bytohix/Kashi/main/index.html && \
sudo sed -i '/^CUSTOM_TEMPLATES_DIRECTORY=/d;/^SUBSCRIPTION_PAGE_TEMPLATE=/d' /opt/pasarguard/.env && \
printf '\nCUSTOM_TEMPLATES_DIRECTORY="/var/lib/pasarguard/templates/"\nSUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"\n' | sudo tee -a /opt/pasarguard/.env >/dev/null && \
sudo pasarguard restart
```

<div dir="rtl">

### نصب مرحله‌به‌مرحله

**۱. دانلود قالب**

</div>

```bash
sudo mkdir -p /var/lib/pasarguard/templates/subscription/
sudo wget -N -O /var/lib/pasarguard/templates/subscription/index.html \
https://raw.githubusercontent.com/bytohix/Kashi/main/index.html
```

<div dir="rtl">

**۲. تنظیم PasarGuard**

</div>

```bash
sudo nano /opt/pasarguard/.env
```

<div dir="rtl">

این دو خط را اضافه یا به‌روزرسانی کنید:

</div>

```env
CUSTOM_TEMPLATES_DIRECTORY="/var/lib/pasarguard/templates/"
SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"
```

<div dir="rtl">

**۳. ری‌استارت پنل**

</div>

```bash
sudo pasarguard restart
```

<div dir="rtl">

---

## نسخه ۲ (با تب تمدید آنلاین)

این نسخه یک تب **تمدید آنلاین** دارد. کاربر عکس فیش واریزی را انتخاب و ارسال می‌کند و فیش همراه با نام کاربری او به ربات تلگرام شما می‌رسد. برای کارکرد این تب، علاوه بر قالب باید یک سرویس کوچک واسط (رله فیش) روی سرور نصب شود. این کار با فایل `v2/install.sh` انجام می‌شود.

### پیش‌نیازها

- دسترسی root روی سرور پنل
- نصب بودن `python3` و `curl`
- **توکن ربات تلگرام** (از [@BotFather](https://t.me/BotFather)) و **Chat ID** عددی که فیش‌ها به آن ارسال می‌شود. حتماً یک بار در ربات دکمه Start را بزنید.
- گواهی SSL فعال روی پنل (رله از همان گواهی برای HTTPS استفاده می‌کند)
- باز بودن پورت **19001** (TCP) در فایروال سرور و فایروال هاستینگ
- دسترسی سرور به `api.telegram.org`. اگر سرور پنل در ایران است و تلگرام بسته است، ارسال فیش کار نمی‌کند.

### مرحله ۱: نصب قالب با یک دستور

</div>

```bash
sudo mkdir -p /var/lib/pasarguard/templates/subscription/ && \
sudo wget -N -O /var/lib/pasarguard/templates/subscription/index.html \
https://raw.githubusercontent.com/bytohix/Kashi/main/v2/index.html && \
sudo sed -i '/^CUSTOM_TEMPLATES_DIRECTORY=/d;/^SUBSCRIPTION_PAGE_TEMPLATE=/d' /opt/pasarguard/.env && \
printf '\nCUSTOM_TEMPLATES_DIRECTORY="/var/lib/pasarguard/templates/"\nSUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"\n' | sudo tee -a /opt/pasarguard/.env >/dev/null && \
sudo pasarguard restart
```

<div dir="rtl">

### مرحله ۲: نصب رله فیش

</div>

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/bytohix/Kashi/main/v2/install.sh)
```

<div dir="rtl">

اسکریپت این موارد را از شما می‌پرسد:

1. توکن ربات تلگرام (قبل از ادامه، اعتبار آن را بررسی می‌کند)
2. Chat ID عددی

بقیه کارها خودکار انجام می‌شود: نصب سرویس `receipt` در systemd، تشخیص آدرس پنل و گواهی SSL از فایل `.env` پنل، باز کردن پورت 19001 در `ufw` (در صورت فعال بودن) و ارسال یک پیام آزمایشی به ربات.

### مدیریت رله

برای آپدیت یا حذف، دستور نصب را دوباره اجرا کنید. اگر رله از قبل نصب باشد، منویی نمایش داده می‌شود:

</div>

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/bytohix/Kashi/main/v2/install.sh)
```

<div dir="rtl">

| گزینه | کار |
|-------|-----|
| `1` | آپدیت (توکن و Chat ID حفظ می‌شود) |
| `2` | حذف کامل رله (سرویس، فایل‌ها و توکن) |
| `0` | خروج |

دستورهای مفید:

</div>

```bash
sudo systemctl status receipt        # وضعیت سرویس
sudo journalctl -u receipt -n 30     # آخرین لاگ‌ها
sudo nano /opt/receipt/receipt.conf  # تنظیمات (بعد از تغییر: systemctl restart receipt)
```

<div dir="rtl">

### نکات امنیتی رله

- توکن ربات فقط در `/opt/receipt/receipt.conf` با دسترسی `600` ذخیره می‌شود و داخل قالب قرار ندارد.
- نام کاربری فرستنده از خود پنل خوانده می‌شود، پس کاربر نمی‌تواند آن را جعل کند.
- حداکثر حجم هر فیش ۸ مگابایت است. هر کاربر در هر ۱۲ ساعت حداکثر ۳ فیش می‌تواند بفرستد و هر IP در هر ساعت حداکثر ۳۰ درخواست. این مقادیر در `receipt.conf` قابل تغییرند.
- فقط فایل‌های JPG، PNG و WebP پذیرفته می‌شوند و رله بدون دسترسی root اجرا می‌شود.

---

## عیب‌یابی

- **تغییرات قالب دیده نمی‌شود:** پنل را ری‌استارت کنید و کش مرورگر را پاک کنید.
- **ارسال فیش خطا می‌دهد (نسخه ۲):** باز بودن پورت 19001، وضعیت سرویس `receipt` و دسترسی سرور به `api.telegram.org` را بررسی کنید.
- **هشدار گواهی SSL هنگام نصب:** مسیر `SSL_CERT` و `SSL_KEY` را در `/opt/receipt/receipt.conf` اصلاح کنید و سرویس را ری‌استارت کنید.

## تغییر پورت

پورت 19001 در `v2/install.sh` و `v2/index.html` تعریف شده است. اگر آن را عوض می‌کنید، باید در هر دو فایل یکسان باشد.

</div>

<div dir="rtl">

---

## سازنده

ساخته‌شده توسط  ([@bytohix](https://github.com/bytohix))

اگه این قالب به دردت خورد، با یک ⭐ روی ریپو حمایت کن.

</div>

<p align="center">
  <a href="https://t.me/tohid35">
    <img src="https://img.shields.io/badge/Telegram-@tohid35-2AABEE?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram">
  </a>
</p>
