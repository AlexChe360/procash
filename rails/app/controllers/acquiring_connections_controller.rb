class AcquiringConnectionsController < ApplicationController
  before_action :require_admin
  before_action :load_outlet

  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to acquiring_path, alert: error.record.errors.full_messages.join(", "), status: :see_other
  end
  rescue_from ActiveRecord::RecordNotUnique do
    redirect_to acquiring_path, alert: "Такое подключение уже существует.", status: :see_other
  end
  rescue_from ArgumentError do
    redirect_to acquiring_path, alert: "Для выбора основным нужны одобренные боевые реквизиты.", status: :see_other
  end

  def create
    connection = @outlet.acquiring_connections.new(connection_attributes.merge(id: SecureRandom.uuid, merchant_id: @merchant.id))
    assign_secret(connection)
    @outlet.with_lock do
      connection.save!
      set_default(connection) if params[:is_default] == "1"
    end
    redirect_to acquiring_path, notice: "Подключение сохранено. Приём платежей пока не включён.", status: :see_other
  rescue KeyError, ArgumentError, OpenSSL::Cipher::CipherError
    redirect_to acquiring_path, alert: "Не удалось сохранить ключ. Проверьте данные и настройку шифрования.", status: :see_other
  end

  def update
    @outlet.with_lock do
      connection = find_connection
      connection.assign_attributes(connection_attributes)
      if connection.will_save_change_to_provider? && connection.acquiring_requests.exists?
        connection.errors.add(:base, "Провайдер связан с заявкой. Для другого провайдера нужна отдельная заявка.")
        raise ActiveRecord::RecordInvalid, connection
      end
      credentials_changed = %w[provider provider_merchant_id environment].any? { |field| connection.will_save_change_to_attribute?(field) } || params[:payment_secret].present?
      if connection.secret_saved? && %w[provider provider_merchant_id environment].any? { |field| connection.will_save_change_to_attribute?(field) } && params[:payment_secret].to_s.strip.empty?
        connection.errors.add(:base, "При изменении провайдера, Merchant ID или режима введите секретный ключ для новых реквизитов.")
        raise ActiveRecord::RecordInvalid, connection
      end
      assign_secret(connection)
      connection.is_default = false if credentials_changed
      connection.save!
      if credentials_changed
        connection.acquiring_requests.where(status: "approved").update_all(status: "in_review", reviewed_at: nil, reviewed_by: nil, review_note: nil, updated_at: Time.current)
      end
    end
    redirect_to acquiring_path, notice: "Настройки подключения сохранены.", status: :see_other
  rescue KeyError, ArgumentError, OpenSSL::Cipher::CipherError
    redirect_to acquiring_path, alert: "Не удалось сохранить ключ. Проверьте данные и настройку шифрования.", status: :see_other
  end

  def primary
    @outlet.with_lock do
      connection = find_connection
      if connection.disabled?
        return redirect_to acquiring_path, alert: "Сначала восстановите подключение.", status: :see_other
      end
      set_default(connection)
    end
    redirect_to acquiring_path, notice: "Основное подключение выбрано. Это не включает приём платежей.", status: :see_other
  end

  def toggle
    return head :bad_request unless %w[disable restore].include?(params[:operation])
    @outlet.with_lock do
      connection = find_connection
      connection.update!(disabled_at: params[:operation] == "disable" ? Time.current : nil, is_default: false)
    end
    redirect_to acquiring_path, notice: "Настройки подключения обновлены.", status: :see_other
  end

  private
  def load_outlet
    @outlet = MerchantOutlet.find(params[:outlet_id])
    @merchant = @outlet.merchant
  end
  def find_connection = @outlet.acquiring_connections.where(merchant_id: @merchant.id).find(params[:connection_id])
  def acquiring_path = "/admin/acquiring/outlets/#{@outlet.id}"
  def connection_attributes
    params.permit(:name, :provider, :provider_merchant_id, :environment).to_h.transform_values(&:strip)
  end
  def assign_secret(connection)
    secret = params[:payment_secret].to_s.strip
    return if secret.empty?
    raise ArgumentError, "Invalid secret length" unless (1..4096).cover?(secret.bytesize)
    connection.assign_attributes(PaymentProviders::SecretCipher.new.encrypt(connection.id, secret))
  end
  def set_default(connection)
    raise ArgumentError, "Approval required" unless connection.acquiring_requests.where(status: "approved").exists? && connection.environment == "live" && connection.secret_saved?
    @outlet.acquiring_connections.where(is_default: true).where.not(id: connection.id).update_all(is_default: false, updated_at: Time.current)
    connection.update!(is_default: true)
  end
end
