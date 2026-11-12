class ActivateConfiguredIikoOutlets < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE merchant_outlets o
      SET status = 'active', updated_at = NOW()
      FROM outlet_iiko_settings s
      JOIN iiko_connections c ON c.id = s.connection_id AND c.merchant_id = s.merchant_id
      WHERE o.id = s.outlet_id AND o.merchant_id = s.merchant_id
        AND o.status = 'draft' AND o.pos_system = 'iiko' AND s.is_enabled = TRUE
        AND c.status = 'verified' AND c.last_verified_at IS NOT NULL
        AND s.organization_id IS NOT NULL AND s.terminal_group_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM outlet_tables t WHERE t.outlet_id = o.id AND t.is_active = TRUE AND NULLIF(BTRIM(t.pos_table_id), '') IS NOT NULL)
    SQL
  end

  def down
    # Operational activation must not be reverted by rolling back a data repair.
  end
end
