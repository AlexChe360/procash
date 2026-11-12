class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :verify_request_origin
  before_action { response.headers["Cache-Control"] = "no-store" }
  helper_method :current_user
  rescue_from ActiveRecord::RecordNotFound do
    render plain: "Страница не найдена", status: :not_found
  end
  private
  def verify_request_origin
    return unless request.post? && protect_against_forgery?
    expected = expected_request_origin.delete_suffix("/")
    head :forbidden unless request.headers["Origin"] == expected
  end
  def expected_request_origin
    ENV.fetch("APP_ORIGIN", request.base_url)
  end
  def current_session
    return @current_session if defined?(@current_session)
    candidate = UserSession.for_token(cookies.encrypted[auth_cookie_name])
    candidate ||= UserSession.for_token(cookies.encrypted[:procash_rails_session])
    @current_session = candidate if candidate && candidate.user.admin? == admin_auth_context?
  end
  def admin_auth_context?
    controller_name == "admin" || request.path.start_with?("/admin/", "/demo/")
  end
  def auth_cookie_name
    admin_auth_context? ? :procash_admin_session : :procash_merchant_session
  end
  def clear_legacy_auth_cookie
    legacy = UserSession.for_token(cookies.encrypted[:procash_rails_session])
    cookies.delete(:procash_rails_session) if legacy && legacy.user.admin? == admin_auth_context?
  end
  def current_user
    user = current_session&.user
    user if user&.is_active && user.email_verified_at
  end
  def require_admin
    redirect_to "/admin/login" unless current_user&.admin?
  end
  def require_merchant
    unless current_user && !current_user.admin? && current_user.merchant_memberships.where(is_active: true).exists?
      redirect_to "/login"
    end
  end
  def load_company
    @membership = current_user.merchant_memberships.where(is_active: true).find_by!(merchant_id: params[:id])
    @merchant = @membership.merchant
  end
  def require_manager
    head :forbidden unless @membership.manages?
  end
end
