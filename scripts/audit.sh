#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK] $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')";
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: значение параметра port отлично от 22
port="$(sudo sshd -T | awk '/^port/{print $2}')"
check "Порт SSH отличен от 22" "не 22" "$([[ "$port" != "22" ]] && echo "не 22" || echo "22")"

# TODO 2: значение параметра maxauthtries равно 3
check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# TODO 3: политика по умолчанию для входящего трафика равна deny
check "Политика входящего трафика deny" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "      %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна"        "active" "$(systemctl is-active nginx)"
sudo nginx -t > /dev/null 2>&1 && nginx_ok="0" || nginx_ok="1"
check "Конфигурация nginx корректна" "0" "$nginx_ok"
days_left="$(openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend 2592000 && echo ok || echo expired)"
check "Сертификат действителен > 30 дней" "ok" "$days_left"
writable="$(find /var/www/devops-site -perm -o+w | wc -l)"
check "Нет файлов, доступных на запись всем" "0" "$writable"
keymode="$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
check "Права ключа TLS равны 600"    "600" "$keymode"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
