CREATE FUNCTION invalidate_iiko_activation_check()
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

CREATE TRIGGER trg_invalidate_iiko_activation_check
    AFTER INSERT OR UPDATE OF
        connection_id,
        organization_id,
        terminal_group_id
    ON outlet_iiko_settings
    FOR EACH ROW
EXECUTE FUNCTION invalidate_iiko_activation_check();

