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
