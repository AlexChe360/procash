class AccountSettingsController < ApplicationController
  before_action :require_account
  rate_limit to: 10, within: 1.minute, only: :password, with: -> { render plain: "Попробуйте позже", status: :too_many_requests }

  def show; end

  def profile
    name = params[:display_name].to_s.strip
    raise ArgumentError, "Имя должно содержать от 2 до 100 символов" unless (2..100).cover?(name.length)
    current_user.update!(display_name: name)
    redirect_to settings_path, notice: "Имя сохранено.", status: :see_other
  rescue ArgumentError => error
    @error = error.message
    render :show, status: :unprocessable_entity
  end

  def password
    account = current_user
    account.with_lock do
      raise ArgumentError, "Текущий пароль неверный" unless Auth::Password.verify(params[:current_password], account.password_hash)
      value = params[:new_password].to_s
      raise ArgumentError, "Подтверждение пароля не совпадает" unless value == params[:password_confirmation].to_s
      account.update!(password_hash: Auth::Password.hash(value))
      account.user_sessions.live.where.not(id: current_session.id).update_all(revoked_at: Time.current)
    end
    redirect_to settings_path, notice: "Пароль изменён. Другие сеансы этого аккаунта завершены.", status: :see_other
  rescue ArgumentError => error
    @error = error.message
    render :show, status: :unprocessable_entity
  end

  private
  def require_account
    admin_auth_context? ? require_admin : require_merchant
  end
  def settings_path = admin_auth_context? ? "/admin/settings" : "/dashboard/settings"
end
