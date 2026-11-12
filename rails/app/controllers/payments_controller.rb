class PaymentsController < ApplicationController
  before_action :require_merchant
  def index
    merchant_ids = current_user.merchant_memberships.where(is_active: true).select(:merchant_id)
    @outlets = MerchantOutlet.where(merchant_id: merchant_ids).includes(:merchant).order(:name)
    @outlet = params[:outlet_id].present? ? @outlets.find(params[:outlet_id]) : @outlets.first
    if @outlet
      @acquiring_connection_count = @outlet.acquiring_requests.where(status: "approved").count
      @can_manage_acquiring = current_user.merchant_memberships.find_by!(merchant_id: @outlet.merchant_id, is_active: true).manages?
    end
  end
end
