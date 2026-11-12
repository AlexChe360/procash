# Migration audit

Дата: 2026-11-12

Источник (только чтение): `/Users/alex/Documents/Development/rust/procash`.
Назначение: `/Users/alex/Documents/ChatGPT/procash_ruby/rails`.

## Границы проверки

Инвентаризация выполнена. Семантический аудит и перенос модулей продолжаются; список ниже не означает завершения переноса.

## Маршруты Axum

- `/admin`
- `/admin/logout`
- `/demo/dashboard`
- `/demo/requests`
- `/demo/requests/{id}`
- `/demo/merchants/new`
- `/demo/requests/{id}/review`
- `/demo/requests/{id}/decision/{action}`
- `/demo/requests/{id}/merchant`
- `/demo/requests/{id}/invitation`
- `/dashboard`
- `/dashboard/logout`
- `/dashboard/merchants/{id}`
- `/dashboard/merchants/{id}/outlets`
- `/dashboard/merchants/{id}/outlets/{outlet_id}`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/tables`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/tables/{table_id}/qr.svg`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/connections/{connection_id}/check`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/connections`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/connections/{connection_id}/setup`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/connections/{connection_id}/binding`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/tables`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/tables/{table_id}/link`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/tip-settings`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/activation/check`
- `/dashboard/merchants/{id}/outlets/{outlet_id}/pos/activation/enable`
- `/`
- `/health`
- `/admin/login`
- `/connect`
- `/connect/success`
- `/invite/{token}`
- `/invite/activate`
- `/invite/success`
- `/login`
- `/t/{token}`
- `/assets/procash-logo.png`
- `/assets/procash-phone-realistic.webp`

## Миграции SQLx

Сохраняются в исходном порядке вместе с down SQL, индексами, составными FK и триггерами. Применяются только к отдельной Rails БД.

- `20261029092311_create_merchants.up.sql`
- `20261029122754_create_users.up.sql`
- `20261030110605_create_connection_requests.up.sql`
- `20261030115125_create_user_sessions.up.sql`
- `20261030143208_create_email_outbox.up.sql`
- `20261030152048_create_merchant_memberships.up.sql`
- `20261030152427_link_connection_requests_to_merchants.up.sql`
- `20261031090636_create_merchant_invitations.up.sql`
- `20261031091156_create_merchant_invitation_outbox.up.sql`
- `20261031101554_create_merchant_outlets.up.sql`
- `20261031105638_create_outlet_tables.up.sql`
- `20261031161847_create_outlet_iiko_settings.up.sql`
- `20261101111018_create_multi_tenant_iiko_connections.up.sql`
- `20261101171944_unique_iiko_table_mapping.up.sql`
- `20261104093318_create_outlet_tip_settings.up.sql`
- `20261111102418_iiko_activation_check_result.up.sql`
- `20261111105000_invalidate_iiko_activation_checks.up.sql`
- `20261111105250_invalidate_iiko_check_on_table_change.up.sql`
- `20261111110546_iiko_config_revision.up.sql`
- `20261111112321_invalidate_iiko_check_on_connection_change.up.sql`
- `20261111124118_disable_iiko_on_config_change.up.sql`

## Таблицы

- `merchants`
- `users`
- `connection_requests`
- `user_sessions`
- `email_outbox`
- `merchant_memberships`
- `merchant_invitations`
- `merchant_invitation_outbox`
- `merchant_outlets`
- `outlet_tables`
- `outlet_iiko_settings`
- `iiko_connections`
- `outlet_tip_settings`
- `outlet_iiko_activation_checks`

## Матрица Rust → Rails

