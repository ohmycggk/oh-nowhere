<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

Скрипт однократной установки, обновления и управления [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` упрощает развёртывание Nowhere Portal / Vector на лёгких Linux-серверах: установка бинарника, генерация Portal или Vector URL, системная служба, управление жизненным циклом, запуск read-only TUI и вывод URI для клиентов.

## Возможности

* Однократная установка Nowhere
* Обновление до последнего upstream-релиза
* Установка указанной версии release
* Интерактивный выбор версии из GitHub releases
* Интерактивное меню настройки
* Неинтерактивный CLI для автоматизации
* Поддержка systemd
* Поддержка OpenRC на Alpine Linux
* Debian, Ubuntu и Alpine
* Определение архитектур x86_64 и aarch64
* Выбор сборки GNU libc / musl
* Роли Portal или Vector
* Исходящий SOCKS5 Portal, native chaining Portal (`next=`), входящий SOCKS5 Vector
* Импорт share URI `nowhere://` (автоконвертация в `vector://`)
* Запуск read-only TUI Nowhere (`nowhere tui`)
* Просмотр статуса службы
* Share URI для клиентов Portal (`nowhere://`)
* Опциональная поддержка QR-кода
* Интерфейс скрипта на английском, китайском и русском

## Nowhere 1.5 / 1.6 / 1.7 / 1.8

Nowhere **1.5** вводит новый wire-протокол и удаляет параметр Portal `spec`. Nowhere **1.6** добавляет read-only TUI и структурированную локальную телеметрию (только Linux). Wire-протокол не менялся с 1.5.x. Nowhere **1.7** добавляет native chaining Portal-to-Portal (`next=`), upstream RTT в EVENT / telemetry / TUI и бюджет из семи переходов. Nowhere **1.8** заменяет тёплый TLS-пул `tcp/tcp` (`pool=<n>`) на TLS Mux (`mux=0|1`); параметр `pool` удалён.

Скрипт адаптирован под эти релизы:

* Portal URL больше не содержат `spec=`
* Поддерживается пользовательский `alpn` (значение по умолчанию `now/1` не пишется в URL)
* Share-ссылки остаются import URI `nowhere://` с носителями `up` / `down`
* `vector://` запускает native SOCKS5-клиент; скрипт генерирует и управляет им
* Вставка или импорт `nowhere://` автоматически конвертируется в `vector://` (добавляет `socks=` при отсутствии)
* При обновлении устаревший `spec=` удаляется из `/etc/nowhere/url.conf`
* При обновлении устаревший `pool=` удаляется; для `tcp/tcp` при отсутствии добавляется `mux=1`
* Сохранённые run URL `nowhere://` мигрируют в `vector://`
* Пункт меню 13 / `--tui` запускает read-only панель (1.7 показывает upstream RTT)
* Relay Portal может использовать native chaining через `next=` (несовместимо с исходящим `socks=`)
* Каждый Portal в native chain должен поддерживать семантику HOPS Nowhere 1.7.0
* Для wire 1.5+ Portal и клиенты нужно обновлять вместе
* Vector и upstream Portal `next` используют `mux=0|1` вместо `pool=` (1.8+)

## Поддерживаемые системы

| ОС           | Init       | Пакетный менеджер |
| ------------ | ---------- | ----------------- |
| Debian       | systemd    | apt               |
| Ubuntu       | systemd    | apt               |
| Alpine Linux | OpenRC     | apk               |

Архитектуры:

* `x86_64`
* `aarch64`

## Быстрый старт

Скачайте скрипт:

```bash
curl -fsSL https://raw.githubusercontent.com/ohmycggk/oh-nowhere/main/oh-nowhere.sh -o oh-nowhere.sh
chmod +x oh-nowhere.sh
```

Запустите интерактивный менеджер:

```bash
sudo ./oh-nowhere.sh --lang ru
```

Пункты меню:

```text
1. Однократная установка
2. Обновить Nowhere
3. Настроить службу
4. Запустить службу
5. Остановить службу
6. Перезапустить службу
7. Показать статус
8. Удалить Nowhere
9. Показать URI для шаринга
10. Установить поддержку QR
11. Сменить язык
12. Установить указанную версию
13. Запустить Nowhere TUI
14. Обновить скрипт oh-nowhere
0. Выход
```

## Однократная установка

Установка Portal с параметрами по умолчанию:

```bash
sudo ./oh-nowhere.sh --install --lang ru
```

Пользовательские параметры Portal:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang ru
```

Пример сгенерированного Portal URL:

```text
portal://change-me@:2077?tls=1&net=mix
```

Установка как Vector (локальный SOCKS5-клиент):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key change-me \
  --host relay.example \
  --port 2077 \
  --up tcp \
  --down tcp \
  --socks 127.0.0.1:1080 \
  --lang ru
```

Импорт share URI (автоконвертация `nowhere://` → `vector://`):

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://change-me@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example' \
  --socks 127.0.0.1:1080 \
  --lang ru
```

Установка chained Portal relay (Nowhere 1.7+):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key relay-key \
  --port 2077 \
  --next 'origin-key@origin.example:2077' \
  --up udp \
  --down udp \
  --lang ru
```

Пример сгенерированного Portal URL:

```text
portal://relay-key@:2077?tls=1&net=mix&next=origin-key@origin.example:2077&up=udp&down=udp
```

## Установка указанной версии

Установка конкретного upstream-релиза:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.8.2 \
  --key change-me \
  --port 2077 \
  --lang ru
```

Обновление или откат:

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.8.2 --lang ru
```

Также можно выбрать пункт меню `12. Установить указанную версию`: скрипт загрузит список GitHub releases. `0` — последняя версия, иначе номер из списка.

## Роли службы

Пункт меню 3 принимает `portal` / `vector` или вставленный `nowhere://` / `vector://` / `portal://` URL.

| Роль | Run URL | Исходящий трафик |
| ---- | ------- | ---------------- |
| `portal` | `portal://key@:port?...` | Опциональный **исходящий SOCKS** (`socks=host:port`) **или** native chain (`next=key@host:port` с `up`/`down`/`mux`/`sni`/`pin`); взаимоисключительно |
| `vector` | `vector://key@portal-host:port?...` | Обязательный **входящий** listener (по умолчанию `127.0.0.1:1080`) |

Одновременно активна только одна роль (один `url.conf` / служба `nowhere`). Для смены — перенастройка.

### Native chaining Portal (1.7+)

Relay Portal пересылает потоки напрямую на следующий Portal без loopback SOCKS5:

```text
portal://relay-key@:2077?next=origin-key@origin.example:2077&up=udp&down=udp
```

Интерактивная настройка спрашивает режим исходящего трафика: `none`, `socks` или `next`. При `next` также запрашиваются upstream-носители и опциональные `mux` / `sni` / `pin`.

Импортируйте chained Portal URL через `--url` или вставьте `portal://...?next=...` в меню настройки; перенастройка сохраняет `next=` и upstream-параметры.

## Режимы TLS (Portal)

### Самоподписанный TLS

По умолчанию `tls=1`.

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang ru
```

При самоподписанном TLS клиенты должны пропускать проверку сертификата; share URI не содержит `sni`.

### Пользовательский сертификат

`tls=2` с вашим сертификатом и ключом. Укажите `--host`, чтобы share URI включал соответствующий `sni`:

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key change-me \
  --port 2077 \
  --net mix \
  --tls 2 \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --host relay.example \
  --lang ru
```

## Сетевые режимы (Portal)

| Режим | Описание              | Носители share URI       |
| ----- | --------------------- | ------------------------ |
| `mix` | Смешанный TCP/UDP     | `up=udp&down=udp`        |
| `tcp` | Только TCP            | `up=tcp&down=tcp&mux=1` |
| `udp` | Только UDP            | `up=udp&down=udp`        |

По умолчанию: `mix`.

## Share URI для клиентов

Пункт меню 9 / `--share` выводит import URI `nowhere://` для роли Portal (не для Vector).

Примеры:

```text
nowhere://change-me@203.0.113.10:2077?up=udp&down=udp#Nowhere-US-203
nowhere://change-me@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example#Nowhere-DE-45
```

* Хост берётся из `/etc/nowhere/host.conf` (или `--host`), иначе — определённый публичный IP
* Имя узла добавляется как percent-encoded `#fragment`; задаётся через `--name` (по умолчанию `Nowhere-<страна>-<первый октет IP>`, файл `/etc/nowhere/name.conf`)
* Portal-only параметры (`tls`, `crt`, `key`, `net`, `dial`, `rate`, `etar`, `log`, исходящий `socks`, **`next`**) не копируются в share URI
* Chained Portal: клиенты подключаются к входу relay; `next=` остаётся только на сервере
* Пользовательский `alpn` копируется, если отличается от `now/1`
* На Vector `--share` показывает текущий run URL `vector://`

Вставьте share URI `nowhere://` в настройку / `--url`, чтобы запустить Vector локально.

## Nowhere TUI

Пункт меню 13 / `--tui` выполняет:

```bash
nowhere tui
```

Панель обнаруживает локальные экземпляры Portal/Vector и показывает метрики в реальном времени, включая upstream RTT (`ping_ms`) в Nowhere 1.7+. Только чтение; не управляет службой.

## CLI

```bash
sudo ./oh-nowhere.sh [опции]
```

### Опции

| Опция                       | Описание |
| --------------------------- | -------- |
| `-i`, `--install`           | Установка/обновление и запуск |
| `-u`, `--upgrade`           | Обновление Nowhere |
| `-c`, `--config`            | Настройка службы |
| `-s`, `--status`            | Статус |
| `-q`, `--share`             | Share URI |
| `--tui`                     | Запуск Nowhere TUI |
| `--upgrade-script`          | Обновить этот скрипт oh-nowhere с GitHub |
| `--uninstall`               | Удаление |
| `--type <portal\|vector>`   | Роль службы, по умолчанию `portal` |
| `--url <uri>`               | Импорт `portal://`, `vector://` или `nowhere://` |
| `-k`, `--key <ключ>`        | Общий ключ |
| `-p`, `--port <порт>`       | Порт, по умолчанию `2077` |
| `--alpn <alpn>`             | ALPN; по умолчанию `now/1` не пишется |
| `--host <hostname>`         | Portal: share/SNI; Vector: хост Portal |
| `--name <имя>`              | Имя узла для `#` fragment |
| `--net <mix\|tcp\|udp>`     | Сеть Portal, по умолчанию `mix` |
| `--tls <1\|2>`              | TLS Portal, по умолчанию `1` |
| `--cert <путь>`             | Сертификат при `tls=2` |
| `--keyfile <путь>`          | Ключ при `tls=2` |
| `--socks <addr>`            | Исходящий SOCKS Portal или входящий SOCKS Vector |
| `--next <key@host:port>`    | Native upstream Portal (несовместимо с `--socks`) |
| `--up <tcp\|udp>`           | Uplink (Vector или upstream Portal `next`; по умолчанию `udp`) |
| `--down <tcp\|udp>`         | Downlink (Vector или upstream Portal `next`; по умолчанию `udp`) |
| `--mux <0\|1>`              | TLS Mux для `tcp/tcp` (Vector или Portal `next`, по умолчанию `0`) |
| `--sni <имя>`               | Имя сертификата (Vector или Portal `next`) |
| `--pin <sha256>`            | Pin сертификата (Vector или Portal `next`) |
| `-v`, `--version <ver>`     | Установить указанный release |
| `-l`, `--lang <en\|zh\|ru>` | Язык скрипта, по умолчанию `zh` |
| `-h`, `--help`              | Справка |

`--spec` принимается, но игнорируется с предупреждением (удалён в Nowhere 1.5).
`--pool` принимается, но игнорируется с предупреждением (удалён в Nowhere 1.8; используйте `--mux`).

## Частые команды

Статус:

```bash
sudo ./oh-nowhere.sh --status --lang ru
```

Обновление:

```bash
sudo ./oh-nowhere.sh --upgrade --lang ru
```

Установка указанной версии:

```bash
sudo ./oh-nowhere.sh --install --version v1.8.2 --lang ru
```

Перенастройка:

```bash
sudo ./oh-nowhere.sh --config --lang ru
```

Share URI:

```bash
sudo ./oh-nowhere.sh --share --lang ru
```

TUI:

```bash
sudo ./oh-nowhere.sh --tui --lang ru
```

Обновление скрипта управления:

```bash
sudo ./oh-nowhere.sh --upgrade-script --lang ru
```

Удаление:

```bash
sudo ./oh-nowhere.sh --uninstall --lang ru
```

## Установленные файлы

Скрипт может создавать или управлять:

```text
/usr/local/bin/nowhere
/usr/local/bin/nowhere-launch.sh
/etc/nowhere/url.conf
/etc/nowhere/host.conf
/etc/nowhere/name.conf
/etc/systemd/system/nowhere.service
/etc/init.d/nowhere
```

Portal или Vector URL:

```text
/etc/nowhere/url.conf
```

Публичное имя для share / SNI (Portal) или запомненный хост Portal:

```text
/etc/nowhere/host.conf
```

Имя узла для `#fragment` share URI:

```text
/etc/nowhere/name.conf
```

Launcher читает `url.conf` и запускает Nowhere; если там `nowhere://`, автоматически мигрирует в `vector://`.

## Управление systemd

На Debian и Ubuntu устанавливается unit `nowhere.service`.

```bash
sudo systemctl status nowhere
sudo systemctl restart nowhere
sudo systemctl stop nowhere
sudo systemctl start nowhere
```

Логи:

```bash
sudo journalctl -u nowhere -f
```

## Управление OpenRC

На Alpine устанавливается служба OpenRC.

```bash
sudo rc-service nowhere status
sudo rc-service nowhere restart
sudo rc-service nowhere stop
sudo rc-service nowhere start
```

Автозапуск:

```bash
sudo rc-update add nowhere default
```

## Поддержка QR

Debian/Ubuntu: `qrencode`. Alpine: `python3` + `py3-qrcode`.

После установки:

```bash
sudo ./oh-nowhere.sh --share --lang ru
```

## Безопасность

* Используйте надёжный общий ключ.
* Не публикуйте Portal URL.
* Для публичных сервисов предпочитайте `tls=2` с валидным сертификатом и `--host` для SNI.
* При `tls=1` клиент должен пропускать проверку сертификата.
* Входящий SOCKS Vector за пределами localhost требует аутентификации и сетевой политики.
* Проверьте скрипт перед запуском на production.

## Upstream-проект

Этот репозиторий содержит только скрипт установки и управления. Nowhere поддерживается NodePassProject:

```text
https://github.com/NodePassProject/Nowhere
```

## Лицензия

Следует лицензии, указанной в репозитории. Проверьте LICENSE перед распространением или изменением.
