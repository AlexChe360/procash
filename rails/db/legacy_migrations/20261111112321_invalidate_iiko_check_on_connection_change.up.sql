
CREATE FUNCTION invalidate_iiko_check_on_connection_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
DECLARE
    affected_outlet_id UUID;
BEGIN
    -- Проверяем, изменились ли значимые данные.
    IF OLD.status IS NOT DISTINCT FROM NEW.status
        AND OLD.api_key_ciphertext IS NOT DISTINCT FROM NEW.api_key_ciphertext
        AND OLD.api_key_nonce IS NOT DISTINCT FROM NEW.api_key_nonce
        AND OLD.encryption_key_version IS NOT DISTINCT FROM NEW.encryption_key_version
        AND (OLD.last_verified_at IS NULL) =
            (NEW.last_verified_at IS NULL)
    THEN
        RETURN NEW;
    END IF;

    -- Находим все торговые точки этого подключения.
    -- Обрабатываем их в фиксированном порядке.
    FOR affected_outlet_id IN
        SELECT s.outlet_id
        FROM outlet_iiko_settings s
        WHERE s.connection_id = NEW.id
          AND s.merchant_id = NEW.merchant_id
        ORDER BY s.outlet_id
        LOOP

            -- Увеличиваем версию конфигурации.
            UPDATE merchant_outlets
            SET iiko_config_revision = iiko_config_revision + 1
            WHERE id = affected_outlet_id
              AND merchant_id = NEW.merchant_id
              AND pos_system = 'iiko';

            -- Удаляем предыдущий результат проверки.
            DELETE FROM outlet_iiko_activation_checks
            WHERE outlet_id = affected_outlet_id;

        END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_invalidate_iiko_check_on_connection_change
    AFTER UPDATE OF
        status,
        api_key_ciphertext,
        api_key_nonce,
        encryption_key_version,
        last_verified_at
    ON iiko_connections
    FOR EACH ROW
EXECUTE FUNCTION invalidate_iiko_check_on_connection_change();