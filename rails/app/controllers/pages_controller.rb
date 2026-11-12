class PagesController < ApplicationController
  def home
    render layout: false
  end
  def health
    ActiveRecord::Base.connection.select_value("SELECT 1")
    render plain: "ok"
  rescue ActiveRecord::ActiveRecordError
    render plain: "unavailable", status: :service_unavailable
  end
end
