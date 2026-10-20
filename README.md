# ProCash

Русскоязычный сервис ресторанных QR-счетов на **Laravel 13 / PHP 8.4 / PostgreSQL 17**. Интерфейс использует Blade и обычные CSS/JS; Node.js и сборка frontend не требуются.

## Возможности

- Регистрация, вход, роли USER/ADMIN и отключение аккаунтов.
- Рестораны владельца, столы и PNG QR-коды с прежними URL.
- Публичный счёт, тестовый заказ, история заказов и платежей.
- Анкета Freedom Pay: компания → руководитель → адрес → банк → ресторан → проверка.
- Администрирование заявок: отправка, возврат на исправление, одобрение, отклонение.
- Транзакционная обработка повторных платежных запросов и защита доступа к чужим ресторанам.

Freedom Pay и получение заказов, как в предыдущей версии, работают в **mock-режиме**. Реального подключения банка, iiko или r-Keeper в проекте пока нет. Mock-оплата не списывает деньги. В production Compose оба mock-режима отключены по умолчанию; для приёма реальных платежей потребуется отдельная интеграция провайдера.

## Локальный запуск

Нужны PHP 8.4+ с `bcmath`, `gd`, `mbstring`, `pdo_pgsql`, `zip`, Composer 2 и PostgreSQL 17. Для тестов с SQLite также нужен `pdo_sqlite`. PHP можно запускать через Docker-обёртки `bin/php` и `bin/composer`, даже если на хосте PHP отсутствует.

С установленным PHP:

```bash
composer install
cp .env.example .env
php artisan key:generate
# Создайте БД procash, настройте DB_* в .env.
php artisan migrate
php artisan serve --host=0.0.0.0 --port=8080
```

Через Docker-обёртки на Linux:

```bash
# PostgreSQL должен быть доступен на DB_HOST из .env.
./bin/setup
./bin/php artisan serve --host=0.0.0.0 --port=8080
```

`bin/setup` собирает development-образ при отсутствии, устанавливает зависимости из `composer.lock`, создаёт `.env` только при отсутствии, генерирует ключ только при отсутствии и применяет миграции. Существующие ключи и база сохраняются. Обёртка использует host networking для локальной PostgreSQL и поддерживает системный HTTPS-прокси. Если сеть разрешает GitHub Git, но блокирует GitHub API архивов, используйте `COMPOSER_INSTALL_PREFERENCE=source ./bin/setup`.

Создание администратора (пароль вводится скрыто; встроенного аккаунта и общего пароля нет):

```bash
php artisan procash:admin admin@example.com
# С Docker: ./bin/php artisan procash:admin admin@example.com
```

Команда повышает существующего пользователя без изменения его пароля либо создаёт нового с паролем от 12 до 72 байт.

## Проверки

```bash
php artisan test
vendor/bin/pint --test
php artisan view:cache
curl --fail http://127.0.0.1:8080/actuator/health
curl --fail http://127.0.0.1:8080/api/v1/health
```

С Docker заменяйте `php` на `./bin/php`, `vendor/bin/pint` на `./bin/php vendor/bin/pint`. Тесты по умолчанию используют изолированную SQLite в памяти. Для PostgreSQL задайте отдельную тестовую БД через переменные процесса:

```bash
DB_CONNECTION=pgsql DB_HOST=127.0.0.1 DB_DATABASE=procash_laravel_test \
DB_USERNAME=procash_user DB_PASSWORD='' ./bin/php artisan test
```

**Никогда не направляйте тесты на рабочую базу:** `RefreshDatabase` пересоздаёт таблицы тестовой базы. CI проверяет SQLite и PostgreSQL. Health `/actuator/health` проверяет SQL-соединение; `/api/v1/health` возвращает состояние приложения. Старый демонстрационный `/api/v1/orders/current` сохраняет camelCase JSON и требует входа.

## Переход со Spring Boot

1. Сделайте проверенную резервную копию PostgreSQL и остановите старое приложение.
2. Сохраните прежние DB-параметры, создайте Laravel `.env` и один постоянный `APP_KEY`. Не меняйте этот ключ при каждом развёртывании.
3. Запустите `php artisan migrate --force`. Миграция принимает прежние таблицы, UUID и связи, добавляет `remember_token`, нормализует старые статусы заявок. Она не удаляет пользователей, рестораны, заказы, платежи и таблицу истории Flyway.
4. Пароли `password_hash` в форматах bcrypt и Spring `{bcrypt}$2a$...` поддерживаются. Пользователям нужно войти заново: старые Spring-сессии не переносятся.
5. Запустите Laravel и проверьте health, вход, ресторан, QR-счёт и историю платежей.

Миграция принятия схемы намеренно не имеет разрушающего `down()`. Для отката базы используйте резервную копию. Не запускайте `migrate:fresh` или `migrate:refresh` на существующей базе. При деплое через Actions копия базы создаётся и проверяется перед миграциями.

## Production Docker

