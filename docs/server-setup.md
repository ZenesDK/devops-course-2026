# Конфигурация виртуальной машины devops-vm

> Инструкция по восстановлению: VirtualBox → выбрать devops-vm → Снимки →
> правый клик по «01-clean-install» → Восстановить → Запустить.
> Далее выполнять блоки по порядку. Все команды — от пользователя student (вход в консоль VM).

## 1. Параметры машины
- ОЗУ: 2048 МБ; CPU: 2 ядра; диск: 25 ГБ (динамический VDI)
- Гостевая ОС: Ubuntu Server 24.04 LTS, имя узла: devops-vm

## 2. Сетевые интерфейсы
| Адаптер | Тип | Адрес | Назначение |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15 | доступ в Интернет, apt |
| enp0s8 | Host-only (vboxnet0) | 192.168.56.101 | доступ с хоста (SSH, веб в ПР №6) |

## 3. Правило проброса портов (VirtualBox, Адаптер 1, NAT)
- Имя: ssh; TCP; адрес хоста 127.0.0.1; порт хоста **2222**; адрес гостя: пусто; порт гостя **2222**

## 4. Учётные записи
- student (uid=1000): администратор установки, sudo, парольная аутентификация
- devops (uid=1001): рабочая учётная запись, группа sudo, вход **только по ключу**
  - восстановление пользователя и ключа:
    ```bash
    sudo adduser devops                                # задать пароль
    sudo usermod -aG sudo devops
    ```
  - публичный ключ: строка из файла `~/.ssh/devops_vm.pub` **хостовой** системы добавить в
    `/home/devops/.ssh/authorized_keys` на VM:
    ```bash
    sudo mkdir -p /home/devops/.ssh
    sudo sh -c 'cat >> /home/devops/.ssh/authorized_keys' < путь/к/devops_vm.pub
    sudo chown -R devops:devops /home/devops/.ssh
    sudo chmod 700 /home/devops/.ssh && sudo chmod 600 /home/devops/.ssh/authorized_keys
    ```

## 5. Служба SSH
Файл конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf` (создаётся командой ниже)

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'CONF'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
CONF
# закомментировать конфликтующую строку cloud-init, если присутствует:
sudo grep -r "PasswordAuthentication" /etc/ssh/sshd_config.d/ || true
sudo sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null || true
# переключение с socket-активации:
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
# проверка:
sudo sshd -t && sudo ss -tlnp | grep sshd   # ожидается 0.0.0.0:2222
```

## 6. Правила межсетевого экрана
Политики: входящие — deny, исходящие — allow. Управляющий порт — rate-limited.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw status verbose
```

## 7. Снимки состояния
| Снимок | Момент создания |
|---|---|
| 01-clean-install | после установки ОС и обновлений, до настройки |
| 02-keys-configured | после создания пользователя devops и ключевой аутентификации |
| 03-ssh-hardened | после hardening SSH (порт 2222, ключ-only, запрет root) |

## 8. Проверка восстановления
```bash
ssh devops                    # вход без пароля
sudo sshd -T | grep -E "port|permitrootlogin|passwordauthentication|maxauthtries"
sudo ufw status verbose
hostname -f                   # devops-vm.devops.local
```

## 8. Веб-сервер
- Пакет: nginx (apt)
- Конфигурация ресурса: /etc/nginx/sites-available/devops-site (симлинк в /etc/nginx/sites-enabled/);
  стандартный ресурс default отключён (симлинк удалён)
- Два server-блока: блок 80 — return 301 https://$host$request_uri; блок 443 ssl — TLSv1.2/1.3
- Каталог ресурса: /var/www/devops-site, владелец devops:devops, права 755/644 (модель «владелец пишет, веб-сервер читает»)
- Сертификат: /etc/ssl/certs/devops.crt (644, root:root); ключ: /etc/ssl/private/devops.key (600, root:root)
- Команда формирования (срок 365 дней):
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"

## 8. Веб-сервер
- Пакет: nginx (apt)
- Конфигурация ресурса: /etc/nginx/sites-available/devops-site (симлинк в /etc/nginx/sites-enabled/);
  стандартный ресурс default отключён (симлинк удалён)
- Два server-блока: блок 80 — return 301 https://$host$request_uri; блок 443 ssl — TLSv1.2/1.3
- Каталог ресурса: /var/www/devops-site, владелец devops:devops, права 755/644 (модель «владелец пишет, веб-сервер читает»)
- Сертификат: /etc/ssl/certs/devops.crt (644, root:root); ключ: /etc/ssl/private/devops.key (600, root:root)
- Команда формирования (срок 365 дней):
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"

## 9. Контейнеризация

### 9.1 Docker Engine
Docker Engine установлен из официального репозитория Docker по инструкции
для Ubuntu (docs.docker.com/engine/install/ubuntu/); пакет docker.io из
репозитория дистрибутива не использовался.
Версии: Docker Engine 29.9.1, Compose v5.6.0 (плагин).
Проверка: docker version — присутствует раздел Server; docker compose version.

### 9.2 Группа docker
Пользователь devops включён в группу docker:

    sudo usermod -aG docker devops

и запускает контейнеры без sudo (docker run --rm hello-world).
Внимание: членство в группе docker эквивалентно доступу уровня root
(возможен запуск контейнера с монтированием корня хоста на запись),
поэтому в группу включена только учётная запись, имеющая право sudo.

### 9.3 Проект приложения
Исходный код хранится в репозитории devops-course-2026 на хостовой системе,
каталог app/ (ветка feature/docker), доставка на сервер:

    rsync -avz --delete --exclude=.env app/ devops:app/

Рабочий каталог на сервере: /home/devops/app. Состав каталога: app.py,
requirements.txt, Dockerfile, .dockerignore, .env.example,
docker-compose.yml. Файл .env создаётся только на сервере из шаблона
.env.example.

### 9.4 Переменные окружения
/home/devops/app/.env содержит: POSTGRES_DB, POSTGRES_USER,
POSTGRES_PASSWORD (случайный, openssl rand -hex 16), DB_HOST=db.
Права доступа 600 (rw-------, владелец devops). В репозиторий файл не
включается: имя .env добавлено в .gitignore, при доставке исключается
параметром --exclude=.env; копирование файла на хостовую систему запрещено.

### 9.5 Публикуемые порты и сети
Публикуется только порт сервиса app: "127.0.0.1:5000:5000" — привязка к
loopback-адресу; доступ извне осуществляется исключительно через обратный
прокси Nginx (HTTPS, порт 443, location /app/). Порт СУБД 5432 не
публикуется: приложение обращается к сервису db по имени через
изолированную сеть проекта backend, создаваемую Compose.
Проверка:

    sudo ss -tlnp | grep -E ':(5000|5432)\b'

— единственный прослушиваемый сокет 127.0.0.1:5000; порт 5432 на сервере
не прослушивается.

### 9.6 Именованные тома
Данные СУБД хранятся в именованном томе db_data, смонтированном в
/var/lib/postgresql/data контейнера db. Том управляется Docker независимо
от жизненного цикла контейнеров: docker compose down сохраняет том
(счётчик Visits продолжается после пересоздания контейнеров),
docker compose down -v удаляет том вместе с данными.
Проверка: docker volume ls.

### 9.7 Обратный прокси-сервер
/etc/nginx/sites-available/devops-site, HTTPS-блок (server 443 ssl).
Статический ресурс (location /) сохранён; для приложения добавлено:

    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

Завершающий символ "/" в значении proxy_pass заменяет префикс /app/ на "/":
запрос /app/health передаётся приложению как /health.
Проверка: curl --cacert ~/devops.crt https://devops.local/app/
