#!/bin/bash

# Nowhere one-click install / upgrade / management script
# Supports Debian/Ubuntu and Alpine Linux
# Project: https://github.com/NodePassProject/Nowhere

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths and constants
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nowhere"
URL_FILE="${CONFIG_DIR}/url.conf"
HOST_FILE="${CONFIG_DIR}/host.conf"
LAUNCHER="${INSTALL_DIR}/nowhere-launch.sh"
SERVICE_NAME="nowhere"
GITHUB_REPO="NodePassProject/Nowhere"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
DEFAULT_ALPN="now/1"

# Detected system info
OS_ID=""
OS_VERSION_ID=""
ARCH=""
LIBC=""
PKG_MANAGER=""
INIT_SYSTEM=""

# CLI mode flag
AUTO_MODE=""

# One-click install arguments
ARG_KEY=""
ARG_PORT=""
ARG_ALPN=""
ARG_HOST=""
ARG_NET=""
ARG_TLS=""
ARG_CERT=""
ARG_KEYFILE=""
ARG_LANG=""
ARG_VERSION=""

# Language
SCRIPT_LANG="zh"
declare -A MSG

# ==================== i18n ====================
t() {
    local key="$1"
    shift
    local msg="${MSG[$key]:-$key}"
    if [[ $# -gt 0 ]]; then
        # shellcheck disable=SC2059
        printf "$msg" "$@"
    else
        printf "%s" "$msg"
    fi
}

set_language() {
    local lang="${1:-zh}"
    case "$lang" in
        en|zh|ru) SCRIPT_LANG="$lang" ;;
        *) SCRIPT_LANG="zh" ;;
    esac
    MSG=()

    case "$SCRIPT_LANG" in
        en)
            MSG[err_root]="This script must be run as root"
            MSG[err_os_unknown]="Unable to detect OS"
            MSG[err_os_unsupported]="Only Debian/Ubuntu/Alpine are supported, detected: %s"
            MSG[err_arch]="Unsupported architecture: %s"
            MSG[err_github]="Failed to fetch latest GitHub release"
            MSG[err_github_parse]="Failed to parse GitHub API response"
            MSG[err_download]="Download failed: %s"
            MSG[err_binary]="nowhere binary not found in archive"
            MSG[err_unknown_opt]="Unknown option: %s"
            MSG[err_invalid_choice]="Invalid choice"
            MSG[err_lang]="Invalid language: %s (use en|zh|ru)"
            MSG[warn_musl]="System may be using musl libc"
            MSG[prompt_musl]="Switch to musl build? [y/N]: "
            MSG[info_os]="OS: %s %s, Init: %s"
            MSG[info_arch]="Arch: %s, libc: %s"
            MSG[info_install_deps]="Installing dependencies: %s"
            MSG[info_query_version]="Fetching latest version..."
            MSG[info_download]="Downloading nowhere %s (%s)"
            MSG[info_install_to]="Installing to %s"
            MSG[ok_upgraded]="Nowhere upgraded to %s"
            MSG[ok_installed]="Nowhere %s installed"
            MSG[warn_uninstall]="About to uninstall Nowhere..."
            MSG[prompt_uninstall]="Confirm uninstall? [y/N]: "
            MSG[info_cancelled]="Cancelled"
            MSG[prompt_del_config]="Delete config %s? [y/N]: "
            MSG[ok_uninstalled]="Nowhere uninstalled"
            MSG[warn_svc_missing]="Service not running or not installed"
            MSG[warn_svc_detect]="Unable to detect service status"
            MSG[info_configure]="Configure Nowhere Portal"
            MSG[prompt_config_intro]="Enter config (press Enter for defaults):"
            MSG[prompt_key]="Shared key [%s]: "
            MSG[prompt_port]="Listen port [%s]: "
            MSG[prompt_alpn]="ALPN [%s]: "
            MSG[prompt_host]="Public hostname for share/SNI (optional) [%s]: "
            MSG[prompt_net]="Network mode (mix/tcp/udp) [%s]: "
            MSG[prompt_tls]="TLS mode (1=self-signed, 2=custom cert) [%s]: "
            MSG[prompt_cert]="Certificate path [%s]: "
            MSG[prompt_keyfile]="Private key path [%s]: "
            MSG[warn_spec_removed]="spec was removed in Nowhere 1.5; ignoring --spec"
            MSG[warn_migrated_spec]="Removed deprecated spec= from %s (Nowhere 1.5)"
            MSG[warn_v15_incompat]="Nowhere 1.5 is not wire-compatible with older clients; upgrade clients together. Anywhere is not ready for 1.5 yet."
            MSG[warn_sni_missing]="TLS=2 but no public hostname set; share URI omits sni (certificate verification disabled)."
            MSG[label_generated_url]="Generated URL:"
            MSG[ok_config_updated]="Config updated and service restarted"
            MSG[prompt_save_config]="Save this config? [Y/n]: "
            MSG[ok_config_saved]="Config saved to %s"
            MSG[prompt_install_svc]="Install/update system service? [Y/n]: "
            MSG[warn_no_init]="systemd/openrc not detected, skipping service install"
            MSG[ok_svc_installed]="Service installed"
            MSG[prompt_start_svc]="Start/restart service now? [Y/n]: "
            MSG[ok_svc_started]="Service started"
            MSG[info_config_not_saved]="Config not saved"
            MSG[label_current_ver]="Current version: %s"
            MSG[label_latest_ver]="GitHub latest: %s"
            MSG[not_installed]="not installed"
            MSG[info_already_latest]="Already at latest version %s"
            MSG[info_already_target]="Already at target version %s"
            MSG[label_target_ver]="Target version: %s"
            MSG[prompt_force_reinstall]="Force reinstall? [y/N]: "
            MSG[info_skip_force]="One-shot mode: skipping force reinstall"
            MSG[info_svc_restarted]="Service restarted"
            MSG[warn_already_installed]="Installed version detected: %s"
            MSG[prompt_overwrite]="Overwrite install/upgrade? [y/N]: "
            MSG[prompt_config_now]="Configure service now? [Y/n]: "
            MSG[info_skip_config]="Skipped config; choose \"Configure service\" later"
            MSG[info_gen_config]="Generating Nowhere Portal config..."
            MSG[info_random_key]="Generated random shared key: %s"
            MSG[info_key_hint]="Press Enter to keep it, or type a custom key:"
            MSG[ok_config_written]="Config written to %s"
            MSG[label_run_url]="Run URL: %s"
            MSG[info_share_key]="Shared key: %s"
            MSG[ok_systemd_started]="systemd service started"
            MSG[ok_openrc_started]="openrc service started"
            MSG[warn_manual_start]="systemd/openrc not detected, start manually"
            MSG[warn_no_config]="Config not found; install and configure Nowhere first"
            MSG[share_title]="========== Nowhere Client Share =========="
            MSG[label_qr]="QR code:"
            MSG[label_client_uri]="Client URI:"
            MSG[warn_tls_skip]="TLS=1 (self-signed). Clients must skip certificate verification."
            MSG[status_title]="========== Nowhere Status =========="
            MSG[label_binary]="Binary:     %s"
            MSG[label_version]="Version:    %s"
            MSG[label_system]="OS:         %s %s"
            MSG[label_arch_libc]="Arch/libc:  %s/%s"
            MSG[label_config_file]="Config:     %s"
            MSG[label_run_url_status]="Run URL:    %s"
            MSG[not_configured]="not configured"
            MSG[label_svc_status]="Service status:"
            MSG[menu_title]="      Nowhere Manager"
            MSG[menu_version]="  Version:  %s"
            MSG[menu_system]="  OS:       %s %s"
            MSG[menu_arch]="  Arch:     %s/%s"
            MSG[menu_1]="One-click install"
            MSG[menu_2]="Upgrade Nowhere"
            MSG[menu_3]="Configure service"
            MSG[menu_4]="Start service"
            MSG[menu_5]="Stop service"
            MSG[menu_6]="Restart service"
            MSG[menu_7]="Show status"
            MSG[menu_8]="Uninstall Nowhere"
            MSG[menu_9]="Show share URI"
            MSG[menu_10]="Install QR code support"
            MSG[menu_11]="Change language"
            MSG[menu_12]="Install specific version"
            MSG[menu_0]="Exit"
            MSG[prompt_menu]="Enter option [0-12]: "
            MSG[ok_start_sent]="Start command sent"
            MSG[ok_stop_sent]="Stop command sent"
            MSG[ok_restart_sent]="Restart command sent"
            MSG[info_exit]="Exit"
            MSG[prompt_continue]="Press Enter to continue..."
            MSG[qr_ready]="QR support already available (%s)"
            MSG[qr_warn_apt]="Will install qrencode via apt. Extra disk use is usually a few MB."
            MSG[qr_warn_apk]="Alpine has no qrencode package. Will install python3 + py3-qrcode instead. This may use tens of MB of disk."
            MSG[prompt_qr_confirm]="Continue install? [y/N]: "
            MSG[info_qr_installing]="Installing QR dependencies..."
            MSG[ok_qr_installed]="QR support installed. Use menu item 9 to show QR code."
            MSG[err_qr_install]="Failed to install QR dependencies"
            MSG[info_target_version]="Target version: %s"
            MSG[prompt_version]="Enter version (e.g. v1.2.3): "
            MSG[err_version_empty]="Version cannot be empty"
            MSG[ok_target_version_set]="Will install version: %s"
            MSG[info_fetch_versions]="Fetching available versions..."
            MSG[prompt_select_version]="Select version [0=latest, 1-%s]: "
            MSG[err_no_versions]="No releases found"
            MSG[err_invalid_version_choice]="Invalid choice"
            MSG[label_latest_version]="latest"
            MSG[info_lang_set]="Language set to: %s"
            MSG[help_title]="Nowhere one-click install script"
            MSG[help_usage]="Usage:"
            MSG[help_options]="Options:"
            MSG[help_no_opt]="No options: enter interactive menu."
            MSG[help_examples]="Examples:"
            MSG[help_opt_install]="  -i, --install          One-shot install/upgrade and start"
            MSG[help_opt_upgrade]="  -u, --upgrade          One-shot upgrade"
            MSG[help_opt_config]="  -c, --config           Configure service"
            MSG[help_opt_status]="  -s, --status           Show status"
            MSG[help_opt_share]="  -q, --share            Show share URI"
            MSG[help_opt_uninstall]="  --uninstall            One-shot uninstall"
            MSG[help_opt_key]="  -k, --key <key>        Shared key"
            MSG[help_opt_port]="  -p, --port <port>      Listen port (default 2077)"
            MSG[help_opt_alpn]="      --alpn <alpn>      ALPN (default now/1, omitted when default)"
            MSG[help_opt_host]="      --host <hostname>  Public hostname for share URI / SNI"
            MSG[help_opt_net]="      --net <mix|tcp|udp>  Network mode (default mix)"
            MSG[help_opt_tls]="      --tls <1|2>        TLS mode (default 1)"
            MSG[help_opt_cert]="      --cert <path>      Cert path when TLS=2"
            MSG[help_opt_keyfile]="      --keyfile <path>   Key path when TLS=2"
            MSG[help_opt_version]="  -v, --version <ver>    Install specific version (e.g. v1.2.3)"
            MSG[help_opt_lang]="  -l, --lang <en|zh|ru>  Script language (default zh)"
            MSG[help_opt_help]="  -h, --help             Show help"
            ;;
        ru)
            MSG[err_root]="Скрипт нужно запускать от root"
            MSG[err_os_unknown]="Не удалось определить ОС"
            MSG[err_os_unsupported]="Поддерживаются только Debian/Ubuntu/Alpine, обнаружено: %s"
            MSG[err_arch]="Неподдерживаемая архитектура: %s"
            MSG[err_github]="Не удалось получить последний релиз GitHub"
            MSG[err_github_parse]="Ошибка разбора ответа GitHub API"
            MSG[err_download]="Ошибка загрузки: %s"
            MSG[err_binary]="Бинарный файл nowhere не найден в архиве"
            MSG[err_unknown_opt]="Неизвестный параметр: %s"
            MSG[err_invalid_choice]="Неверный выбор"
            MSG[err_lang]="Неверный язык: %s (en|zh|ru)"
            MSG[warn_musl]="Система, возможно, использует musl libc"
            MSG[prompt_musl]="Переключиться на сборку musl? [y/N]: "
            MSG[info_os]="ОС: %s %s, Init: %s"
            MSG[info_arch]="Архитектура: %s, libc: %s"
            MSG[info_install_deps]="Установка зависимостей: %s"
            MSG[info_query_version]="Получение последней версии..."
            MSG[info_download]="Загрузка nowhere %s (%s)"
            MSG[info_install_to]="Установка в %s"
            MSG[ok_upgraded]="Nowhere обновлён до %s"
            MSG[ok_installed]="Nowhere %s установлен"
            MSG[warn_uninstall]="Будет удален Nowhere..."
            MSG[prompt_uninstall]="Подтвердить удаление? [y/N]: "
            MSG[info_cancelled]="Отменено"
            MSG[prompt_del_config]="Удалить конфиг %s? [y/N]: "
            MSG[ok_uninstalled]="Nowhere удалён"
            MSG[warn_svc_missing]="Служба не запущена или не установлена"
            MSG[warn_svc_detect]="Не удалось определить статус службы"
            MSG[info_configure]="Настройка Nowhere Portal"
            MSG[prompt_config_intro]="Введите параметры (Enter — значение по умолчанию):"
            MSG[prompt_key]="Общий ключ [%s]: "
            MSG[prompt_port]="Порт [%s]: "
            MSG[prompt_alpn]="ALPN [%s]: "
            MSG[prompt_host]="Публичное имя для share/SNI (необязательно) [%s]: "
            MSG[prompt_net]="Сеть (mix/tcp/udp) [%s]: "
            MSG[prompt_tls]="TLS (1=самоподписанный, 2=свой сертификат) [%s]: "
            MSG[prompt_cert]="Путь к сертификату [%s]: "
            MSG[prompt_keyfile]="Путь к ключу [%s]: "
            MSG[warn_spec_removed]="Параметр spec удалён в Nowhere 1.5; --spec игнорируется"
            MSG[warn_migrated_spec]="Удалён устаревший spec= из %s (Nowhere 1.5)"
            MSG[warn_v15_incompat]="Nowhere 1.5 несовместим со старыми клиентами; обновляйте вместе. Anywhere пока не готов к 1.5."
            MSG[warn_sni_missing]="TLS=2, но публичное имя не задано; в share URI нет sni (проверка сертификата отключена)."
            MSG[label_generated_url]="Сгенерированный URL:"
            MSG[ok_config_updated]="Конфиг обновлён, служба перезапущена"
            MSG[prompt_save_config]="Сохранить конфиг? [Y/n]: "
            MSG[ok_config_saved]="Конфиг сохранён в %s"
            MSG[prompt_install_svc]="Установить/обновить системную службу? [Y/n]: "
            MSG[warn_no_init]="systemd/openrc не найдены, установка службы пропущена"
            MSG[ok_svc_installed]="Служба установлена"
            MSG[prompt_start_svc]="Запустить/перезапустить службу сейчас? [Y/n]: "
            MSG[ok_svc_started]="Служба запущена"
            MSG[info_config_not_saved]="Конфиг не сохранён"
            MSG[label_current_ver]="Текущая версия: %s"
            MSG[label_latest_ver]="Последняя на GitHub: %s"
            MSG[not_installed]="не установлен"
            MSG[info_already_latest]="Уже последняя версия %s"
            MSG[info_already_target]="Уже целевая версия %s"
            MSG[label_target_ver]="Целевая версия: %s"
            MSG[prompt_force_reinstall]="Принудительно переустановить? [y/N]: "
            MSG[info_skip_force]="Одноразовый режим: принудительная переустановка пропущена"
            MSG[info_svc_restarted]="Служба перезапущена"
            MSG[warn_already_installed]="Обнаружена установленная версия: %s"
            MSG[prompt_overwrite]="Переустановить/обновить? [y/N]: "
            MSG[prompt_config_now]="Настроить службу сейчас? [Y/n]: "
            MSG[info_skip_config]="Настройка пропущена; позже выберите «Настройка службы»"
            MSG[info_gen_config]="Создание конфига Nowhere Portal..."
            MSG[info_random_key]="Сгенерирован случайный ключ: %s"
            MSG[info_key_hint]="Enter — оставить, или введите свой ключ:"
            MSG[ok_config_written]="Конфиг записан в %s"
            MSG[label_run_url]="URL запуска: %s"
            MSG[info_share_key]="Общий ключ: %s"
            MSG[ok_systemd_started]="Служба systemd запущена"
            MSG[ok_openrc_started]="Служба openrc запущена"
            MSG[warn_manual_start]="systemd/openrc не найдены, запустите вручную"
            MSG[warn_no_config]="Конфиг не найден; сначала установите и настройте Nowhere"
            MSG[share_title]="========== Поделиться клиентом Nowhere =========="
            MSG[label_qr]="QR-код:"
            MSG[label_client_uri]="URI клиента:"
            MSG[warn_tls_skip]="TLS=1 (самоподписанный сертификат). Клиенту нужно пропустить проверку сертификата."
            MSG[status_title]="========== Статус Nowhere =========="
            MSG[label_binary]="Бинарник:   %s"
            MSG[label_version]="Версия:     %s"
            MSG[label_system]="ОС:         %s %s"
            MSG[label_arch_libc]="Arch/libc:  %s/%s"
            MSG[label_config_file]="Конфиг:     %s"
            MSG[label_run_url_status]="URL:        %s"
            MSG[not_configured]="не настроен"
            MSG[label_svc_status]="Статус службы:"
            MSG[menu_title]="      Менеджер Nowhere"
            MSG[menu_version]="  Версия:   %s"
            MSG[menu_system]="  ОС:       %s %s"
            MSG[menu_arch]="  Arch:     %s/%s"
            MSG[menu_1]="Однократная установка"
            MSG[menu_2]="Обновить Nowhere"
            MSG[menu_3]="Настроить службу"
            MSG[menu_4]="Запустить службу"
            MSG[menu_5]="Остановить службу"
            MSG[menu_6]="Перезапустить службу"
            MSG[menu_7]="Показать статус"
            MSG[menu_8]="Удалить Nowhere"
            MSG[menu_9]="Показать URI для шаринга"
            MSG[menu_10]="Установить поддержку QR"
            MSG[menu_11]="Сменить язык"
            MSG[menu_12]="Установить указанную версию"
            MSG[menu_0]="Выход"
            MSG[prompt_menu]="Введите пункт [0-12]: "
            MSG[ok_start_sent]="Команда запуска отправлена"
            MSG[ok_stop_sent]="Команда остановки отправлена"
            MSG[ok_restart_sent]="Команда перезапуска отправлена"
            MSG[info_exit]="Выход"
            MSG[prompt_continue]="Нажмите Enter для продолжения..."
            MSG[qr_ready]="Поддержка QR уже доступна (%s)"
            MSG[qr_warn_apt]="Будет установлен qrencode через apt. Обычно занимает несколько МБ."
            MSG[qr_warn_apk]="В Alpine нет пакета qrencode. Будут установлены python3 + py3-qrcode. Может занять десятки МБ."
            MSG[prompt_qr_confirm]="Продолжить установку? [y/N]: "
            MSG[info_qr_installing]="Установка зависимостей QR..."
            MSG[ok_qr_installed]="Поддержка QR установлена. Пункт меню 9 покажет QR-код."
            MSG[err_qr_install]="Не удалось установить зависимости QR"
            MSG[info_target_version]="Целевая версия: %s"
            MSG[prompt_version]="Введите версию (например v1.2.3): "
            MSG[err_version_empty]="Версия не может быть пустой"
            MSG[ok_target_version_set]="Будет установлена версия: %s"
            MSG[info_fetch_versions]="Получение доступных версий..."
            MSG[prompt_select_version]="Выберите версию [0=последняя, 1-%s]: "
            MSG[err_no_versions]="Релизы не найдены"
            MSG[err_invalid_version_choice]="Неверный выбор"
            MSG[label_latest_version]="последняя"
            MSG[info_lang_set]="Язык установлен: %s"
            MSG[help_title]="Скрипт однократной установки Nowhere"
            MSG[help_usage]="Использование:"
            MSG[help_options]="Параметры:"
            MSG[help_no_opt]="Без параметров: интерактивное меню."
            MSG[help_examples]="Примеры:"
            MSG[help_opt_install]="  -i, --install          Установка/обновление и запуск"
            MSG[help_opt_upgrade]="  -u, --upgrade          Обновление"
            MSG[help_opt_config]="  -c, --config           Настройка службы"
            MSG[help_opt_status]="  -s, --status           Статус"
            MSG[help_opt_share]="  -q, --share            URI для шаринга"
            MSG[help_opt_uninstall]="  --uninstall            Удаление"
            MSG[help_opt_key]="  -k, --key <ключ>       Общий ключ"
            MSG[help_opt_port]="  -p, --port <порт>      Порт (по умолчанию 2077)"
            MSG[help_opt_alpn]="      --alpn <alpn>      ALPN (по умолчанию now/1, default не пишется)"
            MSG[help_opt_host]="      --host <hostname>  Публичное имя для share URI / SNI"
            MSG[help_opt_net]="      --net <mix|tcp|udp>  Сеть (по умолчанию mix)"
            MSG[help_opt_tls]="      --tls <1|2>        Режим TLS (по умолчанию 1)"
            MSG[help_opt_cert]="      --cert <путь>      Сертификат при TLS=2"
            MSG[help_opt_keyfile]="      --keyfile <путь>   Ключ при TLS=2"
            MSG[help_opt_version]="  -v, --version <ver>    Установить указанную версию (например v1.2.3)"
            MSG[help_opt_lang]="  -l, --lang <en|zh|ru>  Язык скрипта (по умолчанию zh)"
            MSG[help_opt_help]="  -h, --help             Справка"
            ;;
        *)
            # zh (default)
            MSG[err_root]="此脚本需要 root 权限运行"
            MSG[err_os_unknown]="无法识别系统"
            MSG[err_os_unsupported]="仅支持 Debian/Ubuntu/Alpine，检测到: %s"
            MSG[err_arch]="不支持的架构: %s"
            MSG[err_github]="无法获取 GitHub 最新版本"
            MSG[err_github_parse]="解析 GitHub API 失败"
            MSG[err_download]="下载失败: %s"
            MSG[err_binary]="压缩包中未找到 nowhere 二进制"
            MSG[err_unknown_opt]="未知选项: %s"
            MSG[err_invalid_choice]="无效选择"
            MSG[err_lang]="无效语言: %s（使用 en|zh|ru）"
            MSG[warn_musl]="检测到系统可能使用 musl libc"
            MSG[prompt_musl]="是否切换到 musl 构建版本? [y/N]: "
            MSG[info_os]="系统: %s %s, Init: %s"
            MSG[info_arch]="架构: %s, libc: %s"
            MSG[info_install_deps]="安装依赖: %s"
            MSG[info_query_version]="查询最新版本..."
            MSG[info_download]="下载 nowhere %s (%s)"
            MSG[info_install_to]="安装到 %s"
            MSG[ok_upgraded]="Nowhere 已升级至 %s"
            MSG[ok_installed]="Nowhere %s 安装完成"
            MSG[warn_uninstall]="即将卸载 Nowhere..."
            MSG[prompt_uninstall]="确认卸载? [y/N]: "
            MSG[info_cancelled]="已取消"
            MSG[prompt_del_config]="删除配置文件 %s? [y/N]: "
            MSG[ok_uninstalled]="Nowhere 已卸载"
            MSG[warn_svc_missing]="服务未运行或未安装"
            MSG[warn_svc_detect]="无法检测服务状态"
            MSG[info_configure]="配置 Nowhere Portal"
            MSG[prompt_config_intro]="请输入配置参数（直接回车使用默认值）："
            MSG[prompt_key]="共享密钥 [%s]: "
            MSG[prompt_port]="监听端口 [%s]: "
            MSG[prompt_alpn]="ALPN [%s]: "
            MSG[prompt_host]="分享/SNI 用的公网主机名（可选）[%s]: "
            MSG[prompt_net]="网络模式 (mix/tcp/udp) [%s]: "
            MSG[prompt_tls]="TLS 模式 (1=自签, 2=自定义证书) [%s]: "
            MSG[prompt_cert]="证书路径 [%s]: "
            MSG[prompt_keyfile]="私钥路径 [%s]: "
            MSG[warn_spec_removed]="Nowhere 1.5 已移除 spec；忽略 --spec"
            MSG[warn_migrated_spec]="已从 %s 移除废弃的 spec=（Nowhere 1.5）"
            MSG[warn_v15_incompat]="Nowhere 1.5 与旧版客户端协议不兼容，请一并升级；Anywhere 尚未适配 1.5。"
            MSG[warn_sni_missing]="TLS=2 但未设置公网主机名；分享 URI 将省略 sni（跳过证书校验）。"
            MSG[label_generated_url]="生成的 URL："
            MSG[ok_config_updated]="配置已更新并重启服务"
            MSG[prompt_save_config]="是否保存此配置? [Y/n]: "
            MSG[ok_config_saved]="配置已保存到 %s"
            MSG[prompt_install_svc]="是否安装/更新系统服务? [Y/n]: "
            MSG[warn_no_init]="未检测到 systemd/openrc，跳过服务安装"
            MSG[ok_svc_installed]="服务已安装"
            MSG[prompt_start_svc]="是否立即启动/重启服务? [Y/n]: "
            MSG[ok_svc_started]="服务已启动"
            MSG[info_config_not_saved]="配置未保存"
            MSG[label_current_ver]="当前版本: %s"
            MSG[label_latest_ver]="GitHub 最新版本: %s"
            MSG[not_installed]="未安装"
            MSG[info_already_latest]="当前已是最新版本 %s"
            MSG[info_already_target]="当前已是目标版本 %s"
            MSG[label_target_ver]="目标版本: %s"
            MSG[prompt_force_reinstall]="是否强制重新安装? [y/N]: "
            MSG[info_skip_force]="远程一键模式：跳过强制重装"
            MSG[info_svc_restarted]="服务已重新启动"
            MSG[warn_already_installed]="检测到已安装版本: %s"
            MSG[prompt_overwrite]="是否覆盖安装/升级? [y/N]: "
            MSG[prompt_config_now]="是否立即配置服务? [Y/n]: "
            MSG[info_skip_config]="跳过配置，之后可运行脚本选择“配置/重新配置服务”"
            MSG[info_gen_config]="生成 Nowhere Portal 配置..."
            MSG[info_random_key]="已生成随机共享密钥: %s"
            MSG[info_key_hint]="直接回车使用随机密钥，或输入自定义密钥："
            MSG[ok_config_written]="配置已写入 %s"
            MSG[label_run_url]="运行 URL: %s"
            MSG[info_share_key]="共享密钥: %s"
            MSG[ok_systemd_started]="systemd 服务已启动"
            MSG[ok_openrc_started]="openrc 服务已启动"
            MSG[warn_manual_start]="未检测到 systemd/openrc，请手动启动"
            MSG[warn_no_config]="未找到配置文件，请先安装并配置 Nowhere"
            MSG[share_title]="========== Nowhere 客户端分享 =========="
            MSG[label_qr]="二维码："
            MSG[label_client_uri]="客户端 URI："
            MSG[warn_tls_skip]="当前为 TLS=1（自签证书），客户端连接时需跳过证书验证。"
            MSG[status_title]="========== Nowhere 状态 =========="
            MSG[label_binary]="二进制位置: %s"
            MSG[label_version]="当前版本:   %s"
            MSG[label_system]="系统:       %s %s"
            MSG[label_arch_libc]="架构/libc:  %s/%s"
            MSG[label_config_file]="配置文件:   %s"
            MSG[label_run_url_status]="运行 URL:   %s"
            MSG[not_configured]="未配置"
            MSG[label_svc_status]="服务状态："
            MSG[menu_title]="      Nowhere 管理脚本"
            MSG[menu_version]="  当前版本: %s"
            MSG[menu_system]="  系统:     %s %s"
            MSG[menu_arch]="  架构:     %s/%s"
            MSG[menu_1]="一键安装"
            MSG[menu_2]="升级 Nowhere"
            MSG[menu_3]="配置/重新配置服务"
            MSG[menu_4]="启动服务"
            MSG[menu_5]="停止服务"
            MSG[menu_6]="重启服务"
            MSG[menu_7]="查看状态"
            MSG[menu_8]="卸载 Nowhere"
            MSG[menu_9]="显示分享 URI"
            MSG[menu_10]="安装二维码支持库"
            MSG[menu_11]="切换语言"
            MSG[menu_12]="安装指定版本"
            MSG[menu_0]="退出"
            MSG[prompt_menu]="请输入选项 [0-12]: "
            MSG[ok_start_sent]="启动命令已发送"
            MSG[ok_stop_sent]="停止命令已发送"
            MSG[ok_restart_sent]="重启命令已发送"
            MSG[info_exit]="退出"
            MSG[prompt_continue]="按 Enter 键继续..."
            MSG[qr_ready]="二维码支持已可用（%s）"
            MSG[qr_warn_apt]="将通过 apt 安装 qrencode，额外磁盘占用通常约数 MB。"
            MSG[qr_warn_apk]="Alpine 官方源无 qrencode，将改用 python3 + py3-qrcode，体积明显更大（可能数十 MB）。"
            MSG[prompt_qr_confirm]="是否继续安装? [y/N]: "
            MSG[info_qr_installing]="正在安装二维码依赖..."
            MSG[ok_qr_installed]="二维码支持已安装。可使用菜单项 9 显示二维码。"
            MSG[err_qr_install]="二维码依赖安装失败"
            MSG[info_target_version]="目标版本: %s"
            MSG[prompt_version]="请输入版本号 (例如 v1.2.3): "
            MSG[err_version_empty]="版本号不能为空"
            MSG[ok_target_version_set]="将要安装版本: %s"
            MSG[info_fetch_versions]="正在获取可用版本..."
            MSG[prompt_select_version]="请选择版本 [0=最新版, 1-%s]: "
            MSG[err_no_versions]="未找到任何 release"
            MSG[err_invalid_version_choice]="选择无效"
            MSG[label_latest_version]="最新版"
            MSG[info_lang_set]="语言已设置为: %s"
            MSG[help_title]="Nowhere 一键安装脚本"
            MSG[help_usage]="用法:"
            MSG[help_options]="选项:"
            MSG[help_no_opt]="无选项时进入交互式菜单。"
            MSG[help_examples]="示例:"
            MSG[help_opt_install]="  -i, --install          一键安装/升级并启动服务"
            MSG[help_opt_upgrade]="  -u, --upgrade          一键升级"
            MSG[help_opt_config]="  -c, --config           交互式配置服务"
            MSG[help_opt_status]="  -s, --status           查看状态"
            MSG[help_opt_share]="  -q, --share            显示分享 URI"
            MSG[help_opt_uninstall]="  --uninstall            一键卸载"
            MSG[help_opt_key]="  -k, --key <密钥>       指定共享密钥"
            MSG[help_opt_port]="  -p, --port <端口>      指定监听端口 (默认 2077)"
            MSG[help_opt_alpn]="      --alpn <alpn>      指定 ALPN (默认 now/1，默认值不写入 URL)"
            MSG[help_opt_host]="      --host <hostname>  分享 URI / SNI 用的公网主机名"
            MSG[help_opt_net]="      --net <mix|tcp|udp>  指定网络模式 (默认 mix)"
            MSG[help_opt_tls]="      --tls <1|2>        指定 TLS 模式 (默认 1)"
            MSG[help_opt_cert]="      --cert <路径>      TLS=2 时的证书路径"
            MSG[help_opt_keyfile]="      --keyfile <路径>   TLS=2 时的私钥路径"
            MSG[help_opt_version]="  -v, --version <版本>   安装指定版本 (例如 v1.2.3)"
            MSG[help_opt_lang]="  -l, --lang <en|zh|ru>  脚本语言 (默认 zh)"
            MSG[help_opt_help]="  -h, --help             显示帮助"
            ;;
    esac
}