| Rust | Rails / область | Статус |
| --- | --- | --- |
| `src/auth/bootstrap.rs` | модели User, UserSession; сервисы Auth | IN_PROGRESS |
| `src/auth/credentials.rs` | модели User, UserSession; сервисы Auth | IN_PROGRESS |
| `src/auth/mod.rs` | модели User, UserSession; сервисы Auth | IN_PROGRESS |
| `src/auth/password.rs` | модели User, UserSession; сервисы Auth | IN_PROGRESS |
| `src/auth/sessions.rs` | модели User, UserSession; сервисы Auth | IN_PROGRESS |
| `src/users/mod.rs` | User | IN_PROGRESS |
| `src/users/repository.rs` | User | IN_PROGRESS |
| `src/connection_requests/mod.rs` | ConnectionRequest; onboarding | IN_PROGRESS |
| `src/connection_requests/repository.rs` | ConnectionRequest; onboarding | IN_PROGRESS |
| `src/merchants/invitations.rs` | Merchant, MerchantMembership, MerchantInvitation | IN_PROGRESS |
| `src/merchants/mod.rs` | Merchant, MerchantMembership, MerchantInvitation | IN_PROGRESS |
| `src/merchants/repository.rs` | Merchant, MerchantMembership, MerchantInvitation | IN_PROGRESS |
| `src/merchant_outlets/mod.rs` | MerchantOutlet, OutletTable | IN_PROGRESS |
| `src/merchant_outlets/repository.rs` | MerchantOutlet, OutletTable | IN_PROGRESS |
| `src/pos/adapters/iiko/activation.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/adapter.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/bill.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/client.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/connection_check.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/connection_repository.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/connections.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/crypto.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/factory.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/items.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/mapper.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/mod.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/orders.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/sections.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/settings.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/setup.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/table_binding.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/iiko/table_catalog.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/adapters/mod.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/bill_service.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/connection_status.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/mod.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/models.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/ports.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/qr_repository.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/qr_service.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/pos/resolver.rs` | Pos; адаптер iiko | IN_PROGRESS |
| `src/web/admin.rs` | controllers/views | IN_PROGRESS |
| `src/web/connect.rs` | controllers/views | IN_PROGRESS |
| `src/web/errors.rs` | controllers/views | IN_PROGRESS |
| `src/web/handlers.rs` | controllers/views | IN_PROGRESS |
| `src/web/invite.rs` | controllers/views | IN_PROGRESS |
| `src/web/merchant_portal.rs` | controllers/views | IN_PROGRESS |
| `src/web/mod.rs` | controllers/views | IN_PROGRESS |
| `src/web/table_public.rs` | controllers/views | IN_PROGRESS |
| `src/mail/invitation_worker.rs` | Action Mailer; outbox jobs | IN_PROGRESS |
| `src/mail/mod.rs` | Action Mailer; outbox jobs | IN_PROGRESS |
| `src/mail/worker.rs` | Action Mailer; outbox jobs | IN_PROGRESS |

## Шаблоны

- `templates/app/base.html`
- `templates/app/dashboard.html`
- `templates/app/merchant_new.html`
- `templates/app/request_detail.html`
- `templates/app/requests.html`
- `templates/auth/admin_login.html`
- `templates/connect/form.html`
- `templates/connect/success.html`
- `templates/emails/merchant_invitation.html`
- `templates/emails/new_request.html`
- `templates/errors/error.html`
- `templates/index.html`
- `templates/invite/activate.html`
- `templates/invite/success.html`
- `templates/merchant/company.html`
- `templates/merchant/dashboard.html`
- `templates/merchant/iiko_setup.html`
- `templates/merchant/iiko_table_mapping.html`
- `templates/merchant/layouts/workspace.html`
- `templates/merchant/login.html`
- `templates/merchant/outlet_detail.html`
- `templates/merchant/outlets.html`
- `templates/merchant/partials/sidebar.html`
- `templates/public/table.html`

## Тестовые сценарии Rust

