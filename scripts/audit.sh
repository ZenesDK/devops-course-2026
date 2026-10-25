#!/usr/bin/env bash
# audit.sh — аудит конфигурации сервера (v2)
# Запуск: ssh -t devops 'sudo bash ~/audit.sh; echo "код возврата: $?"'

if [ "$(id -u)" -ne 0 ]; then
  echo "Ошибка: запустите скрипт от root (sudo bash $0)" >&2
  exit 2
fi

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf '  [OK] %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf "  [FAIL] %s (ожидалось: '%s', получено: '%s')\n" "$1" "$2" "$3"
}

# check "<заголовок>" "<ожидаемое>" "<полученное>" — все аргументы строго в кавычках!
check() {
  if [ "$3" = "$2" ]; then ok "$1"; else fail "$1" "$2" "$3"; fi
}

echo "Аудит конфигурации: $(hostname -f 2>/dev/null || hostname), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
SSHD_T=$(sshd -T 2>/dev/null)
check "Вход от имени root запрещён" "no" \
  "$(awk 'tolower($1)=="permitrootlogin"{print tolower($2)}' <<<"$SSHD_T" | tail -n1)"
check "Парольная аутентификация отключена" "no" \
  "$(awk 'tolower($1)=="passwordauthentication"{print tolower($2)}' <<<"$SSHD_T" | tail -n1)"
SSH_PORT=$(awk 'tolower($1)=="port"{print $2}' <<<"$SSHD_T" | head -n1)
if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" -ne 22 ] 2>/dev/null; then
  ok "Порт SSH отличен от 22 (используется $SSH_PORT)"
else
  fail "Порт SSH отличен от 22" "не 22" "${SSH_PORT:-неизвестно}"
fi
check "MaxAuthTries равен 3" "3" \
  "$(awk 'tolower($1)=="maxauthtries"{print $2}' <<<"$SSHD_T" | tail -n1)"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(ufw status 2>/dev/null | awk '/^Status:/{print $2}')"
check "Политика входящего трафика deny" "deny" \
  "$(ufw status verbose 2>/dev/null | awk '/^Default:/{print tolower($2)}')"

echo "[3] Учётные записи"
awk -F: '$3 >= 1000 && $3 < 65534 {printf "      %s (uid=%s)\n", $1, $3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
nginx -t >/dev/null 2>&1
check "Конфигурация nginx корректна" "0" "$?"

CERT=$(nginx -T 2>/dev/null | awk '/ssl_certificate[ \t]/{gsub(/;/,"");print $2; exit}')
KEY=$(nginx -T 2>/dev/null | awk '/ssl_certificate_key/{gsub(/;/,"");print $2; exit}')
if [ -n "$CERT" ] && openssl x509 -checkend 2592000 -noout -in "$CERT" >/dev/null 2>&1; then
  ok "Сертификат действителен > 30 дней ($CERT)"
else
  fail "Сертификат действителен > 30 дней" "ok" "не найден или истекает"
fi
check "Нет файлов, доступных на запись всем" "0" \
  "$(find / -xdev -type f -perm -0002 2>/dev/null | wc -l)"
check "Права ключа TLS равны 600" "600" "$(stat -c %a "$KEY" 2>/dev/null)"

echo "[5] Контейнеризация"
check "Служба docker активна" "active" "$(systemctl is-active docker)"
DB_CTR=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'db|postgres' | head -n1)
check "Контейнер СУБД в состоянии healthy" "healthy" \
  "$(docker inspect -f '{{.State.Health.Status}}' "$DB_CTR" 2>/dev/null)"
BAD_PORTS=$(ss -tln | awk '$5 ~ /:(5000|5432)$/ && $5 !~ /127\.0\.0\.1$/ && $5 !~ /\[::1\]$/ {n++} END {print n+0}')
check "Порты 5000 и 5432 не прослушиваются вне 127.0.0.1" "0" "$BAD_PORTS"
check "Права файла /home/devops/app/.env равны 600" "600" "$(stat -c %a /home/devops/app/.env 2>/dev/null)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[ "$FAIL" -eq 0 ]