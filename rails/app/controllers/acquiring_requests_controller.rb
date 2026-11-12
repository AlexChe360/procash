class AcquiringRequestsController < ApplicationController
  before_action :require_merchant
  before_action :load_company
  before_action :require_manager
  before_action { @outlet = @merchant.merchant_outlets.find(params[:outlet_id]) }

  def create
    providers = Array(params[:providers]).map(&:to_s).uniq
    if providers.empty? || (providers - PaymentProviders::Registry::PROVIDERS.keys).any?
      return redirect_to target, alert: "Выберите платёжного провайдера.", status: :see_other
    end
    added = 0
    @outlet.with_lock do
      providers.each do |provider|
        next if @outlet.acquiring_requests.where(provider: provider, status: %w[pending in_review approved]).exists?
        @outlet.acquiring_requests.create!(merchant: @merchant, provider: provider, requested_by: current_user.id)
        added += 1
      end
    end
    redirect_to target, notice: added.positive? ? "Заявка отправлена в ProCash. Статус появится здесь после рассмотрения." : "Заявка уже отправлена или провайдер одобрен. Повторная заявка не создана.", status: :see_other
  end

  def primary
    @outlet.with_lock do
      item = @outlet.acquiring_requests.where(merchant_id: @merchant.id, status: "approved").find(params[:request_id])
      connection = item.acquiring_connection
      unless connection && !connection.disabled? && connection.secret_saved? && connection.environment == "live"
        return redirect_to target, alert: "Основным можно выбрать одобренное боевое подключение. Обратитесь в ProCash.", status: :see_other
      end
      @outlet.acquiring_connections.where(is_default: true).update_all(is_default: false, updated_at: Time.current)
      connection.update!(is_default: true)
    end
    redirect_to target, notice: "Основной провайдер выбран. Приём платежей будет доступен после запуска платёжной интеграции.", status: :see_other
  end
  private
  def target = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}?tab=acquiring"
end