set_language "zh"

# ==================== Logging ====================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# ==================== System detection ====================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "$(t err_root)"
        exit 1
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "$(t err_os_unknown)"
        exit 1
    fi

    OS_ID=$(grep -E '^ID=' /etc/os-release | head -n1 | cut -d'=' -f2 | tr -d '"')
    OS_VERSION_ID=$(grep -E '^VERSION_ID=' /etc/os-release | head -n1 | cut -d'=' -f2 | tr -d '"')

    case "$OS_ID" in
        debian|ubuntu) PKG_MANAGER="apt" ;;
        alpine)        PKG_MANAGER="apk" ;;
        *)
            log_error "$(t err_os_unsupported "$OS_ID")"
            exit 1
            ;;
    esac

    if [[ -d /run/systemd/system ]] || command -v systemctl &>/dev/null; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service &>/dev/null || [[ -d /etc/init.d ]]; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="unknown"
    fi

    log_info "$(t info_os "$OS_ID" "$OS_VERSION_ID" "$INIT_SYSTEM")"
}

detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)  ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        *)
            log_error "$(t err_arch "$machine")"
            exit 1
            ;;
    esac

    if [[ "$OS_ID" == "alpine" ]]; then
        LIBC="musl"
    else
        LIBC="gnu"
    fi

    log_info "$(t info_arch "$ARCH" "$LIBC")"
}

