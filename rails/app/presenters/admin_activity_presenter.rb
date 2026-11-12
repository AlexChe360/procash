class AdminActivityPresenter
  attr_reader :days, :dates, :requests, :companies, :ceiling

  def initialize(period: nil, today: Date.current)
    @days = period.to_s == "7" ? 7 : 30
    @dates = ((today - days + 1)..today).to_a
    @requests = counts(ConnectionRequest)
    @companies = counts(Merchant)
    @ceiling = [requests.max, companies.max, 4].max.ceil(0)
  end

  def x(index) = (54 + index * 880.0 / (days - 1)).round(2)
  def y(value) = (222 - value * 184.0 / ceiling).round(2)
  def points(values) = values.each_with_index.map { |value, index| "#{x(index)},#{y(value)}" }.join(" ")
  def area(values) = "54,222 #{points(values)} 934,222"
  def ticks = (0..4).map { |index| (ceiling * index / 4.0).ceil }.uniq
  def label_indices = [0, (days - 1) / 3, (days - 1) * 2 / 3, days - 1].uniq

  private
  def counts(model)
    totals = model.where(created_at: dates.first.in_time_zone.beginning_of_day..dates.last.in_time_zone.end_of_day)
      .group(Arel.sql("DATE(created_at AT TIME ZONE 'Asia/Almaty')")).count
    dates.map { |date| totals.fetch(date, 0) }
  end
end
