DROP TRIGGER IF EXISTS
    trg_invalidate_iiko_activation_check
    ON outlet_iiko_settings;

DROP FUNCTION IF EXISTS
    invalidate_iiko_activation_check();
