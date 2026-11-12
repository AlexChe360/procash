class PosConfigurationsController < ApplicationController
  before_action :require_merchant
  before_action :load_company
  before_action :require_manager
  before_action :prepare_configuration

  rescue_from Pos::Adapters::Iiko::Client::Error, KeyError, OpenSSL::Cipher::CipherError do
    redirect_to "#{outlet_path}?tab=pos", alert: "Не удалось выполнить шаг. Проверьте доступность iiko и настройки подключения, затем повторите попытку.", status: :see_other
  end

  rescue_from Pos::Adapters::Iiko::Configuration::Error do |error|
    redirect_to "#{outlet_path}?tab=pos", alert: error.message, status: :see_other
  end

  def create
    @configuration.create_connection(params[:name].to_s, params[:api_key].to_s)
    return_to_outlet("Ключ сохранён в зашифрованном виде. Следующий шаг — проверить API-ключ.", anchor: "iiko-step-1")
  end
  def verify
    if @configuration.verify(params[:connection_id])
      redirect_to "#{pos_path}/connections/#{params[:connection_id]}/setup", notice: "API-ключ проверен. Выберите организацию и терминальную группу.", status: :see_other
    else
      code = @merchant.iiko_connections.find(params[:connection_id]).last_error_code
      message = { "NO_ORGANIZATIONS" => "Ключ принят, но организации недоступны. Проверьте права ключа в iiko.", "AUTH_REJECTED" => "iiko отклонил ключ. Проверьте API-ключ и настройки доступа.", "API_UNAVAILABLE" => "iiko сейчас недоступен. Попробуйте проверить ключ позже." }.fetch(code, "Не удалось проверить API-ключ.")
      redirect_to "#{outlet_path}?tab=pos#iiko-step-1", alert: message, status: :see_other
    end
  end
  def setup
    setting = @outlet.outlet_iiko_setting
    saved_binding = setting&.connection_id == params[:connection_id]
    organization = params[:organization_id].presence || (saved_binding ? setting.organization_id : nil)
    @data = @configuration.setup(params[:connection_id], organization)
    @data[:selected_terminal_group_id] = saved_binding && organization == setting.organization_id ? setting.terminal_group_id : nil
  end
  def bind
    @configuration.bind(params[:connection_id], params[:organization_id], params[:terminal_group_id])
    if @outlet.outlet_tables.active.exists?
      redirect_to "#{pos_path}/tables", notice: "Организация и терминальная группа сохранены. Теперь сопоставьте столы.", status: :see_other
    else
      return_to_outlet("Организация и терминальная группа сохранены. Добавьте столы, чтобы продолжить.", anchor: "iiko-step-3")
    end
  end
  def tables
    @data = @configuration.catalog
    @tables = @outlet.outlet_tables.active.order(:code).to_a
  end
  def link
    @configuration.link(params[:table_id], params[:iiko_table_id])
    redirect_to "#{pos_path}/tables", alert: "Сопоставление сохранено. Интеграция iiko выключена: заказы по QR пока не загружаются. Перейдите к активации, проверьте готовность и активируйте интеграцию.", status: :see_other
  end
  def check
    if @configuration.check
      return_to_outlet("Проверка пройдена. Можно активировать интеграцию.", anchor: "iiko-step-4")
    else
      redirect_to "#{outlet_path}?tab=pos#iiko-step-4", alert: "Проверка не пройдена. Организация или терминальная группа недоступна в iiko. Проверьте настройки и повторите попытку.", status: :see_other
    end
  end
  def enable
    @configuration.enable
    return_to_outlet("Интеграция iiko активирована. QR-коды готовы к работе.", anchor: "iiko-step-4")
  end

  private
  def prepare_configuration
    @outlet = @merchant.merchant_outlets.find(params[:outlet_id])
    @configuration = Pos::Adapters::Iiko::Configuration.new(@outlet, user: current_user)
  end
  def outlet_path = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}"
  def pos_path = "#{outlet_path}/pos"
  def return_to_outlet(message, anchor: nil)
    target = "#{outlet_path}?tab=pos"
    target += "##{anchor}" if anchor
    redirect_to target, notice: message, status: :see_other
  end
end
