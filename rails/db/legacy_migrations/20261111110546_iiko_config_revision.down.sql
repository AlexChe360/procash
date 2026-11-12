
-- Восстанавливаем прежнюю функцию настроек.
CREATE OR REPLACE FUNCTION invalidate_iiko_activation_check()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
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
        DELETE FROM outlet_iiko_activation_checks
        WHERE outlet_id = NEW.outlet_id;
    END IF;

    RETURN NEW;
END;
$$;

-- Восстанавливаем прежнюю функцию столов.
CREATE OR REPLACE FUNCTION invalidate_iiko_check_on_table_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        DELETE FROM outlet_iiko_activation_checks
        WHERE outlet_id = NEW.outlet_id;

        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        DELETE FROM outlet_iiko_activation_checks
        WHERE outlet_id = OLD.outlet_id;

        RETURN OLD;
    END IF;

    IF OLD.pos_table_id IS DISTINCT FROM NEW.pos_table_id
        OR OLD.is_active IS DISTINCT FROM NEW.is_active
        OR OLD.outlet_id IS DISTINCT FROM NEW.outlet_id
    THEN
        DELETE FROM outlet_iiko_activation_checks
        WHERE outlet_id = OLD.outlet_id
           OR outlet_id = NEW.outlet_id;
    END IF;

    RETURN NEW;
END;
$$;

ALTER TABLE merchant_outlets
    DROP COLUMN iiko_config_revision;

