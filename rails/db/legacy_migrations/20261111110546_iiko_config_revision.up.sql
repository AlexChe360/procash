
-- Добавляем версию конфигурации для каждой торговой точки.
ALTER TABLE merchant_outlets
    ADD COLUMN iiko_config_revision BIGINT NOT NULL DEFAULT 0;

-- Изменение подключения, организации или терминальной группы.
CREATE OR REPLACE FUNCTION invalidate_iiko_activation_check()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN

        UPDATE merchant_outlets
        SET iiko_config_revision = iiko_config_revision + 1
        WHERE id = NEW.outlet_id;

        DELETE FROM outlet_iiko_activation_checks
        WHERE outlet_id = NEW.outlet_id;

    ELSIF (
           OLD.connection_id,
           OLD.organization_id,
           OLD.terminal_group_id
        ) IS DISTINCT FROM (
                            NEW.connection_id,
                            NEW.organization_id,
                            NEW.terminal_group_id
        ) THEN

        UPDATE merchant_outlets
        SET iiko_config_revision = iiko_config_revision + 1
        WHERE id = NEW.outlet_id;

        DELETE FROM outlet_iiko_activation_checks
        WHERE outlet_id = NEW.outlet_id;

    END IF;

    RETURN NEW;
END;
$$;


-- Изменение столов или их сопоставления с iiko.
CREATE OR REPLACE FUNCTION invalidate_iiko_check_on_table_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
DECLARE
    old_outlet UUID;
    new_outlet UUID;
    affected_outlet UUID;
BEGIN
    IF TG_OP = 'INSERT' THEN

        new_outlet := NEW.outlet_id;

    ELSIF TG_OP = 'DELETE' THEN

        old_outlet := OLD.outlet_id;

    ELSE

        IF OLD.pos_table_id IS NOT DISTINCT FROM NEW.pos_table_id
            AND OLD.is_active IS NOT DISTINCT FROM NEW.is_active
            AND OLD.outlet_id IS NOT DISTINCT FROM NEW.outlet_id
        THEN
            RETURN NEW;
        END IF;

        old_outlet := OLD.outlet_id;
        new_outlet := NEW.outlet_id;

    END IF;

    -- Обновляем версии затронутых торговых точек
    -- в определённом порядке.
    FOR affected_outlet IN
        SELECT DISTINCT id
        FROM (
                 VALUES (old_outlet), (new_outlet)
             ) AS affected(id)
        WHERE id IS NOT NULL
        ORDER BY id
        LOOP

            UPDATE merchant_outlets
            SET iiko_config_revision = iiko_config_revision + 1
            WHERE id = affected_outlet;

        END LOOP;

    -- Удаляем устаревшие результаты проверки.
    DELETE FROM outlet_iiko_activation_checks
    WHERE outlet_id = old_outlet
       OR outlet_id = new_outlet;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;
