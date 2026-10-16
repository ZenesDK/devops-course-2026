#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"
DRY_RUN=0

# 1. Разбор аргумента --dry-run
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

# 2. Проверка требования 4: наличие index.html
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "ОШИБКА: ${LOCAL_DIR}index.html отсутствует" >&2
    exit 1
fi

# 3. Проверка требования 5: отсутствие незафиксированных изменений
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ОШИБКА: в репозитории есть незафиксированные изменения" >&2
    exit 1
fi

# 4. Синхронизация
if [[ "$DRY_RUN" -eq 1 ]]; then
    rsync -avz --delete --chmod=D755,F644 --dry-run \
        -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
        "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"
    exit 0
fi

rsync -avz --delete --chmod=D755,F644 \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 5. Проверка доступности (требование 6)
if ! curl -f -s --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}"; then
    echo "ОШИБКА: ресурс ${SITE_URL} недоступен" >&2
    exit 1
fi

# Требование 7: короткий хеш доставленного коммита
echo "Деплой выполнен: $(git rev-parse --short HEAD)"
exit 0
