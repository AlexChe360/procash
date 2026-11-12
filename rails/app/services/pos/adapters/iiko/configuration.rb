module Pos::Adapters::Iiko
  class Configuration
    class Error < StandardError; end
    class Stale < Error; end

    def initialize(outlet, user:, client_factory: nil)
      @outlet, @user = outlet, user
      @client_factory = client_factory || ->(connection) { build_client(connection) }
      authorize!
    end

    def authorize!
      @outlet.reload
      membership = MerchantMembership.find_by(merchant_id: @outlet.merchant_id, user_id: @user.id, is_active: true)
      raise Error, "Недостаточно прав" unless @user.reload.is_active && membership&.manages? && @outlet.pos_system == "iiko"
    end

    def create_connection(name, key)
      raise Error, "Проверьте имя и API-ключ" unless (2..150).cover?(name.strip.length) && (1..4096).cover?(key.strip.bytesize) && !name.strip.match?(/[[:cntrl:]]/) && !key.strip.match?(/[[:cntrl:]]/)
      id = SecureRandom.uuid
      encrypted = KeyCipher.new.encrypt(id, key.strip)
      authorize!
      @outlet.merchant.iiko_connections.create!(id: id, name: name.strip, **encrypted)
    end

    def verify(connection_id)
      connection = connection_for(connection_id)
      raise Error, "Подключение отключено" if connection.status == "disabled"
      original = secret_snapshot(connection)
      outcome = nil
      begin
        organizations = @client_factory.call(connection).organizations
        outcome = organizations.empty? ? ["draft", "NO_ORGANIZATIONS"] : ["verified", nil]
      rescue Client::Error => error
        outcome = [400, 401, 403].include?(error.status) ? ["draft", "AUTH_REJECTED"] : [nil, "API_UNAVAILABLE"]
      end
      connection.with_lock do
        authorize!
        raise Stale, "Подключение изменилось" unless secret_snapshot(connection) == original && connection.status != "disabled"
        values = { last_error_code: outcome[1] }
        values[:status] = outcome[0] if outcome[0]
        values[:last_verified_at] = Time.current if outcome[0] == "verified"
        connection.update!(values)
      end
      outcome[0] == "verified"
    end

    def setup(connection_id, organization_id = nil)
      connection = connection_for(connection_id)
      raise Error, "Сначала проверьте подключение" unless connection.verified?
      client = @client_factory.call(connection)
      organizations = client.organizations.select { |item| uuid?(item["id"]) }
      groups = []
      if organizations.any? { |item| item["id"] == organization_id }
        groups = groups_for(client, organization_id)
      end
      { connection: connection, organizations: organizations, groups: groups, organization_id: organization_id }
    end

    def bind(connection_id, organization_id, terminal_group_id)
      data = setup(connection_id, organization_id)
      raise Error, "Некорректная организация или терминальная группа" unless uuid?(organization_id) && uuid?(terminal_group_id) && data[:organizations].any? { |org| org["id"] == organization_id } && data[:groups].any? { |group| group["id"] == terminal_group_id }
      connection = data[:connection]
      original = secret_snapshot(connection)
      connection.with_lock do
        authorize!
        raise Stale, "Подключение изменилось" unless connection.verified? && secret_snapshot(connection) == original
        setting = @outlet.outlet_iiko_setting || @outlet.build_outlet_iiko_setting(merchant_id: @outlet.merchant_id)
        setting.update!(connection_id: connection.id, organization_id: organization_id, terminal_group_id: terminal_group_id, is_enabled: false, last_success_at: nil, last_error: nil)
      end
    end

    def catalog
      context = snapshot
      client = @client_factory.call(context[:connection])
      { context: context, tables: normalize_tables(client.restaurant_sections(context[:group], revision: 0), context[:group]) }
    end

    def link(table_id, external_id)
      data = catalog
      raise Error, "Стол недоступен" unless uuid?(external_id) && data[:tables].any? { |table| table["id"] == external_id }
      # A table UPDATE owns its row before its trigger locks settings/outlet.
      # Do not lock settings first here: that inverts ordinary table-update
      # locking and can deadlock against another writer of the same table.
      context = data[:context]
      OutletTable.transaction do
        authorize!
        connection_ids = IikoConnection.where(id: context[:connection].id, merchant_id: @outlet.merchant_id, status: "verified", **context[:secret])
          .where.not(last_verified_at: nil).select(:id)
        outlet_ids = OutletIikoSetting.where(outlet_id: @outlet.id, merchant_id: @outlet.merchant_id,
          connection_id: connection_ids, organization_id: context[:organization], terminal_group_id: context[:group]).select(:outlet_id)
        changed = OutletTable.active.where(id: table_id, outlet_id: outlet_ids).update_all(pos_table_id: external_id, updated_at: Time.current)
        raise Stale, "Привязка изменилась" unless changed == 1
        OutletIikoSetting.where(outlet_id: @outlet.id, merchant_id: @outlet.merchant_id).update_all(is_enabled: false, updated_at: Time.current)
      end
    rescue ActiveRecord::RecordNotUnique
      raise Error, "Стол уже сопоставлен"
    end

    def check
      context = snapshot
      error = nil
      begin
        verify_live(context)
      rescue Error, Client::Error
        error = "verification_error"
      end
      locked(context) do
        authorize!
        check = OutletIikoActivationCheck.find_or_initialize_by(outlet_id: @outlet.id)
        check.update!(status: error ? "failed" : "passed", checked_at: Time.current, error_code: error)
      end
      error.nil?
    end

    def enable
      context = snapshot
      verify_live(context) # Always repeat live verification; a saved check never authorizes activation.
      locked(context) do |setting|
        authorize!
        raise Error, "Торговая точка отключена" if @outlet.status == "disabled"
        raise Stale, "Сопоставления изменились" unless mapped_count == context[:mapped]
        setting.update!(is_enabled: true, last_error: nil)
        @outlet.update!(status: "active") if @outlet.status == "draft"
      end
    end

    def normalize_tables(response, group)
      seen = {}
      response.fetch("restaurantSections").flat_map do |section|
        next [] unless section["terminalGroupId"] == group
        raise Error, "Некорректная секция" unless uuid?(section["id"])
        section.fetch("tables").filter_map do |table|
          next if table["isDeleted"] == true
          id = table["id"]
          raise Error, "Некорректный справочник столов" unless uuid?(id) && table["name"].is_a?(String) && !table["name"].strip.empty? && !seen[id]
          seen[id] = true
          name = table["name"].strip
          number = table["number"]
          display_name = if number.is_a?(Integer)
            name.match?(/\Aстол\s*\d+\z/i) ? "Стол #{number}" : "#{name} · № #{number}"
          else
            name
          end
          table.merge("name" => name, "displayName" => display_name, "sectionName" => section["name"])
        end
      end.sort_by do |table|
        order = table["number"].is_a?(Integer) ? [0, table["number"]] : [1, natural_sort_key(table["name"])]
        [natural_sort_key(table["sectionName"]), order, natural_sort_key(table["name"]), table["id"]]
      end
    end

    private
    def natural_sort_key(value)
      value.to_s.downcase.scan(/[0-9]+|[^0-9]+/).map do |part|
        part.match?(/\A[0-9]+\z/) ? [0, part.to_i] : [1, part]
      end
    end
    def connection_for(id) = @outlet.merchant.iiko_connections.find(id)
    def uuid?(id) = id.to_s.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i) && id.delete("-") != "0" * 32
    def secret_snapshot(connection) = connection.attributes.slice("api_key_ciphertext", "api_key_nonce", "encryption_key_version")
    def mapped_count = @outlet.outlet_tables.active.where.not(pos_table_id: nil).where("BTRIM(pos_table_id) <> ''").count

    def snapshot
      authorize!
      setting = OutletIikoSetting.find_by!(outlet_id: @outlet.id, merchant_id: @outlet.merchant_id)
      connection = connection_for(setting.connection_id)
      raise Error, "Сначала проверьте подключение и выберите организацию" unless connection.verified? && uuid?(setting.organization_id) && uuid?(setting.terminal_group_id)
      { connection: connection, secret: secret_snapshot(connection), organization: setting.organization_id, group: setting.terminal_group_id, revision: @outlet.iiko_config_revision, mapped: mapped_count }
    end

    def locked(context)
      MerchantOutlet.transaction do
        # Match the PostgreSQL triggers and Rust activation lock order.
        connection = connection_for(context[:connection].id).lock!
        raise Stale, "Ключ подключения изменился" unless connection.verified? && secret_snapshot(connection) == context[:secret]
        setting = OutletIikoSetting.where(outlet_id: @outlet.id, merchant_id: @outlet.merchant_id).lock.first!
        raise Stale, "Привязка изменилась" unless setting.connection_id == connection.id && setting.organization_id == context[:organization] && setting.terminal_group_id == context[:group]
        @outlet.lock!
        raise Stale, "Конфигурация изменилась во время проверки" unless @outlet.iiko_config_revision == context[:revision] && @outlet.pos_system == "iiko"
        yield setting
      end
    end

    def verify_live(context)
      raise Error, "Сначала сопоставьте столы" if context[:mapped] < 1
      client = @client_factory.call(context[:connection])
      raise Error, "Организация недоступна" unless client.organizations.any? { |org| org["id"] == context[:organization] }
      raise Error, "Терминальная группа недоступна" unless groups_for(client, context[:organization]).any? { |group| group["id"] == context[:group] }
    end

    def groups_for(client, organization)
      client.terminal_groups(organization).select { |group| group["organizationId"] == organization }.flat_map { |group| group.fetch("items") }.select { |item| item["organizationId"] == organization && uuid?(item["id"]) }.uniq { |item| item["id"] }
    end

    def build_client(connection)
      key = KeyCipher.new.decrypt(connection.id, ciphertext: connection.api_key_ciphertext, nonce: connection.api_key_nonce, version: connection.encryption_key_version)
      Client.new(app_id: ENV.fetch("IIKO_APP_ID"), client_secret: ENV.fetch("IIKO_CLIENT_SECRET"), api_key: key)
    end
  end
end