detect_libc_runtime() {
    if [[ "$OS_ID" != "alpine" ]] && ldd --version 2>/dev/null | grep -qi musl; then
        log_warn "$(t warn_musl)"
        read -rp "$(t prompt_musl)" use_musl
        if [[ "$use_musl" =~ ^[Yy]$ ]]; then
            LIBC="musl"
        fi
    fi
}

# ==================== Dependencies ====================
check_dependencies() {
    local deps=("curl" "tar")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "$(t info_install_deps "${missing[*]}")"
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            apt-get update -qq && apt-get install -y -qq curl tar
        elif [[ "$PKG_MANAGER" == "apk" ]]; then
            apk add --no-cache curl tar
        fi
    fi
}

# ==================== Helpers ====================
generate_random_key() {
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16
}

get_public_ip() {
    local ip=""
    for api in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ifconfig.me"; do
        ip=$(curl -fsSL --connect-timeout 5 "$api" 2>/dev/null | head -n1 | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        [[ -n "$ip" ]] && break
    done
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    echo "$ip"
}

url_encode_alpn() {
    local value="$1"
    # Encode reserved characters commonly present in ALPN values.
    value="${value//'/'/%2F}"
    value="${value//' '/%20}"
    value="${value//'#'/%23}"
    value="${value//'?'/%3F}"
    value="${value//'&'/%26}"
    value="${value//'='/%3D}"
    printf '%s' "$value"
}

url_decode_simple() {
    local value="${1//+/+}"
    printf '%b' "${value//%/\\x}"
}

load_share_host() {
    if [[ -n "$ARG_HOST" ]]; then
        echo "$ARG_HOST"
        return
    fi
    if [[ -f "$HOST_FILE" ]]; then
        tr -d '\n' < "$HOST_FILE"
    fi
}

save_share_host() {
    local host="$1"
    mkdir -p "$CONFIG_DIR"
    if [[ -n "$host" ]]; then
        echo "$host" > "$HOST_FILE"
    else
        rm -f "$HOST_FILE"
    fi
}

strip_query_param() {
    local url="$1"
    local key="$2"
    echo "$url" | sed -E \
        -e "s/([?&])${key}=[^&]*(&|$)/\1/" \
        -e 's/\?&/?/' \
        -e 's/&&+/\&/g' \
        -e 's/\?$//' \
        -e 's/&$//'
}

append_query_param() {
    local url="$1"
    local pair="$2"
    if [[ "$url" == *\?* ]]; then
        echo "${url}&${pair}"
    else
        echo "${url}?${pair}"
    fi
}

build_portal_url() {
    local key="$1"
    local port="$2"
    local tls="$3"
    local net="$4"
    local alpn="$5"
    local crt="$6"
    local keyfile="$7"

    local url="portal://${key}@:${port}?tls=${tls}&net=${net}"
    if [[ -n "$alpn" && "$alpn" != "$DEFAULT_ALPN" ]]; then
        url="${url}&alpn=$(url_encode_alpn "$alpn")"
    fi
    if [[ "$tls" == "2" ]]; then
        url="${url}&crt=${crt}&key=${keyfile}"
    fi
    echo "$url"
}

migrate_portal_url_for_v15() {
    if [[ ! -f "$URL_FILE" ]]; then
        return 0
    fi

    local url migrated=false
    url=$(tr -d '\n' < "$URL_FILE")
    [[ -z "$url" ]] && return 0

    if echo "$url" | grep -qE '[?&]spec='; then
        url=$(strip_query_param "$url" "spec")
        migrated=true
    fi

    if [[ "$migrated" == "true" ]]; then
        echo "$url" > "$URL_FILE"
        log_warn "$(t warn_migrated_spec "$URL_FILE")"
    fi
}

qr_support_available() {
    if command -v qrencode &>/dev/null; then
        echo "qrencode"
        return 0
    fi
    if command -v python3 &>/dev/null && python3 -c "import qrcode" 2>/dev/null; then
        echo "python3-qrcode"
        return 0
    fi
    return 1
}

# ==================== Version lookup ====================
get_latest_version() {
    local response
    response=$(curl -fsSL --connect-timeout 15 "$GITHUB_API" 2>/dev/null)
    if [[ -z "$response" ]]; then
        log_error "$(t err_github)"
        exit 1
    fi

    local version
    version=$(echo "$response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
    if [[ -z "$version" ]]; then
        log_error "$(t err_github_parse)"
        exit 1
    fi

    echo "$version"
}

get_download_url() {
    local version="$1"
    local asset_name="nowhere-${ARCH}-unknown-linux-${LIBC}.tar.gz"
    echo "https://github.com/${GITHUB_REPO}/releases/download/${version}/${asset_name}"
}

get_installed_version() {
    if command -v nowhere &>/dev/null; then
        local version
        version=$(nowhere --version 2>/dev/null | head -n1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' || true)
        echo "${version#v}"
    fi
}

# ==================== Install core ====================
install_nowhere() {
    local version="$1"
    local is_upgrade="${2:-false}"

    if [[ -z "$version" ]]; then
        if [[ -n "$ARG_VERSION" ]]; then
            version="$ARG_VERSION"
        else
            log_info "$(t info_query_version)"
            version=$(get_latest_version)
        fi
    fi

    local download_url asset_name tmp_dir binary
    download_url=$(get_download_url "$version")
    asset_name="nowhere-${ARCH}-unknown-linux-${LIBC}.tar.gz"
    tmp_dir=$(mktemp -d)

    log_info "$(t info_download "$version" "$asset_name")"
    if ! curl -fL --connect-timeout 15 --max-time 120 -o "${tmp_dir}/${asset_name}" "$download_url"; then
        log_error "$(t err_download "$download_url")"
        rm -rf "$tmp_dir"
        exit 1
    fi

    log_info "$(t info_install_to "$INSTALL_DIR")"
    tar -xzf "${tmp_dir}/${asset_name}" -C "$tmp_dir"

    binary=$(find "$tmp_dir" -name "nowhere" -type f | head -n1)
    if [[ -z "$binary" ]]; then
        log_error "$(t err_binary)"
        rm -rf "$tmp_dir"
        exit 1
    fi

    chmod +x "$binary"
    mv -f "$binary" "${INSTALL_DIR}/nowhere"
    rm -rf "$tmp_dir"

    mkdir -p "$CONFIG_DIR"
    migrate_portal_url_for_v15

    if [[ "$is_upgrade" == "true" ]]; then
        log_warn "$(t warn_v15_incompat)"
        log_success "$(t ok_upgraded "$version")"
    else
        log_success "$(t ok_installed "$version")"
    fi
}

uninstall_nowhere() {
    if [[ "$AUTO_MODE" != "uninstall" ]]; then
        log_warn "$(t warn_uninstall)"
        read -rp "$(t prompt_uninstall)" confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { log_info "$(t info_cancelled)"; return; }
    fi

    stop_service
    disable_service

    rm -f "${INSTALL_DIR}/nowhere"
    rm -f "$LAUNCHER"

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload 2>/dev/null || true
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        rm -f "/etc/init.d/${SERVICE_NAME}"
        rc-update delete ${SERVICE_NAME} default 2>/dev/null || true
    fi

    if [[ "$AUTO_MODE" != "uninstall" ]]; then
        read -rp "$(t prompt_del_config "$CONFIG_DIR")" del_config
        [[ "$del_config" =~ ^[Yy]$ ]] && rm -rf "$CONFIG_DIR"
    else
        rm -rf "$CONFIG_DIR"
    fi

    log_success "$(t ok_uninstalled)"
}

# ==================== Service setup ====================
write_launcher() {
    cat > "$LAUNCHER" <<'EOF'
#!/bin/bash
URL_FILE="/etc/nowhere/url.conf"
[[ -f "$URL_FILE" ]] || { echo "错误: 未找到 ${URL_FILE}" >&2; exit 1; }
NOWHERE_URL=$(tr -d '\n' < "$URL_FILE")
[[ -n "$NOWHERE_URL" ]] || { echo "错误: ${URL_FILE} 为空" >&2; exit 1; }
exec /usr/local/bin/nowhere "$NOWHERE_URL"
EOF
    chmod +x "$LAUNCHER"
}

install_systemd_service() {
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Nowhere Portal
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${LAUNCHER}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nowhere

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
}

install_openrc_service() {
    cat > "/etc/init.d/${SERVICE_NAME}" <<'EOF'
#!/sbin/openrc-run
description="Nowhere Portal"
command="/usr/local/bin/nowhere-launch.sh"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
depend() {
    need net
    after firewall
}
EOF
    chmod +x "/etc/init.d/${SERVICE_NAME}"
    rc-update add ${SERVICE_NAME} default 2>/dev/null || true
}

start_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl start ${SERVICE_NAME} || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} start || true
}

stop_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} stop 2>/dev/null || true
}

