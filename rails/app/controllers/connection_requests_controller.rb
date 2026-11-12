class ConnectionRequestsController < ApplicationController
  layout false
  def new
    @connection_request = ConnectionRequest.new
  end
  def create
    return redirect_to "/connect/success", status: :see_other if params[:website].present?
    @connection_request = ConnectionRequest.new(params.permit(:contact_name, :contact_email, :contact_phone, :establishment_name, :bin_iin, :city, :pos_system, :comment, :consent))
    if @connection_request.save
      redirect_to "/connect/success", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end
  def success; end
end