- `src/auth/password.rs::should_hash_and_verify_password`
- `src/auth/password.rs::should_generate_unique_hashes`
- `src/auth/sessions.rs::should_generate_unique_tokens`
- `src/auth/sessions.rs::should_hash_session_token`
- `src/auth/sessions.rs::should_validate_token_format`
- `src/merchants/invitations.rs::same_invitation_generates_same_token`
- `src/merchants/invitations.rs::different_invitations_have_different_tokens`
- `src/pos/adapters/iiko/activation.rs::valid_integration_can_be_activated`
- `src/pos/adapters/iiko/activation.rs::unverified_connection_is_rejected`
- `src/pos/adapters/iiko/activation.rs::foreign_connection_is_rejected`
- `src/pos/adapters/iiko/activation.rs::missing_terminal_group_is_rejected`
- `src/pos/adapters/iiko/activation.rs::unavailable_organization_is_rejected`
- `src/pos/adapters/iiko/activation.rs::unmapped_tables_are_rejected`
- `src/pos/adapters/iiko/activation.rs::validates_live_iiko_binding`
- `src/pos/adapters/iiko/bill.rs::no_order_returns_empty_state`
- `src/pos/adapters/iiko/bill.rs::prepares_bill_with_partial_payment`
- `src/pos/adapters/iiko/bill.rs::missing_processed_payments_is_not_zero`
- `src/pos/adapters/iiko/bill.rs::rejects_order_from_another_table`
- `src/pos/adapters/iiko/bill.rs::waits_for_in_progress_order`
- `src/pos/adapters/iiko/bill.rs::multiple_orders_are_not_selected_automatically`
- `src/pos/adapters/iiko/bill.rs::detects_payment_statuses`
- `src/pos/adapters/iiko/bill.rs::closed_order_is_not_available_for_payment`
- `src/pos/adapters/iiko/bill.rs::accepts_current_partial_payment_balance`
- `src/pos/adapters/iiko/bill.rs::rejects_stale_payment_amount`
- `src/pos/adapters/iiko/bill.rs::rejects_changed_order`
- `src/pos/adapters/iiko/bill.rs::rejects_unknown_payment_balance`
- `src/pos/adapters/iiko/bill.rs::rejects_fully_paid_bill`
- `src/pos/adapters/iiko/bill.rs::rejects_closed_bill`
- `src/pos/adapters/iiko/client.rs::serializes_v2_credentials`
- `src/pos/adapters/iiko/client.rs::deserializes_organizations`
- `src/pos/adapters/iiko/client.rs::serializes_terminal_groups_request`
- `src/pos/adapters/iiko/client.rs::deserializes_terminal_groups_response`
- `src/pos/adapters/iiko/connection_check.rs::accepts_organizations_from_iiko`
- `src/pos/adapters/iiko/connection_check.rs::rejects_empty_organizations`
- `src/pos/adapters/iiko/connection_check.rs::handles_rejected_credentials`
- `src/pos/adapters/iiko/connections.rs::accepts_valid_connection_data`
- `src/pos/adapters/iiko/connections.rs::rejects_invalid_name`
- `src/pos/adapters/iiko/connections.rs::rejects_empty_api_key`
- `src/pos/adapters/iiko/connections.rs::rejects_oversized_api_key`
- `src/pos/adapters/iiko/crypto.rs::encrypts_and_decrypts_api_key`
- `src/pos/adapters/iiko/crypto.rs::produces_different_ciphertexts`
- `src/pos/adapters/iiko/crypto.rs::rejects_other_connection`
- `src/pos/adapters/iiko/crypto.rs::rejects_tampered_ciphertext`
- `src/pos/adapters/iiko/crypto.rs::rejects_unsupported_key_version`
- `src/pos/adapters/iiko/factory.rs::accepts_valid_binding`
- `src/pos/adapters/iiko/factory.rs::rejects_missing_organization`
- `src/pos/adapters/iiko/factory.rs::rejects_nil_organization`
- `src/pos/adapters/iiko/factory.rs::rejects_missing_terminal_group`
- `src/pos/adapters/iiko/factory.rs::rejects_nil_terminal_group`
- `src/pos/adapters/iiko/items.rs::parses_product_with_modifier`
- `src/pos/adapters/iiko/items.rs::skips_deleted_items`
- `src/pos/adapters/iiko/items.rs::rejects_unsupported_item_type`
- `src/pos/adapters/iiko/mapper.rs::maps_partial_payment`
- `src/pos/adapters/iiko/mapper.rs::preserves_unknown_amounts`
- `src/pos/adapters/iiko/mapper.rs::maps_no_order_state`
- `src/pos/adapters/iiko/mapper.rs::maps_syncing_state`
- `src/pos/adapters/iiko/mapper.rs::preserves_multiple_orders`
- `src/pos/adapters/iiko/mapper.rs::preserves_unavailable_reason`
- `src/pos/adapters/iiko/mapper.rs::maps_closed_state`
- `src/pos/adapters/iiko/orders.rs::serializes_orders_by_table_request`
- `src/pos/adapters/iiko/orders.rs::deserializes_open_order_without_losing_precision`
- `src/pos/adapters/iiko/orders.rs::handles_empty_and_pending_orders`
- `src/pos/adapters/iiko/orders.rs::handles_null_order_arrays`
- `src/pos/adapters/iiko/sections.rs::serializes_restaurant_sections_request`
- `src/pos/adapters/iiko/sections.rs::deserializes_restaurant_sections`
- `src/pos/adapters/iiko/setup.rs::draft_is_not_eligible_for_setup`
- `src/pos/adapters/iiko/setup.rs::selects_only_matching_organization`
- `src/pos/adapters/iiko/setup.rs::ignores_invalid_organization_ids`
- `src/pos/adapters/iiko/setup.rs::filters_terminal_groups_by_organization`
- `src/pos/adapters/iiko/table_catalog.rs::returns_tables_from_selected_terminal_group`
- `src/pos/adapters/iiko/table_catalog.rs::ignores_deleted_tables`
- `src/pos/adapters/iiko/table_catalog.rs::rejects_duplicate_table_ids`
- `src/pos/adapters/iiko/table_catalog.rs::does_not_mix_terminal_groups`
- `src/pos/bill_service.rs::loads_bill_from_matching_adapter`
- `src/pos/bill_service.rs::rejects_wrong_pos_adapter`
- `src/pos/bill_service.rs::rejects_missing_table_id`
- `src/pos/connection_status.rs::connection_not_configured`
- `src/pos/connection_status.rs::connection_configured`
- `src/pos/connection_status.rs::connection_verified`
- `src/pos/connection_status.rs::connection_enabled`
- `src/pos/connection_status.rs::connection_disabled`
- `src/pos/connection_status.rs::enabled_without_verification_is_inconsistent`
- `src/pos/connection_status.rs::missing_connection_cannot_be_enabled`
- `src/pos/models.rs::parses_iiko`
- `src/pos/models.rs::parses_rkeeper`
- `src/pos/models.rs::rejects_unknown_pos`
- `src/pos/qr_repository.rs::detects_iiko`
- `src/pos/qr_repository.rs::detects_rkeeper`
- `src/pos/qr_repository.rs::rejects_unknown_pos`
- `src/pos/qr_repository.rs::creates_pos_context`
- `src/pos/qr_repository.rs::rejects_unbound_table`
- `src/pos/qr_service.rs::accepts_valid_iiko_table_id`
- `src/pos/qr_service.rs::rejects_invalid_iiko_table_id`
- `src/pos/qr_service.rs::rejects_nil_iiko_table_id`
- `src/pos/qr_service.rs::loads_real_qr_bill_through_pos_layer`
- `src/pos/resolver.rs::resolves_iiko`
- `src/pos/resolver.rs::rejects_missing_pos_configuration`
- `src/pos/resolver.rs::rejects_unknown_pos`
- `src/pos/resolver.rs::rejects_unavailable_rkeeper_adapter`
- `src/pos/resolver.rs::rejects_duplicate_adapters`
- `src/qr.rs::should_escape_table_name`
- `src/qr.rs::should_generate_branded_qr`
- `src/tip_settings.rs::tips_are_disabled_by_default`
- `src/tip_settings.rs::calculates_ten_percent_tip`
- `src/tip_settings.rs::zero_percent_is_always_allowed`
- `src/tip_settings.rs::rejects_disabled_tips`
- `src/tip_settings.rs::rejects_unconfigured_percentage`
- `src/tip_settings.rs::rounds_fractional_tips_to_two_places`
- `src/tip_settings.rs::rejects_negative_amount`
- `src/tip_settings.rs::calculates_custom_tip`
- `src/tip_settings.rs::accepts_comma_decimal_separator`
- `src/tip_settings.rs::rejects_custom_tip_when_disabled`
- `src/tip_settings.rs::rejects_excessive_custom_tip`
- `src/tip_settings.rs::rejects_excessive_precision`
- `src/web/table_public.rs::no_order_displays_notice`
- `src/web/table_public.rs::multiple_orders_require_assistance`
- `src/web/table_public.rs::preview_preserves_unknown_payment_balance`
- `src/web/table_public.rs::formats_money_in_kzt`
- `src/web/table_public.rs::formats_item_quantity`
- `src/web/table_public.rs::fully_paid_bill_displays_paid_notice`
- `src/web/table_public.rs::partial_payment_preserves_balance_and_waiter`
- `src/web/table_public.rs::zero_total_bill_has_no_payment_preview`