restart_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl restart ${SERVICE_NAME} || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} restart || true
}

disable_service() {
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    [[ "$INIT_SYSTEM" == "openrc" ]] && rc-update delete ${SERVICE_NAME} default 2>/dev/null || true
}

service_status() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl status ${SERVICE_NAME} --no-pager 2>/dev/null || log_warn "$(t warn_svc_missing)"
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        rc-service ${SERVICE_NAME} status 2>/dev/null || log_warn "$(t warn_svc_missing)"
    else
        log_warn "$(t warn_svc_detect)"
    fi
}

# ==================== Version list ====================
list_github_versions() {
    local response
    response=$(curl -fsSL --connect-timeout 15 "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=30" 2>/dev/null)
    if [[ -z "$response" ]]; then
        return 1
    fi
    echo "$response" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 30
}

# ==================== Interactive specific version install ====================
install_specific_version() {
    log_info "$(t info_fetch_versions)"
    local versions=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && versions+=("$line")
    done < <(list_github_versions)

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_error "$(t err_no_versions)"
        return 1
    fi

    echo ""
    echo -e "${CYAN}  0) $(t label_latest_version)${NC}"
    local i
    for i in "${!versions[@]}"; do
        echo -e "  ${YELLOW}$((i + 1)))${NC} ${versions[$i]}"
    done
    echo ""

    local choice
    read -rp "$(t prompt_select_version "${#versions[@]}")" choice
    choice="$(echo "$choice" | tr -d '[:space:]')"

    local version=""
    if [[ "$choice" == "0" || -z "$choice" ]]; then
        version=""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le ${#versions[@]} ]]; then
        version="${versions[$((choice - 1))]}"
    else
        log_error "$(t err_invalid_version_choice)"
        return 1
    fi

    if [[ -n "$version" ]]; then
        log_info "$(t ok_target_version_set "$version")"
        ARG_VERSION="$version"
    else
        ARG_VERSION=""
    fi

    if command -v nowhere &>/dev/null; then
        upgrade_nowhere
    else
        auto_install_nowhere
    fi
    ARG_VERSION=""
}

# ==================== Interactive configure ====================
configure_nowhere() {
    log_info "$(t info_configure)"
    mkdir -p "$CONFIG_DIR"

    local existing_url=""
    [[ -f "$URL_FILE" ]] && existing_url=$(tr -d '\n' < "$URL_FILE")

    local default_key default_port="2077" default_alpn="$DEFAULT_ALPN" default_net="mix" default_tls="1"
    local default_host=""
    default_key=$(generate_random_key)
    default_host=$(load_share_host)

    if [[ -n "$existing_url" ]]; then
        default_key=$(echo "$existing_url" | sed -n 's/.*portal:\/\/\([^@]*\)@.*/\1/p'); default_key=${default_key:-$(generate_random_key)}
        default_port=$(echo "$existing_url" | sed -n 's/.*:\([0-9]*\).*/\1/p'); default_port=${default_port:-2077}
        default_net=$(echo "$existing_url" | sed -n 's/.*[?&]net=\([^&]*\).*/\1/p'); default_net=${default_net:-mix}
        default_tls=$(echo "$existing_url" | sed -n 's/.*[?&]tls=\([^&]*\).*/\1/p'); default_tls=${default_tls:-1}
        local existing_alpn
        existing_alpn=$(echo "$existing_url" | sed -n 's/.*[?&]alpn=\([^&]*\).*/\1/p')
        if [[ -n "$existing_alpn" ]]; then
            default_alpn=$(url_decode_simple "$existing_alpn")
        fi
    fi

    [[ -n "$ARG_KEY" ]] && default_key="$ARG_KEY"
    [[ -n "$ARG_PORT" ]] && default_port="$ARG_PORT"
    [[ -n "$ARG_ALPN" ]] && default_alpn="$ARG_ALPN"
    [[ -n "$ARG_NET" ]] && default_net="$ARG_NET"
    [[ -n "$ARG_TLS" ]] && default_tls="$ARG_TLS"
    [[ -n "$ARG_HOST" ]] && default_host="$ARG_HOST"

    local key="$default_key" port="$default_port" alpn="$default_alpn" net="$default_net" tls="$default_tls" host="$default_host"
    local skip_prompts=false
    if [[ "$AUTO_MODE" == "config" && -n "$ARG_KEY" ]]; then
        skip_prompts=true
        key="${ARG_KEY:-$default_key}"
        port="${ARG_PORT:-$default_port}"
        alpn="${ARG_ALPN:-$default_alpn}"
        net="${ARG_NET:-$default_net}"
        tls="${ARG_TLS:-$default_tls}"
        host="${ARG_HOST:-$default_host}"
    fi

    if [[ "$skip_prompts" == false ]]; then
        echo -e "${CYAN}$(t prompt_config_intro)${NC}"

        read -rp "$(t prompt_key "$default_key")" key_input
        [[ -n "$key_input" ]] && key="$key_input"

        read -rp "$(t prompt_port "$default_port")" port_input
        [[ -n "$port_input" ]] && port="$port_input"

        read -rp "$(t prompt_net "$default_net")" net_input
        [[ -n "$net_input" ]] && net="$net_input"

        read -rp "$(t prompt_tls "$default_tls")" tls_input
        [[ -n "$tls_input" ]] && tls="$tls_input"

        read -rp "$(t prompt_alpn "$default_alpn")" alpn_input
        [[ -n "$alpn_input" ]] && alpn="$alpn_input"

        read -rp "$(t prompt_host "$default_host")" host_input
        # Allow clearing host by typing a single dash.
        if [[ "$host_input" == "-" ]]; then
            host=""
        elif [[ -n "$host_input" ]]; then
            host="$host_input"
        fi
    fi

    local crt="/etc/nowhere/cert.pem" keyfile="/etc/nowhere/key.pem"
    if [[ "$tls" == "2" ]]; then
        local default_crt="/etc/nowhere/cert.pem" default_keyfile="/etc/nowhere/key.pem"
        crt="$default_crt"
        keyfile="$default_keyfile"
        if [[ "$skip_prompts" == true ]]; then
            crt="${ARG_CERT:-$default_crt}"
            keyfile="${ARG_KEYFILE:-$default_keyfile}"
        else
            read -rp "$(t prompt_cert "$default_crt")" crt_input
            [[ -n "$crt_input" ]] && crt="$crt_input"
            read -rp "$(t prompt_keyfile "$default_keyfile")" keyfile_input
            [[ -n "$keyfile_input" ]] && keyfile="$keyfile_input"
        fi
    fi

    local url
    url=$(build_portal_url "$key" "$port" "$tls" "$net" "$alpn" "$crt" "$keyfile")

    echo -e "\n${CYAN}$(t label_generated_url)${NC}\n${GREEN}${url}${NC}\n"

    if [[ "$AUTO_MODE" == "config" ]]; then
        echo "$url" > "$URL_FILE"
        save_share_host "$host"
        write_launcher
        if [[ "$INIT_SYSTEM" == "systemd" ]]; then
            install_systemd_service
        elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
            install_openrc_service
        fi
        restart_service
        log_success "$(t ok_config_updated)"
        return
    fi

    read -rp "$(t prompt_save_config)" save
    if [[ ! "$save" =~ ^[Nn]$ ]]; then
        echo "$url" > "$URL_FILE"
        save_share_host "$host"
        log_success "$(t ok_config_saved "$URL_FILE")"

        write_launcher

        read -rp "$(t prompt_install_svc)" install_svc
        if [[ ! "$install_svc" =~ ^[Nn]$ ]]; then
            if [[ "$INIT_SYSTEM" == "systemd" ]]; then
                install_systemd_service
            elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
                install_openrc_service
            else
                log_warn "$(t warn_no_init)"
                return
            fi
            log_success "$(t ok_svc_installed)"

            read -rp "$(t prompt_start_svc)" start_svc
            if [[ ! "$start_svc" =~ ^[Nn]$ ]]; then
                restart_service
                log_success "$(t ok_svc_started)"
            fi
        fi
    else
        log_info "$(t info_config_not_saved)"
    fi
}

# ==================== Upgrade ====================
upgrade_nowhere() {
    local installed_version latest_version
    installed_version=$(get_installed_version)

    echo -e "${CYAN}$(t label_current_ver "${installed_version:-$(t not_installed)}")${NC}"

    if [[ -n "$ARG_VERSION" ]]; then
        latest_version="$ARG_VERSION"
        echo -e "${CYAN}$(t label_target_ver "${latest_version#v}")${NC}"
        if [[ -n "$installed_version" && "$installed_version" == "${latest_version#v}" ]]; then
            log_info "$(t info_already_target "${latest_version#v}")"
        fi
    else
        latest_version=$(get_latest_version)
        echo -e "${CYAN}$(t label_latest_ver "${latest_version#v}")${NC}"

        if [[ -n "$installed_version" && "$installed_version" == "${latest_version#v}" ]]; then
            log_info "$(t info_already_latest "${latest_version#v}")"
            if [[ "$AUTO_MODE" != "upgrade" ]]; then
                read -rp "$(t prompt_force_reinstall)" force
                [[ "$force" =~ ^[Yy]$ ]] || return
            else
                log_info "$(t info_skip_force)"
                return
            fi
        fi
    fi

    if command -v nowhere &>/dev/null; then
        cp "${INSTALL_DIR}/nowhere" "${INSTALL_DIR}/nowhere.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    local was_running=false
    if [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        was_running=true; stop_service
    elif [[ "$INIT_SYSTEM" == "openrc" ]] && rc-service ${SERVICE_NAME} status 2>/dev/null | grep -q started; then
        was_running=true; stop_service
    fi

    install_nowhere "$latest_version" true

    if [[ "$was_running" == "true" ]]; then
        start_service
        log_info "$(t info_svc_restarted)"
    fi
}

# ==================== One-click install (args + interactive) ====================
auto_install_nowhere() {
    if command -v nowhere &>/dev/null; then
        log_info "$(t warn_already_installed "$(get_installed_version)")"
        upgrade_nowhere
        return
    fi

    install_nowhere

    log_info "$(t info_gen_config)"
    mkdir -p "$CONFIG_DIR"

    local key port alpn net tls host url
    port=${ARG_PORT:-2077}
    alpn=${ARG_ALPN:-$DEFAULT_ALPN}
    net=${ARG_NET:-mix}
    tls=${ARG_TLS:-1}
    host=${ARG_HOST:-}

    if [[ -n "$ARG_KEY" ]]; then
        key="$ARG_KEY"
    else
        key=$(generate_random_key)
    fi

    if [[ -t 0 && -z "$ARG_KEY" ]]; then
        echo -e "${CYAN}$(t info_random_key "${GREEN}${key}${NC}${CYAN}")${NC}"
        echo -e "${CYAN}$(t info_key_hint)${NC}"
        read -rp "$(t prompt_key "$key")" key_input
        [[ -n "$key_input" ]] && key="$key_input"

        read -rp "$(t prompt_port "$port")" port_input
        [[ -n "$port_input" ]] && port="$port_input"

        read -rp "$(t prompt_net "$net")" net_input
        [[ -n "$net_input" ]] && net="$net_input"

        read -rp "$(t prompt_tls "$tls")" tls_input
        [[ -n "$tls_input" ]] && tls="$tls_input"

        read -rp "$(t prompt_alpn "$alpn")" alpn_input
        [[ -n "$alpn_input" ]] && alpn="$alpn_input"

        read -rp "$(t prompt_host "$host")" host_input
        if [[ "$host_input" == "-" ]]; then
            host=""
        elif [[ -n "$host_input" ]]; then
            host="$host_input"
        fi
    fi

    local crt="/etc/nowhere/cert.pem" keyfile="/etc/nowhere/key.pem"
    if [[ "$tls" == "2" ]]; then
        crt=${ARG_CERT:-/etc/nowhere/cert.pem}
        keyfile=${ARG_KEYFILE:-/etc/nowhere/key.pem}
        if [[ -t 0 && -z "$ARG_CERT" ]]; then
            read -rp "$(t prompt_cert "$crt")" crt_input
            [[ -n "$crt_input" ]] && crt="$crt_input"
            read -rp "$(t prompt_keyfile "$keyfile")" keyfile_input
            [[ -n "$keyfile_input" ]] && keyfile="$keyfile_input"
        fi
    fi

    url=$(build_portal_url "$key" "$port" "$tls" "$net" "$alpn" "$crt" "$keyfile")

    echo "$url" > "$URL_FILE"
    save_share_host "$host"
    write_launcher
    log_success "$(t ok_config_written "$URL_FILE")"
    echo -e "${CYAN}$(t label_run_url "${GREEN}${url}${NC}")${NC}"
    log_info "$(t info_share_key "${GREEN}${key}${NC}")"

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        install_systemd_service
        start_service
        log_success "$(t ok_systemd_started)"
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        install_openrc_service
        start_service
        log_success "$(t ok_openrc_started)"
    else
        log_warn "$(t warn_manual_start)"
    fi
}

# ==================== Share URI ====================
show_share_uri() {
    if [[ ! -f "$URL_FILE" ]]; then
        log_warn "$(t warn_no_config)"
        return
    fi

    local server_url client_uri share_host tls_mode net_mode alpn_raw qr_tool key port
    server_url=$(tr -d '\n' < "$URL_FILE")

    key=$(echo "$server_url" | sed -n 's/^portal:\/\/\([^@]*\)@.*/\1/p')
    port=$(echo "$server_url" | sed -n 's/.*:\([0-9][0-9]*\).*/\1/p')
    port=${port:-2077}

    tls_mode=$(echo "$server_url" | sed -n 's/.*[?&]tls=\([^&]*\).*/\1/p')
    tls_mode=${tls_mode:-1}
    net_mode=$(echo "$server_url" | sed -n 's/.*[?&]net=\([^&]*\).*/\1/p')
    net_mode=${net_mode:-mix}
    alpn_raw=$(echo "$server_url" | sed -n 's/.*[?&]alpn=\([^&]*\).*/\1/p')

    share_host=$(load_share_host)
    if [[ -z "$share_host" ]]; then
        share_host=$(get_public_ip)
    fi
    if [[ -z "$share_host" ]]; then
        share_host="127.0.0.1"
    fi

    client_uri="nowhere://${key}@${share_host}:${port}"

    case "$net_mode" in
        tcp)
            client_uri=$(append_query_param "$client_uri" "up=tcp")
            client_uri=$(append_query_param "$client_uri" "down=tcp")
            client_uri=$(append_query_param "$client_uri" "pool=5")
            ;;
        udp)
            client_uri=$(append_query_param "$client_uri" "up=udp")
            client_uri=$(append_query_param "$client_uri" "down=udp")
            ;;
        *)
            # mix / default: match upstream client defaults
            client_uri=$(append_query_param "$client_uri" "up=udp")
            client_uri=$(append_query_param "$client_uri" "down=udp")
            ;;
    esac

    if [[ "$tls_mode" == "2" ]]; then
        local stored_host
        stored_host=$(load_share_host)
        if [[ -n "$stored_host" ]]; then
            client_uri=$(append_query_param "$client_uri" "sni=${stored_host}")
        else
            log_warn "$(t warn_sni_missing)"
        fi
    fi

    if [[ -n "$alpn_raw" ]]; then
        local decoded_alpn
        decoded_alpn=$(url_decode_simple "$alpn_raw")
        if [[ -n "$decoded_alpn" && "$decoded_alpn" != "$DEFAULT_ALPN" ]]; then
            client_uri=$(append_query_param "$client_uri" "alpn=${alpn_raw}")
        fi
    fi

    echo -e "\n${CYAN}$(t share_title)${NC}"
    echo -e "${CYAN}$(t label_client_uri)${NC}\n${GREEN}${client_uri}${NC}\n"

    qr_tool=$(qr_support_available || true)
    if [[ "$qr_tool" == "qrencode" ]]; then
        echo -e "${CYAN}$(t label_qr)${NC}\n"
        qrencode -t ANSI -m 2 "$client_uri" || true
        echo ""
    elif [[ "$qr_tool" == "python3-qrcode" ]]; then
        echo -e "${CYAN}$(t label_qr)${NC}\n"
        python3 -c "import qrcode,sys; qr=qrcode.QRCode(border=2); qr.add_data(sys.argv[1]); qr.make(); qr.print_tty(invert=True)" "$client_uri" || true
        echo ""
    fi

    if [[ "$tls_mode" == "1" ]]; then
        log_warn "$(t warn_tls_skip)"
    fi

    echo -e "${CYAN}========================================${NC}\n"
}

# ==================== QR dependency install ====================
install_qr_support() {
    local existing
    if existing=$(qr_support_available); then
        log_success "$(t qr_ready "$existing")"
        return 0
    fi

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        log_warn "$(t qr_warn_apt)"
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        log_warn "$(t qr_warn_apk)"
    else
        log_error "$(t err_qr_install)"
        return 1
    fi

    read -rp "$(t prompt_qr_confirm)" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "$(t info_cancelled)"
        return 0
    fi

    log_info "$(t info_qr_installing)"
    set +e
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -qq && apt-get install -y qrencode
    else
        apk add --no-cache python3 py3-qrcode
    fi
    local rc=$?
    set -e

    if [[ $rc -ne 0 ]] || ! qr_support_available >/dev/null; then
        log_error "$(t err_qr_install)"
        return 1
    fi

    log_success "$(t ok_qr_installed)"
}

# ==================== Language selection ====================
select_language() {
    local choice
    echo ""
    echo -e "${CYAN}Select language / 选择语言 / Выберите язык${NC}"
    echo -e "  ${YELLOW}1)${NC} English"
    echo -e "  ${YELLOW}2)${NC} 中文"
    echo -e "  ${YELLOW}3)${NC} Русский"
    read -rp "[1-3]: " choice
    case "$choice" in
        1) set_language "en" ;;
        3) set_language "ru" ;;
        *) set_language "zh" ;;
    esac
    log_info "$(t info_lang_set "$SCRIPT_LANG")"
}

# ==================== Status ====================
show_status() {
    echo -e "\n${CYAN}$(t status_title)${NC}"
    if command -v nowhere &>/dev/null; then
        echo -e "$(t label_binary "${GREEN}${INSTALL_DIR}/nowhere${NC}")"
        echo -e "$(t label_version "${GREEN}$(get_installed_version)${NC}")"
    else
        echo -e "$(t label_version "${RED}$(t not_installed)${NC}")"
    fi
    echo -e "$(t label_system "${GREEN}${OS_ID}" "${OS_VERSION_ID}${NC}")"
    echo -e "$(t label_arch_libc "${GREEN}${ARCH}" "${LIBC}${NC}")"
    if [[ -f "$URL_FILE" ]]; then
        echo -e "$(t label_config_file "${GREEN}${URL_FILE}${NC}")"
        echo -e "$(t label_run_url_status "${GREEN}$(tr -d '\n' < "$URL_FILE")${NC}")"
    else
        echo -e "$(t label_config_file "${YELLOW}$(t not_configured)${NC}")"
    fi
    echo -e "\n${CYAN}$(t label_svc_status)${NC}"
    service_status
    echo -e "${CYAN}==================================${NC}\n"
}

# ==================== Interactive menu ====================
show_menu() {
    clear 2>/dev/null || true
    local version
    version="$(t not_installed)"
    command -v nowhere &>/dev/null && version=$(get_installed_version)

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$(t menu_title)${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "$(t menu_version "${CYAN}${version}${NC}")"
    echo -e "$(t menu_system "${CYAN}${OS_ID}" "${OS_VERSION_ID}${NC}")"
    echo -e "$(t menu_arch "${CYAN}${ARCH}" "${LIBC}${NC}")"
    echo -e "${GREEN}========================================${NC}"
    echo -e "  ${YELLOW}1)${NC} $(t menu_1)"
    echo -e "  ${YELLOW}2)${NC} $(t menu_2)"
    echo -e "  ${YELLOW}3)${NC} $(t menu_3)"
    echo -e "  ${YELLOW}4)${NC} $(t menu_4)"
    echo -e "  ${YELLOW}5)${NC} $(t menu_5)"
    echo -e "  ${YELLOW}6)${NC} $(t menu_6)"
    echo -e "  ${YELLOW}7)${NC} $(t menu_7)"
    echo -e "  ${YELLOW}8)${NC} $(t menu_8)"
    echo -e "  ${YELLOW}9)${NC} $(t menu_9)"
    echo -e "  ${YELLOW}10)${NC} $(t menu_10)"
    echo -e "  ${YELLOW}11)${NC} $(t menu_11)"
    echo -e "  ${YELLOW}0)${NC} $(t menu_0)"
    echo -e "${GREEN}========================================${NC}"
}

run_menu() {
    if [[ -z "$ARG_LANG" ]]; then
        select_language
    fi

    while true; do
        show_menu
        read -rp "$(t prompt_menu)" choice

        case "$choice" in
            1) auto_install_nowhere ;;
            2) upgrade_nowhere ;;
            3) configure_nowhere ;;
            4) start_service; log_success "$(t ok_start_sent)" ;;
            5) stop_service; log_success "$(t ok_stop_sent)" ;;
            6) restart_service; log_success "$(t ok_restart_sent)" ;;
            7) show_status ;;
            8) uninstall_nowhere ;;
            9) show_share_uri ;;
            10) install_qr_support ;;
            11) select_language ;;
            12) install_specific_version ;;
            0) log_info "$(t info_exit)"; exit 0 ;;
            *) log_error "$(t err_invalid_choice)" ;;
        esac

        echo ""
        if [[ -t 0 ]]; then
            read -rp "$(t prompt_continue)"
        fi
    done
}

