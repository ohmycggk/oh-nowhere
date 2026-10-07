<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

Скрипт однократной установки, обновления и управления [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` упрощает развёртывание Nowhere Portal / Vector на лёгких Linux- и FreeBSD-серверах: установка бинарника, генерация Portal или Vector URL, системная служба, управление жизненным циклом, запуск read-only TUI и вывод URI для клиентов. Цель по умолчанию — Nowhere **2.0+**; 1.x остаётся доступен для обслуживания старых узлов.

## Возможности

* Однократная установка Nowhere (по умолчанию последний 2.x)
* Обновление до последнего upstream-релиза
* Установка указанной версии release, включая 1.x
* Интерактивный выбор версии из GitHub releases
* Интерактивное меню настройки
* Пошаговое изменение текущей конфигурации (пункт 5) с автоматическим перезапуском службы
* Состояние службы Nowhere в шапке меню
* Проверка занятости порта при интерактивной настройке и изменении конфигурации
* Неинтерактивный CLI для автоматизации
* systemd, OpenRC и FreeBSD rc.d
* Debian, Ubuntu, Alpine и FreeBSD (только 2.0+)
* Определение архитектур x86_64 и aarch64
* Выбор GNU libc / musl на Linux; пакеты `unknown-freebsd` на FreeBSD
* Роли Portal или Vector
* Исходящий SOCKS5 Portal, native chaining Portal (`next=`), входящий SOCKS5 Vector
* Режим носителя (`tcp` / `udp` / `mix`): на 2.0 — путь endpoint, на 1.x — `net=`
* Независимые порты TCP/UDP и Morph (`--tcp-port` / `--udp-port` / `--morph`, Nowhere 2.0+)
* Смешанная политика носителей (`tcp` / `udp` / `mix`) для Vector и Portal `next`
* Готовность к Nowhere 2.2+: ключи Portal из 32–64 строчных hex-символов (`nowhere generate-key`), автоматическая миграция несоответствующих ключей при обновлении и поддержка pin сертификата (`pin=<sha256>`) в share URI
* Импорт share URI `nowhere://` (автоконвертация в `vector://`)
* Запуск read-only TUI Nowhere (`nowhere tui`)
* Просмотр статуса службы
* Share URI для клиентов Portal (`nowhere://`)
* Опциональная поддержка QR-кода
* Интерфейс скрипта на английском, китайском и русском

## Nowhere 2.0 (по умолчанию) и обслуживание 1.x

Nowhere **2.0** — ломающее изменение wire: ALPN фиксирован как `nw2` (`alpn=` игнорируется), Portal `net=` игнорируется (носители задаёт путь endpoint), узлы 1.x не подключаются. Скрипт по умолчанию ставит последний 2.x с GitHub. Сохраните узел 1.x через `--version v1.8.3` или пункт меню 3; цель обновления по умолчанию не возвращается к 1.8.

* Portal и клиенты должны быть одной мажорной версии (`now/1` и `nw2` несовместимы)
* Интерактивное обновление/откат 1↔2 требует подтверждения; `--upgrade` / `--install` только предупреждают и продолжают
* `--tcp-port`, `--udp-port` и `--morph` требуют Nowhere 2.0+ (при профиле 1.x скрипт завершается с ошибкой)
* На 2.0 `--alpn` игнорируется с предупреждением (как `--spec` / `--pool`)
* Новые конфиги 2.0 по умолчанию используют `up`/`down` = `tcp`; `mux` не пишется (каноническое `0`). 1.x сохраняет `udp` и по-прежнему добавляет `mux=1` для `tcp/tcp`
* `--port` остаётся общим значением по умолчанию (**2077**), пока порты не разделены
* Пакеты FreeBSD есть только для Nowhere 2.0+; установка 1.x на FreeBSD отклоняется. Если у 2.x tag нет `nowhere-<arch>-unknown-freebsd.tar.gz`, ошибка загрузки указывает tag и ожидаемое имя файла

`--net mix|tcp|udp` остаётся интерфейсом оператора. На 2.0 это отображается в endpoint, а не в `net=`:

| `--net` / порты | URL прослушивания Portal |
| --------------- | ------------------------ |
| `mix` (общий порт) | `portal://KEY@:2077?tls=1` (TCP+UDP на одном порту) |
| `tcp` | `portal://KEY@*/tcp:2077?tls=1` |
| `udp` | `portal://KEY@*/udp:2077?tls=1` |
| `--tcp-port 2006 --udp-port 2017` | `portal://KEY@*/tcp:2006/udp:2017?tls=1` |
| оба порта одинаковы | compact `KEY@:PORT` |

`--url` по-прежнему принимает полный endpoint, включая суффиксы семейства адресов (`tcp4` / `udp6`). Vector требует конкретный `--host` (`*` запрещён).

При обновлении до 2.x сохранённый Portal `net=tcp|udp` становится `@*/tcp:PORT` или `@*/udp:PORT`, `net=mix` (или отсутствие) остаётся compact, `alpn=` удаляется, `morph=` сохраняется. Откат на 1.x делает обратное, удаляет `morph=` и не пишет `alpn` (у 1.x по умолчанию `now/1`). Разные порты TCP/UDP нельзя выразить в 1.x: предупреждение и свёртка к одному порту (TCP, иначе UDP).

## Nowhere 2.2 (ключи Portal и проверка сертификатов)

Nowhere **2.2** — ломающее изменение для существующих 2.x узлов:

* **Ключ Portal должен содержать 32–64 строчных hex-символа** (в 2.2.0 требовалось ровно 64; в 2.2.1 требование смягчено до 32–64). То же правило для ключа `next=`. Portal с несоответствующим ключом **не запустится**.
* **Сертификаты Portal проверяются по умолчанию.** Пропустить проверку сертификата больше нельзя: клиенту нужен сертификат от CA, покрывающий адрес endpoint, или `pin=<sha256>` (SHA-256 отпечаток листового сертификата Portal). При `tls=1` (самоподписанный) параметр `pin=` фактически обязателен.

Скрипт адаптирован под 2.2.1:

* Новые ключи Portal генерируются как 32 строчных hex-символа (через `nowhere generate-key`, если бинарник доступен, иначе `/dev/urandom`)
* `--key` и интерактивный ввод ключа проверяются по формату 2.2 (32–64 строчных hex); неверный ввод отклоняется с ошибкой
* При обновлении до 2.2 несоответствующий сохранённый ключ Portal **перегенерируется автоматически** с предупреждением — после этого разошлите новый share URI всем клиентам. Неверный ключ `next=` только сообщается (ключ принадлежит upstream Portal и не перезаписывается)
* Share URI для самоподписанного Portal включает `pin=<sha256>`, когда отпечаток доступен из лога службы (journal systemd или `/var/log/nowhere.log` на OpenRC / FreeBSD) либо через `nowhere fingerprint`
* При настройке Vector на 2.2 с пустым `pin=` предлагается автоматическое получение отпечатка (`nowhere fingerprint`)
* Тулбокс 2.2 предоставляет `nowhere generate-key`, `nowhere fingerprint <nowhere-url>`, `nowhere probe`, `nowhere status`; скрипт использует первые две

**Важно:** самоподписанный сертификат пересоздаётся при каждом перезапуске Portal, поэтому `pin=` в share URI меняется — рассылайте share URI заново после перезапусков. Для стабильной настройки используйте `tls=2` с реальным сертификатом.

`dial` / `dial4` / `dial6` (dual-stack привязка исходящего адреса, только Portal, 2.2+) не являются отдельными опциями скрипта; редактор полей сохраняет их без изменений при правке других параметров.

## Nowhere 1.5 / 1.6 / 1.7 / 1.8

Nowhere **1.5** вводит новый wire-протокол и удаляет параметр Portal `spec`. Nowhere **1.6** добавляет read-only TUI и структурированную локальную телеметрию (только Linux). Wire-протокол не менялся с 1.5.x. Nowhere **1.7** добавляет native chaining Portal-to-Portal (`next=`), upstream RTT в EVENT / telemetry / TUI и бюджет из семи переходов. Nowhere **1.8** заменяет тёплый TLS-пул `tcp/tcp` (`pool=<n>`) на TLS Mux (`mux=0|1`); параметр `pool` удалён. Nowhere **1.8.3** добавляет смешанную политику носителей: Vector и Portal `next` принимают `up`/`down` = `tcp`, `udp` или `mix`.

Скрипт адаптирован под эти релизы:

* Portal URL больше не содержат `spec=`
* Поддерживается пользовательский `alpn` (значение по умолчанию `now/1` не пишется в URL)
* Share-ссылки остаются import URI `nowhere://` с носителями `up` / `down`
* `vector://` запускает native SOCKS5-клиент; скрипт генерирует и управляет им
* Вставка или импорт `nowhere://` автоматически конвертируется в `vector://` (добавляет `socks=` при отсутствии)
* При обновлении устаревший `spec=` удаляется из `/etc/nowhere/url.conf`
* При обновлении устаревший `pool=` удаляется; для `tcp/tcp` при отсутствии добавляется `mux=1`
* Сохранённые run URL `nowhere://` мигрируют в `vector://`
* Пункт меню 10 / `--tui` запускает read-only панель (1.7 показывает upstream RTT)
* Relay Portal может использовать native chaining через `next=` (несовместимо с исходящим `socks=`)
* Каждый Portal в native chain должен поддерживать семантику HOPS Nowhere 1.7.0
* Для wire 1.5+ Portal и клиенты нужно обновлять вместе
* Vector и upstream Portal `next` используют `mux=0|1` вместо `pool=` (1.8+)
* Vector и Portal `next` принимают `up`/`down` = `tcp|udp|mix` (1.8.3+); `mix/mix` для каждого потока разрешается в `tcp/tcp` или `udp/udp`
* Mux предлагается, если направление `tcp` или `mix`; для `udp/udp` `mux` не пишется (каноническое значение `0`)
* В share URI `up` и `down` обрабатываются отдельно: сторона `mix` пишется как `udp`, `tcp`/`udp` не меняются. У Portal `net=mix` обе стороны `mix`, поэтому URI — `up=udp&down=udp`

## Поддерживаемые системы

| ОС           | Init       | Пакетный менеджер | Примечание |
| ------------ | ---------- | ----------------- | ---------- |
| Debian       | systemd    | apt               | 1.x и 2.x |
| Ubuntu       | systemd    | apt               | 1.x и 2.x |
| Alpine Linux | OpenRC     | apk               | 1.x и 2.x |
| FreeBSD      | rc.d       | pkg               | только Nowhere 2.0+ (`x86_64` / `aarch64`) |

Архитектуры:

* `x86_64` (`amd64` на FreeBSD)
* `aarch64` (`arm64` на FreeBSD)

Свежие GNU Linux-сборки требуют **glibc 2.39** (Ubuntu 24.04 / Debian 13). Debian 12 и другие системы со старым glibc автоматически получают musl-сборку.

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
3. Установить указанную версию

4. Настроить службу
5. Изменить текущую конфигурацию

6. Запустить службу
7. Остановить службу
8. Перезапустить службу
9. Показать статус
10. Запустить Nowhere TUI

11. Показать URI для шаринга
12. Установить поддержку QR

13. Сменить язык
14. Обновить скрипт oh-nowhere
15. Удалить Nowhere
0. Выход
```

В шапке меню отображаются установленная версия Nowhere и состояние службы (работает / остановлена / не установлена).

## Изменение текущей конфигурации

Пункт меню **5** открывает редактор по полям для сохранённого URL запуска. Он показывает текущие значения всех параметров протокола (роль, ключ, порты, носитель `net`, режим TLS, `morph`/`alpn`, носители up/down, `mux`, исходящий SOCKS / `next=`, SNI, SPKI pin, адрес для шаринга, имя узла); введите номер поля, чтобы изменить только его, затем нажмите Enter или `q` для применения. Служба перезапускается автоматически, а параметры, которыми редактор не управляет (например `rate`/`etar`/`dial`/`log`), сохраняются без изменений.

Порты проверяются по таблице локальных слушателей (`ss`/`sockstat`/`netstat`): если порт занят, выводится предупреждение, и его нужно подтвердить перед использованием. Та же проверка выполняется при интерактивной установке и настройке.

## Однократная установка

Установка Portal с параметрами по умолчанию:

```bash
sudo ./oh-nowhere.sh --install --lang ru
```

Пользовательские параметры Portal:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang ru
```

На Nowhere 2.0 получается compact dual-carrier Portal URL:

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@:2077?tls=1
```

`--version v1.8.3` сохраняет форму 1.x: `portal://change-me@:2077?tls=1&net=mix` (1.x принимает любой непустой текст ключа).

Независимые порты TCP/UDP и Morph (только 2.0+):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --tcp-port 2006 \
  --udp-port 2017 \
  --morph 1 \
  --lang ru
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*/tcp:2006/udp:2017?tls=1&morph=1
```

Установка как Vector (локальный SOCKS5-клиент):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --up tcp \
  --down tcp \
  --socks 127.0.0.1:1080 \
  --lang ru
```

На 2.0 Vector URL следует тем же правилам endpoint (`relay.example:2077` для mix на одном порту или `relay.example/tcp:PORT`). Если `up`/`down` не заданы, по умолчанию `tcp`; `mux` не выставляется автоматически. На 1.x для `tcp/tcp` по-прежнему пишется `mux=1`.

Установка Vector со смешанными носителями (`mix/mix` выбирает `tcp/tcp` или `udp/udp` для каждого потока):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --up mix \
  --down mix \
  --socks 127.0.0.1:1080 \
  --lang ru
```

Импорт share URI (автоконвертация `nowhere://` → `vector://`):

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example' \
  --socks 127.0.0.1:1080 \
  --lang ru
```

Установка chained Portal relay (Nowhere 1.7+):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key b1c2d3e4f5a60718293a4b5c6d7e8f90 \
  --port 2077 \
  --next '00112233445566778899aabbccddeeff@origin.example:2077' \
  --up tcp \
  --down tcp \
  --lang ru
```

На 2.0 получается:

```text
portal://b1c2d3e4f5a60718293a4b5c6d7e8f90@:2077?tls=1&next=00112233445566778899aabbccddeeff@origin.example:2077&up=tcp&down=tcp
```

`next=` может использовать явный путь, например `00112233445566778899aabbccddeeff@origin.example/tcp:2077`. Chained Portal 1.x по-прежнему пишет `net=mix` и по умолчанию `up`/`down` = `udp`.

## Установка указанной версии

Установка конкретного upstream-релиза:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.0.0 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --lang ru
```

Сохранить или вернуть узел 1.x:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.8.3 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --lang ru
```

Обновление или откат:

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.8.3 --lang ru
```

Также можно выбрать пункт меню `3. Установить указанную версию`: скрипт загрузит список GitHub releases. `0` — последняя версия, иначе номер из списка.

## Роли службы

Пункт меню 4 принимает `portal` / `vector` или вставленный `nowhere://` / `vector://` / `portal://` URL.

| Роль | Run URL | Исходящий трафик |
| ---- | ------- | ---------------- |
| `portal` | `portal://key@:port?...` или `portal://key@*/tcp:port[/udp:port]?...` | Опциональный **исходящий SOCKS** (`socks=host:port`) **или** native chain (`next=key@host:port` с `up`/`down`/`mux`/`sni`/`pin`); взаимоисключительно |
| `vector` | `vector://key@portal-host:port?...` или путь `host/tcp:A/udp:B` | Обязательный **входящий** listener (по умолчанию `127.0.0.1:1080`) |

Одновременно активна только одна роль (один `url.conf` / служба `nowhere`). Для смены — перенастройка.

### Native chaining Portal (1.7+)

Relay Portal пересылает потоки напрямую на следующий Portal без loopback SOCKS5:

```text
portal://b1c2d3e4f5a60718293a4b5c6d7e8f90@:2077?next=00112233445566778899aabbccddeeff@origin.example:2077&up=tcp&down=tcp
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
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang ru
```

При самоподписанном TLS на Nowhere 2.2+ клиенты должны задать `pin=<sha256>` (проверка сертификата обязательна и отключить её нельзя); share URI не содержит `sni`. Вывод `--share` встраивает текущий отпечаток Portal как `pin=`, когда его можно прочитать из лога службы или получить через `nowhere fingerprint`; самоподписанный сертификат пересоздаётся при каждом перезапуске Portal — рассылайте share URI заново. На 1.x клиенты вместо этого пропускают проверку сертификата. Для стабильной настройки без pin используйте `tls=2` с реальным сертификатом.

### Пользовательский сертификат

`tls=2` с вашим сертификатом и ключом. Укажите `--host`, чтобы share URI включал соответствующий `sni`:

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --net mix \
  --tls 2 \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --host relay.example \
  --lang ru
```

## Режимы носителей (Portal)

`--net` задаёт носители Portal. По умолчанию по-прежнему `mix`.

| Режим | Endpoint Portal 2.0 | Query 1.x | Носители share URI |
| ----- | ------------------- | --------- | ------------------ |
| `mix` | compact `KEY@:PORT` (TCP+UDP на одном порту) | `net=mix` | `up=udp&down=udp` |
| `tcp` | `KEY@*/tcp:PORT` | `net=tcp` | `up=tcp&down=tcp` (на 1.x ещё `mux=1`) |
| `udp` | `KEY@*/udp:PORT` | `net=udp` | `up=udp&down=udp` |

`--tcp-port` / `--udp-port` (только 2.0+) перекрывают `--net` + `--port`:

* оба заданы и равны → compact `HOST:PORT`
* оба заданы и различны → `HOST/tcp:A/udp:B`
* только `--tcp-port` → `HOST/tcp:A`
* только `--udp-port` → `HOST/udp:B`
* не заданы → `--net` + `--port`

Конфликты сразу завершают работу: `--net tcp` вместе с `--udp-port`, `--net udp` вместе с `--tcp-port`, либо `up`/`down`/`mix` требуют носитель, не объявленный endpoint.

## Share URI для клиентов

Пункт меню 11 / `--share` выводит import URI `nowhere://` для роли Portal (не для Vector).

Примеры:

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/tcp:2006/udp:2017?up=udp&down=udp&morph=1#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f5#Nowhere-US-203
```

Последний пример — самоподписанный Portal 2.2: `pin=<sha256>` — отпечаток сертификата Portal (64 строчных hex-символа, меняется при каждом перезапуске Portal).

* Compact dual-carrier Portal → `host:port`. Сторона `mix` публикуется как `udp` (`net=mix` — `mix` с обеих сторон, поэтому `up=udp&down=udp`); явные или разные порты используют путь
* Endpoint только TCP / только UDP даёт `up=tcp&down=tcp` или `up=udp&down=udp`; 2.0 не добавляет `mux=1`
* `morph=1` Portal копируется в share URI
* Хост берётся из `/etc/nowhere/host.conf` (или `--host`), иначе — определённый публичный IP
* Имя узла добавляется как percent-encoded `#fragment`; задаётся через `--name` (по умолчанию `Nowhere-<страна>-<первый октет IP>`, файл `/etc/nowhere/name.conf`)
* Portal-only параметры (`tls`, `crt`, `key`, `net`, `dial`, `rate`, `etar`, `log`, исходящий `socks`, **`next`**) не копируются в share URI
* Chained Portal: клиенты подключаются к входу relay; `next=` остаётся только на сервере
* Пользовательский `alpn` копируется на 1.x, если отличается от `now/1`; share URI 2.0 не содержит `alpn`
* На Nowhere 2.2+ при `tls=1` в share URI встраивается `pin=<sha256>`, если отпечаток доступен (см. [Nowhere 2.2](#nowhere-22-ключи-portal-и-проверка-сертификатов)); он меняется при каждом перезапуске Portal
* На Vector `--share` показывает текущий run URL `vector://`

Вставьте share URI `nowhere://` в настройку / `--url`, чтобы запустить Vector локально.

## Nowhere TUI

Пункт меню 10 / `--tui` выполняет:

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
| `-k`, `--key <ключ>`        | Общий ключ (ключи Portal на Nowhere 2.2+: 32–64 строчных hex) |
| `-p`, `--port <порт>`       | Порт, по умолчанию `2077` |
| `--alpn <alpn>`             | ALPN 1.x (по умолчанию `now/1` не пишется); на 2.0 игнорируется (`nw2`) |
| `--host <hostname>`         | Portal: share/SNI; Vector: хост Portal |
| `--name <имя>`              | Имя узла для `#` fragment |
| `--net <mix\|tcp\|udp>`     | Режим носителя (1.x пишет `net=`; 2.0 отображает в путь endpoint; по умолчанию `mix`) |
| `--tcp-port <порт>`         | Порт TLS/TCP (Nowhere 2.0+; независимо от `--udp-port`) |
| `--udp-port <порт>`         | Порт QUIC/UDP (Nowhere 2.0+; независимо от `--tcp-port`) |
| `--morph <0\|1>`            | Маскировка TLS/QUIC (Nowhere 2.0+; по умолчанию `0`, не пишется) |
| `--tls <1\|2>`              | TLS Portal, по умолчанию `1` |
| `--cert <путь>`             | Сертификат при `tls=2` |
| `--keyfile <путь>`          | Ключ при `tls=2` |
| `--socks <addr>`            | Исходящий SOCKS Portal или входящий SOCKS Vector |
| `--next <key@host:port>`    | Native upstream Portal (несовместимо с `--socks`) |
| `--up <tcp\|udp\|mix>`      | Uplink (по умолчанию `tcp` на 2.x, `udp` на 1.x) |
| `--down <tcp\|udp\|mix>`    | Downlink (по умолчанию `tcp` на 2.x, `udp` на 1.x) |
| `--mux <0\|1>`              | TLS Mux, если направление `tcp` или `mix` (2.x не пишет/по умолчанию `0`; 1.x `tcp/tcp` → `1`) |
| `--sni <имя>`               | Имя сертификата (Vector или Portal `next`) |
| `--pin <sha256>`            | Pin сертификата (Nowhere 2.2+: обязателен для самоподписанного Portal `tls=1`; иначе Vector или Portal `next`) |
| `-v`, `--version <ver>`     | Установить указанный release (например `v2.0.0` или `v1.8.3`) |
| `-l`, `--lang <en\|zh\|ru>` | Язык скрипта, по умолчанию `zh` |
| `-h`, `--help`              | Справка |

`--spec` принимается, но игнорируется с предупреждением (удалён в Nowhere 1.5).
`--pool` принимается, но игнорируется с предупреждением (удалён в Nowhere 1.8; используйте `--mux`).
`--alpn` на Nowhere 2.0 игнорируется с предупреждением (фиксированный ALPN `nw2`).

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
sudo ./oh-nowhere.sh --install --version v1.8.3 --lang ru
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
/usr/local/etc/rc.d/nowhere
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

## Управление FreeBSD rc.d

На FreeBSD (Nowhere 2.0+) скрипт ставит `/usr/local/etc/rc.d/nowhere` и включает его через `sysrc nowhere_enable=YES`. Конфиг остаётся в `/etc/nowhere` (как на Linux). Launcher использует `#!/usr/bin/env bash`, потому что bash на FreeBSD обычно в `/usr/local/bin/bash`.

```bash
sudo service nowhere status
sudo service nowhere restart
sudo service nowhere stop
sudo service nowhere start
```

Включение или отключение автозапуска:

```bash
sudo sysrc nowhere_enable=YES
sudo sysrc -x nowhere_enable
```

## Поддержка QR

Debian/Ubuntu: `qrencode`. Alpine: `python3` + `py3-qrcode`. FreeBSD: `libqrencode` (`pkg install libqrencode`).

После установки:

```bash
sudo ./oh-nowhere.sh --share --lang ru
```

## Безопасность

* На Nowhere 2.2+ используйте сгенерированный ключ Portal: 32–64 строчных hex-символа (`nowhere generate-key`). Portal с несоответствующим ключом не запустится; скрипт перегенерирует такие ключи при обновлении и выведет предупреждение.
* Не публикуйте Portal URL.
* Для публичных сервисов предпочитайте `tls=2` с валидным сертификатом и `--host` для SNI.
* На Nowhere 2.2+ при `tls=1` рассылайте `pin=<sha256>` вместе с share URI (пропустить проверку сертификата нельзя); pin меняется при каждом перезапуске Portal. На 1.x клиент пропускает проверку сертификата.
* Входящий SOCKS Vector за пределами localhost требует аутентификации и сетевой политики.
* Проверьте скрипт перед запуском на production.

## Upstream-проект

Этот репозиторий содержит только скрипт установки и управления. Nowhere поддерживается NodePassProject:

```text
https://github.com/NodePassProject/Nowhere
```

## Лицензия

Следует лицензии, указанной в репозитории. Проверьте LICENSE перед распространением или изменением.
