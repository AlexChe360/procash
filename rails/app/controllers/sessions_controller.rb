class SessionsController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { render plain: "Попробуйте позже", status: :too_many_requests }
  def new
    @admin = request.path.start_with?("/admin")
    render(@admin ? :admin : :merchant, layout: false)
  end
  def create
    @admin = request.path.start_with?("/admin")
    user = User.authenticate(params[:email], params[:password], role: @admin ? "admin" : "user")
    if user
      previous_session = current_session
      clear_legacy_auth_cookie
      previous_session&.update!(revoked_at: Time.current)
      # Authentication tokens rotate independently; keep the shared Rails CSRF
      # session so forms in the other workspace remain valid.
      cookies.encrypted[auth_cookie_name] = { value: UserSession.issue!(user), httponly: true, secure: Rails.env.production?, same_site: :strict, expires: 12.hours.from_now }
      redirect_to(@admin ? "/demo/requests" : "/dashboard", status: :see_other)
    else
      @error = "Неверный email или пароль"
      render(@admin ? :admin : :merchant, layout: false, status: :unprocessable_entity)
    end
  end
  def destroy
    previous_session = current_session
    clear_legacy_auth_cookie
    previous_session&.update!(revoked_at: Time.current)
    cookies.delete(auth_cookie_name)
    redirect_to(admin_auth_context? ? "/admin/login" : "/login", status: :see_other)
  end
end
