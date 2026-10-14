<div>

[**English**](README.md) | [**简体中文**](README_zh_CN.md) | [**Русский**](README_ru.md)

</div>

# oh-nowhere

Скрипт однократной установки, обновления и управления [Nowhere](https://github.com/NodePassProject/Nowhere).

`oh-nowhere` ставит бинарник Nowhere на лёгкие серверы Linux и FreeBSD, собирает URL Portal, Vector или Egress, записывает системную службу, управляет её жизненным циклом и печатает клиентский share URI. Новая установка следует последнему стабильному релизу (Nowhere 3 / nw3). Уже установленный узел 2.x остаётся на 2.x и сам не переходит на nw3. Без версии узел 1.x обновляется до новейшего 2.x; чтобы остаться на 1.x, передайте `--version` или выберите пункт меню 3.

## Возможности

* Однократная установка последнего стабильного релиза (nw3); установленный 2.x остаётся на 2.x и сам не переходит на nw3
* Установка указанного релиза или интерактивный выбор из GitHub releases
* Интерактивное меню и неинтерактивный CLI
* Правка текущей конфигурации по полям с автоматическим перезапуском; проверка занятости порта при настройке
* systemd, OpenRC и FreeBSD rc.d
* Debian, Ubuntu, Alpine и FreeBSD (только Nowhere 2.0+)
* x86_64 / aarch64; на Linux автоматически выбирается GNU libc или musl
* Portal, Vector и роль Egress в nw3
* Share URI Portal (`nowhere://`) и необязательные QR-коды
* TUI только для чтения на 2.x; на nw3 — `nowhere status`
* Интерфейс скрипта на английском, китайском и русском

## Поддерживаемые системы

| ОС           | Init    | Пакеты | Примечание |
| ------------ | ------- | ------ | ---------- |
| Debian       | systemd | apt    | 1.x, 2.x и 3.x |
| Ubuntu       | systemd | apt    | 1.x, 2.x и 3.x |
| Alpine Linux | OpenRC  | apk    | 1.x, 2.x и 3.x |
| FreeBSD      | rc.d    | pkg    | Только Nowhere 2.0+ (`x86_64` / `aarch64`) |

Архитектуры:

* `x86_64` (на FreeBSD — `amd64`)
* `aarch64` (на FreeBSD — `arm64`)

Свежие сборки GNU Linux требуют **glibc 2.39** (Ubuntu 24.04 / Debian 13). Debian 12 и другие системы со старым glibc автоматически ставят сборку musl.

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
10. TUI / статус инстанса

11. Показать URI для шаринга
12. Установить поддержку QR

13. Сменить язык
14. Обновить скрипт oh-nowhere
15. Удалить Nowhere
0. Выход
```

В шапке меню видны версия скрипта oh-nowhere, установленная версия Nowhere и состояние службы (работает / остановлена / не установлена).

## Установка по умолчанию (Nowhere 3)

Новая установка без `--version` использует nw3. Если Nowhere уже установлен, `--install` переходит к обновлению и следует правилам целевой версии из раздела «Обновление и смена линии протокола» ниже. Ключи Portal, Vector и Egress — ровно 32 строчных шестнадцатеричных символа (`nowhere generate-key`, если бинарник уже есть, иначе `/dev/urandom`). `morph` по умолчанию `1` и всегда записывается. `tls` принимает только `1` или `2`. Подстановочный хост Portal пишется как `*`.

Бинарник nw3 молча игнорирует неизвестные параметры. Скрипт проверяет их до записи. Если бинарник уже nw3, а в `url.conf` Portal или Vector ещё есть `up`, `down`, `mux`, `next`, `socks`, `net`, `alpn`, `log`, `pool` или `spec`, launcher отказывается стартовать.

### Portal

```bash
sudo ./oh-nowhere.sh --install --lang ru
```

По умолчанию это `mix` на общем порту. URL имеет такой вид (ключ генерирует скрипт; hex ниже — только пример из 32 символов):

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=direct&morph=1
```

`*:2077` слушает TCP и UDP на одном порту. Выход задаётся через `--out`:

| `--out` | Выход в URL запуска |
| ------- | ------------------- |
| `direct` (по умолчанию) | `out=direct` |
| `socks` | `out=127.0.0.1:1080` (адрес из `--socks`; допустим `user:pass@`) |
| `egress` | `out=egress` (на endpoint должен быть UDP) |

На Portal `--socks` — совместимый псевдоним `--out socks`. `--next` на nw3 отклоняется.

Носители:

| Форма | Endpoint Portal |
| ----- | --------------- |
| `--net mix` (по умолчанию, порты не разделены) | `*:2077` |
| `--net tcp` | `*/tcp:2077` |
| `--net udp` | `*/udp:2077` |
| `--tcp-port 2006 --udp-port 2017` | `*/tcp:2006/udp:2017` |

Одинаковые порты TCP и UDP схлопываются в `*:PORT`. `--net tcp` вместе с `--udp-port` или `--net udp` вместе с `--tcp-port` сразу завершаются ошибкой.

SOCKS5 upstream:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --socks 127.0.0.1:1080 \
  --lang ru
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=127.0.0.1:1080&morph=1
```

Отдать трафик зарегистрированному Egress (у Portal и Egress один ключ):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --out egress \
  --lang ru
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=1&out=egress&morph=1
```

### Vector

Vector — локальный SOCKS5-клиент. Endpoint объявляет ровно один носитель. `--host` должен быть конкретным хостом; `*` отклоняется.

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type vector \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --net tcp \
  --socks 127.0.0.1:1080 \
  --lang ru
```

```text
vector://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/tcp:2077?in=127.0.0.1:1080&morph=1
```

`--net udp` даёт `/udp:PORT`. `--up` / `--down` / `--mux` — совместимые прокладки: одинаковые носители сохраняются (`mix` сворачивается в `tcp`); несовпадение становится `tcp` и печатает предупреждение.

Импорт share URI превращает его в Vector. На nw3 скрипт добавляет `in=` (по умолчанию `127.0.0.1:1080`):

```bash
sudo ./oh-nowhere.sh \
  --config \
  --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?net=tcp&morph=1' \
  --socks 127.0.0.1:1080 \
  --lang ru
```

### Egress

Egress сам устанавливает исходящий QUIC к Portal с `out=egress`. Входящий порт файрвола не нужен.

```bash
sudo ./oh-nowhere.sh \
  --install \
  --type egress \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --lang ru
```

```text
egress://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/udp:2077?morph=1
```

## Роли службы

Пункт меню 4 принимает `portal`, `vector` или `egress`, либо вставленный URL `nowhere://`, `vector://`, `portal://` или `egress://`. Одновременно активна одна роль (один `url.conf`, одна служба `nowhere`).

| Роль | URL запуска | Примечание |
| ---- | ----------- | ---------- |
| `portal` | `portal://KEY@*:2077?tls=1&out=direct&morph=1` | Выход: `out=direct`, `out=[user:pass@]host:port` или `out=egress` |
| `vector` | `vector://KEY@HOST/tcp:2077?in=127.0.0.1:1080&morph=1` | Входящий слушатель `in=`; у endpoint один носитель |
| `egress` | `egress://KEY@HOST/udp:2077?morph=1` | Соединяется с Portal `out=egress`; входящего порта нет |

`socks=`, `next=` и двухносительные пути 2.x описаны в конце, в разделе «Старые линии протокола».

## Режимы TLS (Portal)

По умолчанию `tls=1` (самоподписанный сертификат). nw3 не принимает `tls=0`.

Nowhere 2.2+ и nw3 проверяют сертификаты по умолчанию; клиент не может пропустить проверку. Если отпечаток удалось прочитать, share URI самоподписанного Portal содержит `pin=<sha256>` (64 строчных hex-символа). Отпечаток берётся из лога службы (journal systemd или `/var/log/nowhere.log` на OpenRC / FreeBSD) либо через `nowhere fingerprint`. Самоподписанный сертификат создаётся заново при каждом перезапуске Portal, поэтому после перезапуска клиентам нужен новый share URI. На 1.x клиенты вместо этого пропускают проверку сертификата.

Для стабильного отпечатка на долгой публичной службе используйте `tls=2` с настоящим сертификатом и `--host`, чтобы в share URI попал подходящий `sni`:

```bash
sudo ./oh-nowhere.sh \
  --config \
  --type portal \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --tls 2 \
  --cert /etc/nowhere/cert.pem \
  --keyfile /etc/nowhere/key.pem \
  --host relay.example \
  --lang ru
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*:2077?tls=2&crt=/etc/nowhere/cert.pem&key=/etc/nowhere/key.pem&out=direct&morph=1
```

## Клиентский share URI

Пункт меню 11 / `--share` печатает по одной ссылке `nowhere://` на каждый носитель Portal. QR-код кодирует TCP-ссылку, если она есть. Самоподписанный Portal (`tls=1`) включает `pin=`, когда отпечаток доступен:

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=tcp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?net=udp&morph=1&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
```

При `tls=2` и заданном хосте шаринга ссылка несёт `sni` и не зависит от `pin`. Смысл `pin=` и смена отпечатка после перезапуска описаны в «Режимы TLS».

* Хост берётся из `/etc/nowhere/host.conf` (или `--host`), иначе — обнаруженный публичный IP
* Имя узла — percent-encoded `#fragment`; задаётся через `--name` (по умолчанию `Nowhere-<страна>-<первый октет IP>`, хранится в `/etc/nowhere/name.conf`)
* `tls`, `crt`, `key`, `out`, `dial`, `rate`, `etar` и `log` в share URI не попадают
* Vector и Egress печатают только URL запуска; клиентской ссылки импорта нет
* Вставка `nowhere://` в настройку или `--url` запускает локальный Vector

Share-ссылки 2.x используют `up` / `down`. См. «Старые линии протокола» ниже.

## Изменение текущей конфигурации

Пункт меню **5** правит сохранённый URL запуска по полям. Введите номер поля, чтобы изменить только его, затем нажмите Enter или `q`, чтобы сохранить и перезапустить службу.

На nw3 поля включают: ключ, порты, носитель (у Vector один `tcp` или `udp`), TLS, `morph`, выход Portal `out=` (`direct` / `socks` / `egress`), SOCKS upstream, `in=` у Vector, а у Egress — хост / UDP-порт / SNI / pin, плюс хост шаринга и имя узла. Параметры, которыми редактор не управляет (`rate` / `etar` / `dial` / `log`), сохраняются как есть.

Порты сверяются с локальной таблицей слушателей (`ss` / `sockstat` / `netstat`). Занятый порт вызывает предупреждение и требует подтверждения. Та же проверка есть в интерактивной установке и настройке.

## Обновление и смена линии протокола

`--upgrade` без `--version`:

* Установленный 2.x остаётся на 2.x: новейший `v2.*` среди последних 30 релизов, а если его нет — `v2.2.1`
* Установленный 1.x без указанной версии тоже нацелен на этот новейший `v2.*` и не остаётся на 1.x
* Установленный nw3 и новая установка следуют последнему стабильному релизу

Пункт меню 3 показывает список GitHub releases. `0` для новой установки означает последний стабильный релиз; уже установленный 2.x по-прежнему идёт на новейший 2.x, а уже установленный 1.x тоже нацелен на этот новейший 2.x. Номер из списка ставит этот релиз. Переход на другой мажор всё равно требует подтверждения.

Обновление с 1.x на 2.x сначала печатает предупреждение. В интерактивном режиме продолжение идёт после подтверждения; `--upgrade` / `--install` печатают предупреждение и продолжают.

Переход между nw2 и nw3 — отдельный порог. Явный `--version` его не обходит. До скачивания скрипт проверяет `url.conf`:

* Переход на nw3 останавливается, если у Portal есть `next=` (в nw3 этого нет; перенастройте узел как Vector или используйте `out=socks` / `out=egress`)
* Возврат на nw2 останавливается, если роль — Egress или Portal использует `out=egress`

После проверки:

* В интерактивном меню введите `MIGRATE`
* `--upgrade` / `--install` дополнительно требуют `--allow-protocol-breaking-upgrade` (без `--version` этот флаг сразу переходит на последний 3.x)

После подтверждения скрипт копирует `url.conf` в `url.conf.nw<старый мажор>.bak.<время>`, бинарник — в `nowhere.bak.<время>`, затем мигрирует URL:

* nw2 → nw3: `socks=` становится `out=` (если `socks` нет — `out=direct`); пустой хост `@:PORT` становится `*:PORT`; `socks=` у Vector становится `in=`, несколько носителей сходятся в один (`mix` или несовпадающие up/down становятся `tcp` с предупреждением). `morph` пишется явно (`0`, если nw2 его опускал). Ключ Portal, который не является 32 строчными hex, перегенерируется, и скрипт просит заново разослать share URI. Ключ Vector принадлежит чужому Portal и только сообщается. `rate` / `etar` / `dial*` сохраняются. `up` / `down` / `mux` / `sni` / `pin` / `alpn` / `net` / `log` удаляются из URL Portal
* nw3 → nw2: `out=direct` убирает выход, `out=<endpoint>` становится `socks=`, `in=` становится `socks=`, один носитель разворачивается в `up`=`down`. `morph=1` сохраняется; `morph=0` опускается

## CLI

```bash
sudo ./oh-nowhere.sh [опции]
```

### Опции

| Опция | Описание |
| ----- | -------- |
| `-i`, `--install` | Однократная установка, обновление и запуск |
| `-u`, `--upgrade` | Обновить Nowhere |
| `--allow-protocol-breaking-upgrade` | Подтвердить переход линии nw2↔nw3 (мигрирует сохранённые URL) |
| `-c`, `--config` | Настроить службу |
| `-s`, `--status` | Показать статус |
| `-q`, `--share` | Показать клиентский share URI |
| `--tui` | Запустить TUI Nowhere (2.x) или `nowhere status` (nw3) |
| `--upgrade-script` | Обновить этот скрипт oh-nowhere с GitHub |
| `--uninstall` | Удалить Nowhere |
| `--type <portal\|vector\|egress>` | Роль службы, по умолчанию `portal` (`egress` требует nw3) |
| `--url <uri>` | Импорт `portal://`, `vector://`, `egress://` или `nowhere://` |
| `-k`, `--key <ключ>` | Общий ключ (nw3: ровно 32 строчных hex; Portal 2.2+: 32–64 строчных hex) |
| `-p`, `--port <порт>` | Порт прослушивания, по умолчанию `2077` |
| `--alpn <alpn>` | ALPN TLS/QUIC для 1.x (значение по умолчанию `now/1` не пишется); на 2.0 и nw3 предупреждение и игнор |
| `--host <hostname>` | Portal: хост шаринга/SNI; Vector / Egress: хост Portal |
| `--name <имя>` | Имя узла для фрагмента `#` в share URI |
| `--net <mix\|tcp\|udp>` | Носитель (1.x пишет `net=`; 2.0 отображает в путь endpoint; Vector nw3 использует только `tcp` / `udp`; по умолчанию `mix`) |
| `--tcp-port <порт>` | Порт TLS/TCP (Nowhere 2.0+; может отличаться от UDP) |
| `--udp-port <порт>` | Порт QUIC/UDP (Nowhere 2.0+; им же пользуется Egress nw3) |
| `--morph <0\|1>` | Маскировка TLS/QUIC (Nowhere 2.0+; на 2.x по умолчанию `0` и не пишется, на nw3 по умолчанию `1` и пишется) |
| `--tls <1\|2>` | Режим TLS Portal, по умолчанию `1` (nw3 не принимает `0`) |
| `--cert <путь>` | Путь к сертификату при `tls=2` |
| `--keyfile <путь>` | Путь к приватному ключу при `tls=2` |
| `--socks <адрес>` | Входящий SOCKS Vector; на Portal nw3 — псевдоним `--out socks` |
| `--out <direct\|socks\|egress>` | Выход Portal (nw3; по умолчанию `direct`) |
| `--next <key@host:port>` | Нативный upstream Portal, только 2.x (взаимоисключающе с `--socks`; на nw3 отклоняется) |
| `--up <tcp\|udp\|mix>` | Восходящий носитель (по умолчанию `tcp` на 2.x, `udp` на 1.x; на nw3 — совместимая прокладка) |
| `--down <tcp\|udp\|mix>` | Нисходящий носитель (по умолчанию `tcp` на 2.x, `udp` на 1.x; на nw3 — совместимая прокладка) |
| `--mux <0\|1>` | TLS Mux, когда направление — `tcp` или `mix` (2.x опускает, это `0`; у 1.x `tcp/tcp` по умолчанию `1`) |
| `--sni <имя>` | Имя сертификата (Vector, Egress или upstream `next` Portal 2.x) |
| `--pin <sha256>` | Отпечаток сертификата (нужен клиентам самоподписанного Portal; можно задать и на Vector / Egress) |
| `-v`, `--version <версия>` | Установить указанный релиз Nowhere (например `v3.0.0`, `v2.2.1` или `v1.8.3`) |
| `--script-version` | Напечатать версию этого oh-nowhere и выйти |
| `-l`, `--lang <en\|zh\|ru>` | Язык скрипта, по умолчанию `zh` |
| `-h`, `--help` | Показать справку |

`--spec` всё ещё принимается, затем предупреждение и игнор (удалён в Nowhere 1.5).
`--pool` всё ещё принимается, затем предупреждение и игнор (удалён в Nowhere 1.8; используйте `--mux`).
`--alpn` на 2.0 и nw3 предупреждает и игнорируется.
`--next` на nw3 отклоняется.

## Частые команды

Статус:

```bash
sudo ./oh-nowhere.sh --status --lang ru
```

Обновление внутри текущей линии протокола:

```bash
sudo ./oh-nowhere.sh --upgrade --lang ru
```

Переход на nw3 после подтверждения:

```bash
sudo ./oh-nowhere.sh --upgrade --allow-protocol-breaking-upgrade --lang ru
```

Перенастройка:

```bash
sudo ./oh-nowhere.sh --config --lang ru
```

Показать share URI:

```bash
sudo ./oh-nowhere.sh --share --lang ru
```

Запустить TUI (2.x) или снимок статуса (nw3):

```bash
sudo ./oh-nowhere.sh --tui --lang ru
```

Обновить скрипт управления:

```bash
sudo ./oh-nowhere.sh --upgrade-script --lang ru
```

Удаление:

```bash
sudo ./oh-nowhere.sh --uninstall --lang ru
```

## Установленные файлы

Скрипт может создать или вести:

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

URL запуска — `/etc/nowhere/url.conf`. Хост шаринга — `/etc/nowhere/host.conf`. Имя узла — `/etc/nowhere/name.conf`.

Launcher читает `url.conf` и запускает Nowhere. Сохранённый `nowhere://` становится `vector://`: nw3 добавляет `in=127.0.0.1:1080`; более ранние релизы добавляют `socks=`. Если бинарник nw3 всё ещё видит параметры 2.x в URL Portal или Vector, launcher завершается с ошибкой, чтобы эти параметры не были молча проигнорированы.

## Управление systemd

Debian / Ubuntu ставят unit `nowhere.service`.

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

Alpine ставит службу OpenRC.

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

FreeBSD (Nowhere 2.0+) ставит `/usr/local/etc/rc.d/nowhere` и включает его через `sysrc nowhere_enable=YES`. Конфигурация остаётся в `/etc/nowhere`. Shebang launcher — `#!/usr/bin/env bash` (bash на FreeBSD обычно в `/usr/local/bin/bash`).

```bash
sudo service nowhere status
sudo service nowhere restart
sudo service nowhere stop
sudo service nowhere start
```

Включить или выключить автозапуск:

```bash
sudo sysrc nowhere_enable=YES
sudo sysrc -x nowhere_enable
```

## Поддержка QR

Debian / Ubuntu используют `qrencode`; Alpine — `python3` + `py3-qrcode`; FreeBSD — `libqrencode` (`pkg install libqrencode`). Пункт меню 12 ставит подходящий пакет. После этого `--share` кодирует TCP-ссылку Portal в QR (UDP, если TCP-ссылки нет).

## Безопасность

* Используйте ключ, который сгенерировал скрипт. На nw3 каждая роль — ровно 32 строчных hex; Portal 2.2 — 32–64. Portal с неподходящим ключом отказывается запускаться.
* Не публикуйте URL запуска Portal.
* Для долгой публичной службы используйте `tls=2`, действительный сертификат и `--host`. В самоподписанном режиме нужно раздавать `pin=`, и отпечаток меняется при каждом перезапуске Portal. См. «Режимы TLS».
* Если входящий SOCKS Vector доступен за пределами хоста, добавьте аутентификацию и сетевые ограничения.
* Перед продакшеном просмотрите скрипт.

## Upstream-проект

Этот репозиторий содержит скрипт установки и управления. Nowhere ведёт NodePassProject:

```text
https://github.com/NodePassProject/Nowhere
```

## Лицензия

Следуйте лицензии, заявленной в этом репозитории. Перед распространением или изменением прочитайте файл LICENSE.

## Старые линии протокола (2.x / 1.x)

Установить, сохранить или вернуться на старую линию можно через `--version v2.2.1`, `--version v1.8.3` или пункт меню 3. Формы URL ниже создаются только на соответствующем мажоре. Переход на nw3 и обратно описан в «Обновление и смена линии протокола».

### Nowhere 2.0

Nowhere 2.0 меняет wire-протокол: ALPN фиксирован как `nw2` (`--alpn` предупреждает и игнорируется), `net=` у Portal игнорируется, носители задаёт путь endpoint, узлы 1.x не подключаются. `--tcp-port`, `--udp-port` и `--morph` требуют 2.0+ (на 1.x скрипт завершается с ошибкой). Пакеты FreeBSD есть только для 2.0+. Если у тега 2.x нет `nowhere-<arch>-unknown-freebsd.tar.gz`, ошибка загрузки называет тег и ожидаемое имя файла.

На 2.0 `--net` отображается в endpoint и не пишется как `net=`:

| `--net` / порты | URL прослушивания Portal |
| --------------- | ------------------------ |
| `mix` (по умолчанию, общий порт) | `portal://KEY@:2077?tls=1` |
| `tcp` | `portal://KEY@*/tcp:2077?tls=1` |
| `udp` | `portal://KEY@*/udp:2077?tls=1` |
| `--tcp-port 2006 --udp-port 2017` | `portal://KEY@*/tcp:2006/udp:2017?tls=1` |
| порты равны | компактный `KEY@:PORT` |

Новые конфигурации 2.0 по умолчанию ставят `up` / `down` в `tcp` и опускают mux (каноническое `0`). 1.x по умолчанию использует `udp` и по-прежнему добавляет `mux=1` для `tcp/tcp`. Если порты не разделены, `--port` по умолчанию **2077**.

`--url` может импортировать полный endpoint, включая суффиксы семейства адресов вроде `tcp4` / `udp6`. Vector требует конкретный `--host`.

При обновлении до 2.x сохранённый Portal `net=tcp|udp` становится `@*/tcp:PORT` или `@*/udp:PORT`, `net=mix` (или отсутствие значения) остаётся компактным, `alpn=` удаляется, `morph=` сохраняется. Откат на 1.x делает обратное отображение, убирает `morph=` и не пишет `alpn` (у 1.x по умолчанию `now/1`). Разные порты TCP/UDP на 1.x не представимы: скрипт предупреждает и схлопывает их в один порт (TCP, если задан, иначе UDP).

Portal на общем порту:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --net mix \
  --tls 1 \
  --lang ru
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@:2077?tls=1
```

Раздельные порты и Morph:

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --tcp-port 2006 \
  --udp-port 2017 \
  --morph 1 \
  --lang ru
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@*/tcp:2006/udp:2017?tls=1&morph=1
```

Vector (если `up` / `down` опущены, по умолчанию `tcp`; `mux` сам не добавляется):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --type vector \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --host relay.example \
  --port 2077 \
  --up tcp \
  --down tcp \
  --socks 127.0.0.1:1080 \
  --lang ru
```

Vector с mix на одном порту использует `relay.example:2077`; один носитель — `relay.example/tcp:PORT`. `mix/mix` выбирает `tcp/tcp` или `udp/udp` на поток.

Импорт share URI 2.x превращает `nowhere://` в `vector://` и добавляет `socks=`, если его нет:

```bash
sudo ./oh-nowhere.sh \
  --config \
  --version v2.2.1 \
  --url 'nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example' \
  --socks 127.0.0.1:1080 \
  --lang ru
```

### Nowhere 2.2

2.2 — ломающее изменение времени выполнения для существующих узлов 2.x:

* Ключи Portal и ключ upstream `next=` должны состоять из 32–64 строчных шестнадцатеричных символов (2.2.0 требовал ровно 64; 2.2.1 ослабил это до 32–64). Portal с неподходящим ключом отказывается запускаться
* Проверка сертификата обязательна. При `tls=1` клиентам нужен `pin=<sha256>`. См. «Режимы TLS»

Что делает скрипт:

* Новые ключи Portal — 32 строчных шестнадцатеричных символа
* `--key` и интерактивный ввод проверяются как 32–64 hex
* При обновлении до 2.2 неподходящий ключ Portal перегенерируется и печатается предупреждение; затем заново разошлите share URI. Неподходящий ключ `next=` только сообщается и не переписывается
* При настройке Vector с пустым `pin=` можно получить отпечаток Portal через `nowhere fingerprint`
* В наборе 2.2 есть `nowhere generate-key`, `nowhere fingerprint`, `nowhere probe` и `nowhere status`; скрипт использует первые две команды

`dial` / `dial4` / `dial6` (привязка исходящего источника dual-stack, только Portal, 2.2+) не являются опциями первого уровня. Редактор по полям сохраняет их при изменении других полей.

### Нативная цепочка Portal (1.7+, 2.x)

Portal-ретранслятор пересылает потоки на следующий хоп без loopback SOCKS5. `next=` и исходящий `socks=` взаимоисключающие. Каждый Portal в цепочке должен поддерживать семантику HOPS 1.7.0 (семь хопов).

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v2.2.1 \
  --type portal \
  --key b1c2d3e4f5a60718293a4b5c6d7e8f90 \
  --port 2077 \
  --next '00112233445566778899aabbccddeeff@origin.example:2077' \
  --up tcp \
  --down tcp \
  --lang ru
```

```text
portal://b1c2d3e4f5a60718293a4b5c6d7e8f90@:2077?tls=1&next=00112233445566778899aabbccddeeff@origin.example:2077&up=tcp&down=tcp
```

`next=` может быть и путём, например `00112233445566778899aabbccddeeff@origin.example/tcp:2077`. Цепочный Portal 1.x по-прежнему пишет `net=mix`, а `up` / `down` по умолчанию равны `udp`.

Интерактивная настройка предлагает `none`, `socks` или `next`. Выбор `next` продолжается носителями upstream и необязательными `mux` / `sni` / `pin`. Повторная настройка сохраняет `next=` и параметры upstream. Клиенты подключаются к входу этого ретранслятора; `next=` в share URI отсутствует. Узел, у которого ещё есть `next=`, нельзя мигрировать на nw3.

### Nowhere 1.5 / 1.6 / 1.7 / 1.8

* **1.5** меняет wire-протокол и удаляет `spec` у Portal. Обновление снимает `spec=` из `url.conf`. Свой `alpn` можно записать; значение по умолчанию `now/1` опускается
* **1.6** добавляет TUI только для чтения и структурированную локальную телеметрию (только Linux). Wire-протокол совпадает с 1.5
* **1.7** добавляет `next=`, upstream RTT в логах EVENT / телеметрии / TUI и бюджет в семь хопов. Сохранённые URL запуска `nowhere://` мигрируют в `vector://`
* **1.8** заменяет `pool=<n>` на TLS Mux (`mux=0|1`). Обновление снимает `pool=` и пишет `mux=1` для `tcp/tcp`, если `mux=` нет. Mux предлагается, когда направление — `tcp` или `mix`; `udp/udp` опускает `mux`
* **1.8.3**: Vector и `next` Portal принимают `up` / `down` равными `tcp`, `udp` или `mix`. `mix/mix` на поток разрешается в `tcp/tcp` или `udp/udp`

Portal и клиенты должны быть одного мажора. Wire-протокол 1.5+ требует обновлять обе стороны вместе.

Сохранить или вернуть 1.x (годится любой непустой ключ):

```bash
sudo ./oh-nowhere.sh \
  --install \
  --version v1.8.3 \
  --key a1b2c3d4e5f60718293a4b5c6d7e8f90 \
  --port 2077 \
  --lang ru
```

```text
portal://a1b2c3d4e5f60718293a4b5c6d7e8f90@:2077?tls=1&net=mix
```

Откат:

```bash
sudo ./oh-nowhere.sh --upgrade --version v1.8.3 --lang ru
```

Пункт меню 10 / `--tui` на 2.x и на 1.6+ запускает `nowhere tui` (только чтение; upstream RTT с 1.7). nw3 запускает `nowhere status`.

### Share URI 2.x / 1.x

```text
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp#Nowhere-US-203
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example/tcp:2006/udp:2017?up=udp&down=udp&morph=1#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@relay.example:2077?up=tcp&down=tcp&mux=1&sni=relay.example#Nowhere-DE-45
nowhere://a1b2c3d4e5f60718293a4b5c6d7e8f90@203.0.113.10:2077?up=udp&down=udp&pin=8f14e45fceea167a5a36dedd4bea2543b7e6d5c4a3f2918273645a0b1c2d3e4f#Nowhere-US-203
```

Последний пример — самоподписанный Portal 2.2.

* Двухносительный компактный Portal шарится как `host:port`. Сторона `mix` публикуется как `udp` (`net=mix` — это `mix` с обеих сторон, поэтому `up=udp&down=udp`). Явные пути или разделённые порты используют форму пути
* Endpoint только TCP / только UDP шарятся как `up=tcp&down=tcp` или `up=udp&down=udp`. 2.0 не добавляет `mux=1`; 1.x для `tcp/tcp` добавляет
* `morph=1` у Portal копируется в share URI
* `tls`, `crt`, `key`, `net`, `dial`, `rate`, `etar`, `log`, исходящий `socks` и `next` опускаются
* На 1.x нестандартный `alpn` копируется; share URI 2.0 никогда не содержит `alpn`
* На 2.2+ при `tls=1` доступный отпечаток встраивается как `pin=`
