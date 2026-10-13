# Мониторинг Ubuntu через HTTPS

Домашнее задание №2 по системному администрированию: контейнеризация, RAID/LVM и сервис за reverse proxy с TLS.

Автор: Доронин Никита Сергеевич.
Работа выполнена на учебной машине sysadmin-host: Ubuntu 22.04.5 LTS, aarch64.

Основой служит скрипт варианта Б из ДЗ №1. Завершённая версия первого задания сохранена [меткой hw1](https://github.com/nikndip/my-sysadmin-scripts/tree/hw1).

## Как работает сервис

Bash-скрипт каждые 5 секунд дописывает в monitor.log временную метку и результаты free -h, df -h и uptime. Между измерениями выполняется пауза; фактическое расстояние между метками включает время выполнения команд.

В контейнере одновременно работают скрипт мониторинга и HTTP-сервер Python. Сервер отдаёт файлы каталога /app, включая /app/monitor.log.

Путь запроса:

```text
HTTPS :443 → Nginx → 127.0.0.1:8080 → контейнер my-app → monitor.log
```

HTTP-запросы на порт 80 перенаправляются на HTTPS кодом 301.
Контейнер запускается службой my-app.service с зависимостью от docker.service.

## Файлы проекта

| Файл | Назначение |
|---|---|
| script.sh | Сбор показателей и обработка ошибок |
| Dockerfile | Образ Ubuntu с procps, Python и скриптом |
| docker-compose.yml | Создание контейнера и публикация порта 8080 на localhost |
| nginx/my-app.conf | Reverse proxy, HTTPS и HTTP-редирект |
| systemd/my-app.service | Управление контейнером и автозапуск |
| sample_output.txt | Три реальных блока мониторинга из контейнера |
| .gitignore | Исключение рабочего monitor.log из Git |

## Первичное развёртывание сервиса

Команды предназначены для новой учебной Ubuntu-машины с установленными Git, Docker, Docker Compose, Nginx, OpenSSL и curl, а также доступом к sudo.

Получение проекта и сборка:

```bash
git clone https://github.com/nikndip/my-sysadmin-scripts.git
cd my-sysadmin-scripts
docker build -t my-script .
docker compose config --quiet
docker compose up -d
```

Создание учебного самоподписанного сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/my-app.key \
  -out /etc/ssl/certs/my-app.crt \
  -subj "/CN=my-app.local"
```

Подключение Nginx:

```bash
sudo cp nginx/my-app.conf /etc/nginx/sites-available/my-app
sudo ln -s /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/my-app
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Передача управления контейнером службе systemd:

```bash
docker compose stop app
sudo cp systemd/my-app.service /etc/systemd/system/my-app.service
sudo systemctl daemon-reload
sudo systemctl enable --now my-app
```

Контейнер должен быть создан через Compose до первого запуска службы.
Сертификат и приватный ключ создаются на хосте в системных каталогах.

## Проверка и управление

После запуска службе нужно дать несколько секунд на запуск приложения.

```bash
systemctl is-enabled my-app
sudo systemctl status my-app --no-pager -l
curl -I http://127.0.0.1:8080/monitor.log
curl -I http://192.168.252.2/monitor.log
curl -kI https://192.168.252.2/monitor.log
```

Адрес 192.168.252.2 относится к моей учебной VM; на другой машине используется её фактический IPv4.

Ожидаемые результаты: enabled, active (running), код 200 от внутреннего HTTP-сервера, HTTP-редирект 301 и HTTPS-ответ 200. Флаг -k используется при проверке самоподписанного сертификата.

Для дальнейшего управления:

```bash
sudo systemctl start my-app
sudo systemctl stop my-app
```

Просмотр логов:

```bash
sudo journalctl -u my-app -n 15 --no-pager
sudo tail -n 5 /var/log/nginx/access.log
```

Журнал службы содержит сообщения запуска и запросы к Python-серверу. Access.log Nginx позволяет сопоставить внешний запрос, его время и HTTP-код.

## Учебное хранилище

Для лабораторной части созданы три файла по 512 МиБ в /mnt/raid-lab и подключены как loop-устройства.

| Хранилище | Основа | Результат |
|---|---|---|
| RAID 1 | disk1.img и disk2.img; при выполнении loop3 и loop4 | /dev/md0, смонтирован в /mnt/raid |
| LVM | disk3.img; при выполнении loop5 | vg_data, том lv_logs на 200 МиБ, смонтирован в /mnt/logs |

RAID 1 проверен в состоянии [2/2] [UU]: оба участника активны.
LVM-группа имеет размер 508 МиБ, из которых 200 МиБ выделены lv_logs и 308 МиБ остаются свободными.
Оба хранилища отформатированы в ext4; размер файловой системы в df меньше выделенного объёма из-за служебных структур.

Команды проверки:

```bash
cat /proc/mdstat
df -h /mnt/raid
sudo pvs
sudo vgs
sudo lvs
df -h /mnt/logs
```

RAID/LVM демонстрируются как отдельная лабораторная часть. Рабочий monitor.log находится в /app внутри контейнера.

После перезагрузки VM подключения loop-устройств и монтирование учебных томов нужно восстановить отдельно. Файлы-диски сохраняются; команды первоначального создания файловых систем не являются командами восстановления.

## Подтверждённые результаты

- Docker-образ собран, контейнер запускается через Compose.
- Скрипт создаёт повторяющиеся блоки мониторинга внутри контейнера.
- RAID 1 и LVM-том созданы и смонтированы.
- nginx -t завершился успешно.
- Внутренний HTTP-сервер возвращает 200.
- HTTP перенаправляется на HTTPS кодом 301.
- HTTPS возвращает 200 через Nginx.
- Служба my-app активна, автозапуск включён.
- Тестовый запрос HEAD /monitor.log найден в журнале службы и access.log Nginx.

Скриншоты проверок сохранены отдельно для сдачи в ЛМС.
