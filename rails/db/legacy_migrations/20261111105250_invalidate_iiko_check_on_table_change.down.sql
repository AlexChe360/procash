DROP TRIGGER IF EXISTS
    trg_invalidate_iiko_check_on_table_change
    ON outlet_tables;

DROP FUNCTION IF EXISTS
    invalidate_iiko_check_on_table_change();