# ==================== Argument parsing ====================
show_help() {
    cat <<EOF
$(t help_title)

$(t help_usage)
  bash install.sh [options]

$(t help_options)
$(t help_opt_install)
$(t help_opt_upgrade)
$(t help_opt_config)
$(t help_opt_status)
$(t help_opt_share)
$(t help_opt_uninstall)
$(t help_opt_key)
$(t help_opt_port)
$(t help_opt_alpn)
$(t help_opt_host)
$(t help_opt_net)
$(t help_opt_tls)
$(t help_opt_cert)
$(t help_opt_keyfile)
$(t help_opt_version)
$(t help_opt_lang)
$(t help_opt_help)

$(t help_no_opt)

$(t help_examples)
  bash install.sh --install --key mysecret --port 2088
  bash install.sh --install --key mysecret --tls 2 --cert /path/cert.pem --keyfile /path/key.pem --host relay.example
  bash install.sh -l en --status
  bash install.sh --version v1.2.3 --install --key mysecret
EOF
}

parse_args() {
    AUTO_MODE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--install)       AUTO_MODE="install" ;;
            -u|--upgrade)       AUTO_MODE="upgrade" ;;
            -c|--config)        AUTO_MODE="config" ;;
            -s|--status)        AUTO_MODE="status" ;;
            -q|--share)         AUTO_MODE="share" ;;
            --uninstall)        AUTO_MODE="uninstall" ;;
            -k|--key)           ARG_KEY="$2"; shift ;;
            -p|--port)          ARG_PORT="$2"; shift ;;
            --alpn)             ARG_ALPN="$2"; shift ;;
            --host)             ARG_HOST="$2"; shift ;;
            --spec)
                # Kept for automation compatibility; Nowhere 1.5 removed spec.
                log_warn "$(t warn_spec_removed)"
                if [[ $# -ge 2 && "$2" != -* ]]; then
                    shift
                fi
                ;;
            --net)              ARG_NET="$2"; shift ;;
            --tls)              ARG_TLS="$2"; shift ;;
            --cert)             ARG_CERT="$2"; shift ;;
            --keyfile)          ARG_KEYFILE="$2"; shift ;;
            -v|--version)       ARG_VERSION="$2"; shift ;;
            -l|--lang)
                ARG_LANG="$2"
                case "$ARG_LANG" in
                    en|zh|ru) set_language "$ARG_LANG" ;;
                    *)
                        log_error "$(t err_lang "$ARG_LANG")"
                        exit 1
                        ;;
                esac
                shift
                ;;
            -h|--help|help)
                set_language "${ARG_LANG:-zh}"
                show_help
                exit 0
                ;;
            *)
                log_error "$(t err_unknown_opt "$1")"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    if [[ -z "$AUTO_MODE" ]]; then
        AUTO_MODE="menu"
    fi
}

# ==================== Main ====================
main() {
    parse_args "$@"
    set_language "${ARG_LANG:-zh}"
    check_root
    detect_os
    detect_arch
    detect_libc_runtime
    check_dependencies

    case "$AUTO_MODE" in
        install)    auto_install_nowhere ;;
        upgrade)    upgrade_nowhere ;;
        config)     configure_nowhere ;;
        status)     show_status ;;
        share)      show_share_uri ;;
        uninstall)  uninstall_nowhere ;;
        menu)       run_menu ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
