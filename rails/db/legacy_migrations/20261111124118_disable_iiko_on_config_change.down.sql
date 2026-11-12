-- Restore previous behavior (the earlier migrations remain unchanged).
DROP TRIGGER IF EXISTS trg_disable_iiko_before_binding_change
    ON outlet_iiko_settings;

DROP FUNCTION IF EXISTS disable_iiko_before_binding_change();

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

    FOR affected_outlet IN
        SELECT DISTINCT id
        FROM (VALUES (old_outlet), (new_outlet)) AS affected(id)
        WHERE id IS NOT NULL
        ORDER BY id
        LOOP
            UPDATE merchant_outlets
            SET iiko_config_revision = iiko_config_revision + 1
            WHERE id = affected_outlet;
        END LOOP;

    DELETE FROM outlet_iiko_activation_checks
    WHERE outlet_id = old_outlet
       OR outlet_id = new_outlet;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION invalidate_iiko_check_on_connection_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS $$
DECLARE
    affected_outlet_id UUID;
BEGIN
    IF OLD.status IS NOT DISTINCT FROM NEW.status
        AND OLD.api_key_ciphertext IS NOT DISTINCT FROM NEW.api_key_ciphertext
        AND OLD.api_key_nonce IS NOT DISTINCT FROM NEW.api_key_nonce
        AND OLD.encryption_key_version IS NOT DISTINCT FROM NEW.encryption_key_version
        AND (OLD.last_verified_at IS NULL) = (NEW.last_verified_at IS NULL)
    THEN
        RETURN NEW;
    END IF;

    FOR affected_outlet_id IN
        SELECT s.outlet_id
        FROM outlet_iiko_settings s
        WHERE s.connection_id = NEW.id
          AND s.merchant_id = NEW.merchant_id
        ORDER BY s.outlet_id
        LOOP
            UPDATE merchant_outlets
            SET iiko_config_revision = iiko_config_revision + 1
            WHERE id = affected_outlet_id
              AND merchant_id = NEW.merchant_id
              AND pos_system = 'iiko';

            DELETE FROM outlet_iiko_activation_checks
            WHERE outlet_id = affected_outlet_id;
        END LOOP;

    RETURN NEW;
END;
$$;
