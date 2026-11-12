class BillsController < ApplicationController
  def show
    @result = Pos::QrBillService.load(params[:token])
    raise ActiveRecord::RecordNotFound unless @result
    raise ArgumentError if params.key?(:tip) && params.key?(:custom_tip)
    percentage = params[:tip].nil? ? 0 : Integer(params[:tip], 10)
    @display = GuestBillPresenter.new(@result, percentage: percentage, custom: params[:custom_tip])
    render layout: false
  rescue ArgumentError
    render plain: "Некорректные параметры чаевых", status: :bad_request
  end
end
