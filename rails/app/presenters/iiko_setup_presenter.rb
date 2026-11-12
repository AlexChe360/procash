class IikoSetupPresenter
  attr_reader :setting, :connections, :connection, :table_count, :mapped_count
  def initialize(outlet, tables:)
    @setting = outlet.outlet_iiko_setting
    @connections = outlet.merchant.iiko_connections.order(:created_at).to_a
    @connection = @connections.find { |item| item.id == @setting&.connection_id } || @connections.find(&:verified?) || @connections.first
    @table_count = tables.size
    @mapped_count = tables.count { |table| table.pos_table_id.present? }
  end
  def key_ready? = !!connection&.verified?
  def binding_ready? = key_ready? && setting&.connection_id == connection.id && setting.organization_id.present? && setting.terminal_group_id.present?
  def tables_ready? = !!binding_ready? && mapped_count.positive?
  def enabled? = !!setting&.is_enabled
  def current_step
    return 1 unless key_ready?
    return 2 unless binding_ready?
    return 3 unless tables_ready?
    4
  end
end
