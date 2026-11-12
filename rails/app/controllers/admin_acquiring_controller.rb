class AdminAcquiringController < ApplicationController
  before_action :require_admin
  before_action :load_item, only: %i[show review configure decision]

  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to detail_path, alert: error.record.errors.full_messages.join(", "), status: :see_other
  end
  rescue_from ActiveRecord::RecordNotUnique do
    redirect_to detail_path, alert: "Такие реквизиты уже сохранены у точки. Выберите существующее подключение.", status: :see_other
  end
  rescue_from ArgumentError, KeyError, OpenSSL::Cipher::CipherError do |error|
    message = error.is_a?(ArgumentError) && error.message.start_with?("Для ", "Заявка ", "Выберите ") ? error.message : "Не удалось сохранить данные. Проверьте реквизиты и настройки шифрования."
    redirect_to detail_path, alert: message, status: :see_other
  end

  def index
    @items = AcquiringRequest.includes(:merchant, :merchant_outlet).order(created_at: :desc).limit(200)
    @configured_outlets = MerchantOutlet.where(id: AcquiringConnection.select(:outlet_id)).includes(:merchant).order(:name)
  end
  def show
    @connection = @item.acquiring_connection
    @connections = @outlet.acquiring_connections.where(provider: @item.provider).order(:created_at)
  end
  def outlet
    @outlet = MerchantOutlet.find(params[:outlet_id])
    @connections = @outlet.acquiring_connections.order(:created_at)
  end
  def review
    with_context do
      raise ArgumentError, "Заявка уже рассмотрена." unless @item.status.in?(%w[pending in_review])
      @item.update!(status: "in_review", reviewed_by: current_user.id)
    end
    redirect_to detail_path, notice: "Заявка взята в работу.", status: :see_other
  end
  def configure
    with_context do
      raise ArgumentError, "Заявка отклонена. Для подключения нужна новая заявка." if @item.status == "rejected"
      connection = @item.acquiring_connection
      connection ||= @outlet.acquiring_connections.where(provider: @item.provider).find(params[:existing_connection_id]) if params[:existing_connection_id].present?
      connection ||= @outlet.acquiring_connections.new(id: SecureRandom.uuid, merchant_id: @item.merchant_id, provider: @item.provider)
      connection.assign_attributes(params.permit(:name, :provider_merchant_id, :environment))
      secret = params[:payment_secret].to_s.strip
      changed_account = %w[provider_merchant_id environment].any? { |field| connection.will_save_change_to_attribute?(field) }
      raise ArgumentError, "Для изменения Merchant ID или режима введите новый ключ." if connection.secret_saved? && changed_account && secret.empty?
      unless secret.empty?
        raise ArgumentError if secret.bytesize > 4096
        connection.assign_attributes(PaymentProviders::SecretCipher.new.encrypt(connection.id, secret))
      end
      connection.is_default = false
      connection.save!
      @item.update!(acquiring_connection: connection, status: "in_review", reviewed_by: current_user.id, reviewed_at: nil, review_note: nil)
    end
    redirect_to detail_path, notice: "Реквизиты сохранены. Теперь рассмотрите и одобрите заявку.", status: :see_other
  end
  def decision
    return head :bad_request unless %w[approve reject].include?(params[:decision])
    with_context do
      raise ArgumentError, "Заявка уже рассмотрена." unless @item.status.in?(%w[pending in_review])
      note = params[:review_note].to_s.strip
      connection = @item.acquiring_connection
      if params[:decision] == "approve"
        raise ArgumentError, "Для одобрения сохраните боевой Merchant ID и ключ." unless connection && connection.secret_saved? && !connection.disabled? && connection.environment == "live"
      else
        raise ArgumentError, "Для отклонения укажите причину для мерчанта." if note.empty?
        connection&.update!(is_default: false)
      end
      @item.update!(status: params[:decision] == "approve" ? "approved" : "rejected", review_note: note, reviewed_by: current_user.id, reviewed_at: Time.current)
    end
    redirect_to detail_path, notice: "Решение сохранено и доступно мерчанту.", status: :see_other
  end
  private
  def load_item
    @item = AcquiringRequest.find(params[:request_id])
    @outlet = @item.merchant_outlet
  end
  def detail_path = "/admin/acquiring/requests/#{@item.id}"
  def with_context
    @outlet.with_lock do
      @item.lock!
      yield
    end
  end
end