```bash
docker build --target production -t procash:local .
# Настройте APP_KEY, POSTGRES_PASSWORD, APP_URL и прежние POSTGRES_DB/POSTGRES_USER в .env.
docker compose config --quiet
docker compose up -d db
docker compose run --rm app php artisan migrate --force
docker compose up -d app
```

`APP_KEY` и пароль базы задаются безопасно на сервере. Не коммитьте `.env`. Сохраняйте прежний Compose project name и том `procash_postgres_data`, чтобы использовать прежнюю PostgreSQL. `procash_storage` хранит файловые сессии и cache. HTTPS завершается внешним reverse proxy; в production включены secure cookies. Apache обслуживает только `public/`, порт приложения привязан к loopback сервера.

Reverse proxy должен передавать исходный `Host` и заголовки `X-Forwarded-Proto`, `X-Forwarded-Port`, `X-Forwarded-For`, а HTTP перенаправлять на HTTPS. Laravel доверяет этим заголовкам: доступ к порту приложения должен оставаться только у reverse proxy. При `APP_ENV=production` и `APP_URL=https://...` адреса форм, ссылки и редиректы всегда используют HTTPS, даже если прокси не передал протокол. Для локальной разработки HTTP сохраняется.

## Автодеплой через GitHub Actions

После `push` в `main` workflow **Deploy ProCash** выполняет тесты на SQLite и PostgreSQL, проверки сценария деплоя, сборку production-образа и развёртывание на VPS. Для повторного запуска выберите **Actions → Deploy ProCash → Run workflow → main**. Pull request запускает проверки без деплоя. Выполняющийся production-деплой не отменяется новым push.

Используются прежние GitHub Actions secrets:

| Secret | Значение |
| --- | --- |
| `VPS_HOST` | Адрес сервера |
| `VPS_USER` | Пользователь с доступом к Docker и каталогу приложения |
| `VPS_SSH_KEY` | Закрытый SSH-ключ этого пользователя |
| `VPS_KNOWN_HOSTS` | Проверенная запись SSH host key сервера; для нестандартного порта — `[host]:port` |

При необходимости задайте repository variables `VPS_PORT` (по умолчанию `22`) и `VPS_DEPLOY_PATH` (по умолчанию `/opt/procash`). Новый registry token добавлять не нужно: Actions передаёт свой `GITHUB_TOKEN` с `packages:read` через stdin для временного входа в GHCR. Временный Docker config удаляется после завершения скрипта; постоянный Docker login сервера сохраняется.

Перед первым запуском на сервере должны быть:

- Git-копия этого репозитория в `/opt/procash`, Docker с Compose v2.20+, `git`, `curl`, `flock`.
- Доступ пользователя деплоя к Docker, файлам репозитория и `.env`. Локальные изменения отслеживаемых файлов должны быть сохранены отдельно.
- Рабочий доступ Git к `origin`. Скрипт использует существующую настройку, в том числе ключ `~/.ssh/procash_deploy_git`, если он есть.
- Серверный `.env` с прежними `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`; при другом домене — `APP_URL`. Сохраняйте прежнее имя Compose project, включая `COMPOSE_PROJECT_NAME`, если оно настроено.
- Настроенный HTTPS reverse proxy к `127.0.0.1:8080`.

Загружайте в `main` весь перенос Laravel вместе с workflow: `composer.lock`, `deploy/`, `Dockerfile`, `compose.yaml`, код и шаблоны должны принадлежать одному коммиту. Одного изменения YAML для перехода со Spring недостаточно.

Скрипт [deploy/deploy.sh](deploy/deploy.sh) получает образ по digest и сверяет его метку с проверенным SHA коммита. Затем безопасно переключает Git на этот коммит, сохраняя `.env` и локальные неотслеживаемые файлы. Если `APP_KEY` отсутствует или пуст, [prepare-env.php](deploy/prepare-env.php) создаёт его один раз; существующий ключ не меняется. PHP и Composer на сервере устанавливать не требуется — служебные команды выполняются внутри образа.

Перед `artisan migrate --force` создаётся `pg_dump` в `.deploy/backups/` и проверяется через `pg_restore --list`. Незавершённые копии имеют суффикс `.partial`. После миграций запускается новый app-контейнер, проверяются его image ID, SQL health и страница входа, обновляется cache Blade. После успеха digest сохраняется в серверном `.env` как `PROCASH_IMAGE`; последующие ручные команды Compose используют тот же образ.

При ошибке миграции прежнее приложение продолжает работать. Если новый контейнер не прошёл проверку, скрипт возвращает прежний checkout и образ приложения. База автоматически не откатывается: сохранённая копия предназначена для отдельного восстановления при необходимости. Копии базы остаются на сервере, поэтому контролируйте доступное место в `.deploy/backups/`.

Самостоятельная проверка сценария деплоя:

```bash
python3 tests/deploy_workflow_test.py
```

Тесты используют временные Git-репозитории, настоящий PHP и подменённые Docker/HTTP-команды. Они проверяют успешный повторный деплой, сохранение ключа и локальных файлов, отказ при неверном образе и сценарии возврата при сбоях backup, миграций, health и HTTP. Production-сервер при тестировании не затрагивается.
