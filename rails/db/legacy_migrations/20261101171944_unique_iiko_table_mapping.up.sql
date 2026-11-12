CREATE UNIQUE INDEX IF NOT EXISTS
    outlet_tables_unique_iiko_table_per_outlet
    ON outlet_tables (outlet_id, pos_table_id)
    WHERE pos_table_id IS NOT NULL;