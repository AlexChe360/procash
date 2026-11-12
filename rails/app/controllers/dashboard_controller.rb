class DashboardController < ApplicationController
  before_action :require_merchant
  before_action :load_company, except: :index
  before_action :require_manager, only: %i[create_outlet create_table tips qr_logo]
  def index
    @memberships = current_user.merchant_memberships.where(is_active: true).includes(:merchant)
  end
  def company
    @outlets = @merchant.merchant_outlets.order(created_at: :desc).limit(100)
  end
  def create_outlet
    @merchant.merchant_outlets.create!(params.permit(:name, :city, :address, :pos_system).to_h.transform_values { |v| v.strip.presence })
    redirect_to "/dashboard/merchants/#{@merchant.id}/outlets", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @new_outlet = error.record
    @error = error.record.errors.full_messages.join(", ")
    @outlets = @merchant.merchant_outlets.order(created_at: :desc).limit(100)
    render :company, status: :unprocessable_entity
  end
  def outlet
    @outlet = @merchant.merchant_outlets.find(params[:outlet_id])
    @tables = @outlet.outlet_tables.active.order(:code).to_a
    allowed = @membership.manages? ? %w[overview tables tips pos acquiring] : %w[overview tables]
    @tab = allowed.include?(params[:tab]) ? params[:tab] : "overview"
    @acquiring_requests = @outlet.acquiring_requests.includes(:acquiring_connection).order(created_at: :desc).to_a if @tab == "acquiring"
  end
  def qr
    outlet = @merchant.merchant_outlets.find(params[:outlet_id])
    table = outlet.outlet_tables.active.find(params[:table_id])
    origin = ENV.fetch("APP_ORIGIN", "http://localhost:3101").delete_suffix("/")
    filename = "procash-table-#{table.code.parameterize.presence || table.id}.svg"
    send_data Qr::Renderer.call("#{origin}/t/#{table.qr_token}", table.name, design: params[:design], logo: outlet.qr_logo, color: params[:color]), type: "image/svg+xml", disposition: params[:download] == "1" ? "attachment" : "inline", filename: filename
  end
  def qr_design
    @outlet = @merchant.merchant_outlets.find(params[:outlet_id])
    @table = @outlet.outlet_tables.active.find(params[:table_id])
    @design = Qr::Renderer::DESIGNS.key?(params[:design]) ? params[:design] : "classic"
    @color = Qr::Renderer.color(params[:color])
  end
  def qr_logo
    qr_design
    @outlet.update!(qr_logo: params[:reset_logo] == "1" ? nil : Qr::Logo.read(params[:logo]))
    query = { design: @design }
    query[:color] = @color if @color
    redirect_to "#{request.path.delete_suffix('/logo')}/design?#{query.to_query}", notice: "Логотип QR-карточек сохранён.", status: :see_other
  rescue ArgumentError => error
    @error = error.message
    render :qr_design, status: :unprocessable_entity
  end
  def qr_print
    qr_design
    @print_sizes = { "small" => [40, 50], "standard" => [60, 75], "large" => [80, 100] }
    @print_size = @print_sizes.key?(params[:size]) ? params[:size] : "standard"
    @print_width, @print_height = @print_sizes.fetch(@print_size)
    origin = ENV.fetch("APP_ORIGIN", "http://localhost:3101").delete_suffix("/")
    @print_svg = Qr::Renderer.call("#{origin}/t/#{@table.qr_token}", @table.name, design: @design, logo: @outlet.qr_logo, color: @color).sub(/<\?xml.*?\?>\s*/, "")
    render layout: false
  end
  def create_table
    @outlet = @merchant.merchant_outlets.find(params[:outlet_id])
    @outlet.outlet_tables.create!(params.permit(:code, :name, :zone).to_h.transform_values { |v| v.strip.presence })
    redirect_to "#{outlet_url_path}?tab=tables", notice: "Стол добавлен", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    @error = "Проверьте название и уникальность кода стола"
    @tables = @outlet.outlet_tables.active.order(:code).to_a
    @tab = "tables"
    render :outlet, status: :unprocessable_entity
  end
  def tips
    @outlet = @merchant.merchant_outlets.find(params[:outlet_id])
    checkbox_fields = %w[is_enabled allow_custom_amount tip_5 tip_10 tip_15 tip_20]
    return head :bad_request unless checkbox_fields.all? { |field| params[field].nil? || params[field] == "1" }
    percentages = [5, 10, 15, 20].select { |value| params["tip_#{value}"] == "1" }
    enabled, custom = params[:is_enabled] == "1", params[:allow_custom_amount] == "1"
    if enabled && percentages.empty? && !custom
      return render plain: "Выберите проценты или произвольную сумму", status: :bad_request
    end
    setting = @outlet.outlet_tip_setting || @outlet.build_outlet_tip_setting
    setting.update!(is_enabled: enabled, allow_custom_amount: custom, percentages: percentages)
    redirect_to "#{outlet_url_path}?tab=tips", notice: "Настройки чаевых сохранены", status: :see_other
  end
  private
  def outlet_url_path = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}"
end
