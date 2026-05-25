# auditd Rules Testing Script by vbkrnk

<div align="center">

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)
![Platform](https://img.shields.io/badge/platform-CentOS%20%7C%20Oracle%20Linux%20%7C%20Ubuntu-lightgrey.svg)
![Version](https://img.shields.io/badge/version-2.0-orange.svg)

**Automated auditd rules validation tool.**  
Reads all active rules from the running system, triggers each one, and produces a structured TXT report with rule ↔ log pairs.

[English](#english) • [Русский](#русский)

</div>

---

## English

### The Problem

After writing dozens of auditd rules you need to verify that every single one actually works. Doing this manually means generating events yourself, then digging through audit.log to find the matching entry — for every rule. With a hundred rules that becomes a real pain.

### The Solution

This script does it automatically:

1. Reads all active rules from the running system via `auditctl -l`
2. Generates the appropriate OS event for each rule
3. Searches `audit.log` for the matching entry
4. Writes a structured `.txt` report — every rule next to its confirming log line

No hardcoded rule lists. The script tests **exactly what is loaded on your machine**.

### Supported Platforms

| Distribution | Versions |
|---|---|
| CentOS | 7, 8, 9 |
| Oracle Linux | 7, 8, 9 |
| Ubuntu | 18.04, 20.04, 22.04, 24.04 |

### Requirements

- Root privileges (`sudo`)
- `auditd` installed and running
- `auditctl` available in PATH
- `python3` — for network syscall and `sethostname` triggers (optional but recommended)
- `ausearch` — improves log search accuracy (optional)

### Installation

```bash
git clone https://github.com/vbkrnk/auditd-rules-tester.git
cd auditd-rules-tester
chmod +x auditd_rules_tester_v2_en.sh
```

### Usage

```bash
sudo ./auditd_rules_tester_v2_en.sh
```

Report is saved in the current directory:
```
audit_test_report_<hostname>_<YYYYMMDD_HHMMSS>.txt
```

### Report Format

```
================================================================================
  auditd Rules Testing Script by vbkrnk
  Host:    myserver
  Date:    2026-05-25 12:00:00
  OS:      Oracle Linux Server 8.9
  Rules:   182 (loaded from this host via auditctl -l)
================================================================================

--------------------------------------------------------------------------------
RULE:
  -a always,exit -F arch=b64 -S rename,unlink,unlinkat,renameat -F key=file_deletion

LOG (confirmation that the rule triggered):
  type=SYSCALL msg=audit(1748000000.123:4567): arch=c000003e syscall=82 ...
  key="file_deletion"

...

================================================================================
  SUMMARY
  Total rules tested:             182
  Confirmed (log entries found):  97
  Not applicable (no path/dir):   34
  NEVER rules (suppressed):       1
  No log entry (did not trigger): 50
================================================================================
```

### How It Works

| Rule type | How it's detected | Trigger action |
|---|---|---|
| `-w /file -p x -k key` | starts with `-w`, file | `stat` + `head` on the file |
| `-w /dir -p wa -k key` | starts with `-w`, directory | creates and removes a temp file |
| `-a always,exit -S execve` | `-S execve\|execveat` | `/bin/ls /tmp` |
| `-a always,exit -S kill` | `-S kill\|exit_group` | `kill -0 $$` |
| `-a always,exit -S connect -F a2=0x10` | IPv4 connect | Python3 TCP to `127.0.0.1:19753` |
| `-a always,exit -S connect -F a2=0x1C` | IPv6 connect | Python3 TCP to `[::1]:19753` |
| `-a always,exit -S sethostname` | sethostname syscall | Python3 `libc.sethostname()` (same name) |
| `-a always,exit -S rename,unlink,...` | file deletion syscalls | `mktemp` + `rm` |
| `-a always,exit -F path=... -F perm=x` | path filter | `stat` on that path |
| `-a never,...` | never action | marked as suppressed — no trigger |
| Path does not exist | file/dir check | marked as N/A for this OS |

### Key Parsing

The script handles both key formats produced by `auditctl -l`:

```bash
-w /usr/bin/sudo -p x -k sudo_log           # -k format
-a always,exit -S execve -F key=process_spawn  # -F key= format
```

Both are parsed correctly and used for log lookup.

### Safety Notes

- **`shutdown` / `reboot` / `halt` binaries** — triggered via `stat` only, never executed
- **`reboot` syscall** — no trigger generated (unsafe), existing log entries are checked
- **`never` rules** — not triggered, logged as intentionally suppressed
- **Missing binaries** (e.g. `zypper` on Ubuntu) — logged as N/A, not an error
- **Deduplication** — identical path+perm combinations are triggered only once

### License

MIT License. See [LICENSE](LICENSE).

---

## Русский

### Проблема

После написания десятков правил auditd нужно убедиться, что каждое из них реально работает. Делать это вручную — генерировать события, потом искать нужную запись в audit.log для каждого правила — долго и муторно. При сотне правил это превращается в настоящую боль.

### Решение

Скрипт делает всё автоматически:

1. Считывает все активные правила с работающей системы через `auditctl -l`
2. Генерирует подходящее событие ОС для каждого правила
3. Ищет соответствующую запись в `audit.log`
4. Записывает структурированный `.txt` отчёт — каждое правило рядом с подтверждающей строкой из лога

Никакого захардкоженного списка правил. Скрипт тестирует **именно то, что загружено на вашей машине**.

### Поддерживаемые платформы

| Дистрибутив | Версии |
|---|---|
| CentOS | 7, 8, 9 |
| Oracle Linux | 7, 8, 9 |
| Ubuntu | 18.04, 20.04, 22.04, 24.04 |

### Требования

- Права суперпользователя (`sudo`)
- Установлен и запущен `auditd`
- `auditctl` доступен в PATH
- `python3` — для сетевых syscall и `sethostname` (опционально, но рекомендуется)
- `ausearch` — улучшает точность поиска в логах (опционально)

### Установка

```bash
git clone https://github.com/vbkrnk/auditd-rules-tester.git
cd auditd-rules-tester
chmod +x auditd_rules_tester_v2_en.sh
```

### Запуск

```bash
sudo ./auditd_rules_tester_v2_en.sh
```

Отчёт сохраняется в текущей директории:
```
audit_test_report_<hostname>_<YYYYMMDD_HHMMSS>.txt
```

### Формат отчёта

```
--------------------------------------------------------------------------------
RULE:
  -w /usr/bin/sudo -p x -k sudo_log

LOG (confirmation that the rule triggered):
  type=SYSCALL msg=audit(1748000000.123:4567): arch=c000003e syscall=59 ...
  key="sudo_log"
```

### Важные замечания

- Бинари выключения (`shutdown`, `reboot`, `halt`) — триггер только через `stat`, реального запуска нет
- Syscall `reboot` — триггер не генерируется (небезопасно), скрипт проверяет имеющиеся записи в логе
- Правила `never` — не триггерятся, в отчёте отмечаются как намеренно подавленные
- Отсутствующие бинари (например `zypper` на Ubuntu) — отмечаются как N/A, это не ошибка
- Дедупликация — одинаковые пары path+perm триггерятся только один раз

### Лицензия

MIT License. См. [LICENSE](LICENSE).