## Подтвержденные инварианты

- Авторизация: Argon2id; активный пользователь с подтвержденным email; admin и merchant разделены.
- Merchant: требуется активное membership; изменения точек и столов разрешены owner/manager.
- Сессии: случайный hex-токен 32 байта, SHA-256 в BYTEA, срок 12 часов, отзыв.
- Onboarding: new → in_review → approved/rejected; создание компании только после approved.
- Приглашения: HMAC-SHA256 над префиксом и 16 байтами UUID; 48 часов; одноразовая активация в транзакции.
- iiko: AES-256-GCM, nonce 12 байт, тег в конце ciphertext; AAD включает connection UUID.
- Конфигурация iiko: connection → settings → outlet — порядок блокировок; revision и DB-триггеры инвалидируют проверку и активацию.
- Счёт: неизвестный остаток сохраняется как nil; несколько заказов не выбираются автоматически; Closed отдельное состояние.
- Чаевые: BigDecimal, округление half-up до двух знаков, произвольные чаевые не выше остатка.
- Эквайринг отсутствует; r_keeper распознаётся, но адаптер недоступен.

## Проверки, требующие завершения

- Полный перенос handlers, POS setup/activation и конкурентных тестов.
- Сравнение UI с публичным сайтом и скриншотом админок.
- Внешний тест iiko только по явно разрешённой тестовой конфигурации.
- Почтовые outbox: SKIP LOCKED, 8 попыток, lease 5 минут для заявок / 2 минуты для приглашений, квадратичная задержка до 60 минут.

Секреты .env и production-данные не копировались. Исходный Rust-проект не запускался и не изменялся.

## Уточнение публичного дизайна (2026-11-12)

Опубликованная главная отличается от локального Rust templates/index.html.
По прямому указанию пользователя для публичной главной перенесены опубликованные
HTML и /assets/home.css с procash.kz; бизнес-логика по-прежнему берётся из Rust.
Телефон на опубликованной странице — встроенный SVG. Юридические документы
ссылаются на действующие публичные PDF procash.kz.
