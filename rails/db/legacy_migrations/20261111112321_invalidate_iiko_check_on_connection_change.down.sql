DROP TRIGGER IF EXISTS
    trg_invalidate_iiko_check_on_connection_change
    ON iiko_connections;

DROP FUNCTION IF EXISTS
    invalidate_iiko_check_on_connection_change();