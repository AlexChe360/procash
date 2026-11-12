class AdminController < ApplicationController
  before_action :require_admin
  before_action :load_request, only: %i[show review decision merchant invitation]
  def index
    @merchant_count = Merchant.count
    @activity = AdminActivityPresenter.new(period: params[:period])
  end
  def requests
    @requests = ConnectionRequest.order(created_at: :desc).limit(100)
  end
  def merchants
    @merchants = Merchant.order(created_at: :desc)
  end
  def new_merchant
    @preview = false
  end
  def preview_merchant
    @legal_name, @bin_iin = params[:legal_name].to_s.strip, params[:bin_iin].to_s.strip
    @preview = (2..200).cover?(@legal_name.length) && @bin_iin.match?(/\A[0-9]{12}\z/)
    @error = "Проверьте название компании и 12 цифр БИН/ИИН" unless @preview
    render :new_merchant, status: @preview ? :ok : :unprocessable_entity
  end
  def show; end
  def review
    @connection_request.transition!("in_review", current_user)
    redirect_to detail_path, status: :see_other
  rescue ArgumentError => error
    render plain: error.message, status: :conflict
  end
  def decision
    target = { "approve" => "approved", "reject" => "rejected" }.fetch(params[:action_name]) { raise ArgumentError, "Недопустимое решение" }
    @connection_request.transition!(target, current_user)
    redirect_to detail_path, status: :see_other
  rescue ArgumentError => error
    render plain: error.message, status: :conflict
  end
  def merchant
    @connection_request.create_merchant!(legal_name: params[:legal_name].to_s, bin_iin: params[:bin_iin].to_s)
    redirect_to detail_path, status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    render plain: "Проверьте статус заявки, название и уникальность БИН/ИИН", status: :unprocessable_entity
  end
  def invitation
    MerchantInvitation.issue!(@connection_request, current_user)
    redirect_to detail_path, notice: "Приглашение создано и добавлено в очередь отправки.", status: :see_other
  rescue ArgumentError => error
    redirect_to detail_path, alert: error.message, status: :see_other
  end
  private
  def load_request = @connection_request = ConnectionRequest.find(params[:id])
  def detail_path = "/demo/requests/#{@connection_request.id}"
end
