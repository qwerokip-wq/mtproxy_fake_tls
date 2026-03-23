# 🚀 mtproxy: Безопасный MTProxy с Fake TLS

Ультимативное решение для стабилизации работы Telegram через "партизанский" прокси. Скрипт маскирует трафик под обычные сайты, работает через Docker с автозапуском и управляется одной короткой командой.

---

## 💎 Особенности
* **Маскировка (Fake TLS):** Провайдер видит, что вы просто читаете новости или Википедию. Трафик не определяется как прокси.
* **Быстрый выбор:** Список из предустановленных популярных доменов или ввод своего.
* **Автоматизация:** Полная настройка Docker и зависимостей "под ключ" за один запуск.
* **Удобное управление:** Команда `mtproxy` доступна в консоли сразу после установки.
* **QR-коды:** Генерация рабочих QR-кодов прямо в терминале для мгновенного подключения с телефона.

---

## 📥 Быстрая установка (One-Liner)

Просто скопируйте эту команду и вставьте в терминал вашего сервера (работает на Ubuntu/Debian/CentOS):

```bash
wget -O mtproxy_fake_tls.sh https://raw.githubusercontent.com/qwerokip-wq/mtproxy_fake_tls/refs/heads/main/mtproxy_fake_tls.sh && chmod +x mtproxy_fake_tls.sh && sudo ./mtproxy_fake_tls.sh

```
## 📥 Устанавливает сразу 2 прокси с разными портами и секретами

```bash
wget -O mtproxy_fake_tls_2mtp.sh https://raw.githubusercontent.com/qwerokip-wq/mtproxy_fake_tls/refs/heads/main/mtproxy_fake_tls_2mtp.sh && chmod +x mtproxy_fake_tls_2mtp.sh && sudo ./mtproxy_fake_tls_2mtp.sh

```
## 📥 Устанавливает сразу 2 прокси с разными портами и секретами c возможностю их редактирования и переустановки каждого отдельно

```bash
wget -O mtproxy_fake_tls_2mtpV2.sh https://raw.githubusercontent.com/qwerokip-wq/mtproxy_fake_tls/refs/heads/main/mtproxy_fake_tls_2mtpV2.sh && chmod +x mtproxy_fake_tls_2mtpV2.sh && sudo ./mtproxy_fake_tls_2mtpV2.sh

```

```bash
wget -O mtproxy_fake_tls_2mtpV3.sh https://raw.githubusercontent.com/qwerokip-wq/mtproxy_fake_tls/refs/heads/main/mtproxy_fake_tls_2mtpV3.sh && chmod +x mtproxy_fake_tls_2mtpV3.sh && sudo ./mtproxy_fake_tls_2mtpV3.sh

```
