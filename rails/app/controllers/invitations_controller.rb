class InvitationsController < ApplicationController
  layout false
  def show
    @invitation = MerchantInvitation.for_token(params[:token])
    raise ActiveRecord::RecordNotFound unless @invitation
    @token = params[:token]
  end
  def activate
    @token = params[:token]
    @invitation = MerchantInvitation.for_token(@token)
    raise ActiveRecord::RecordNotFound unless @invitation
    raise ArgumentError, "Пароли не совпадают" unless params[:password] == params[:password_confirmation]
    MerchantInvitation.activate!(@token, params[:password].to_s)
    redirect_to "/invite/success", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordNotUnique => error
    @error = error.is_a?(ActiveRecord::RecordNotUnique) ? "Аккаунт уже существует" : error.message
    render :show, status: :unprocessable_entity
  end
  def success; end
end
