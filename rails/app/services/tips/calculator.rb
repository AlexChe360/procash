require "bigdecimal"

module Tips
  class Calculator
    MAX = BigDecimal("79228162514264337593543950335")
    def initialize(enabled: false, percentages: [5, 10, 15], custom: false)
      @enabled, @percentages, @custom = enabled, percentages, custom
    end

    def percentage(amount_due, percentage)
      amount = decimal(amount_due)
      raise ArgumentError, "Invalid amount" if amount.negative?
      unless percentage.is_a?(Integer) && (percentage == 0 || (@enabled && (1..100).cover?(percentage) && @percentages.include?(percentage)))
        raise ArgumentError, "Percentage not allowed"
      end
      result(amount, (amount * percentage / 100).round(2, BigDecimal::ROUND_HALF_UP))
    end

    def custom(amount_due, input)
      raise ArgumentError, "Custom tips not allowed" unless @enabled && @custom
      amount = decimal(amount_due)
      text = input.to_s.strip.tr(",", ".")
      raise ArgumentError, "Invalid amount" unless amount.positive? && text.bytesize <= 32 && text.match?(/\A(?:\d+(?:\.\d*)?|\.\d+)\z/)
      tip = decimal(text)
      raise ArgumentError, "Too many decimal places" unless tip.round(2) == tip
      raise ArgumentError, "Tip exceeds balance" if tip > amount
      result(amount, tip)
    end

    private

    def decimal(value)
      raise ArgumentError, "Use decimal values, not Float" if value.is_a?(Float)
      number = BigDecimal(value.to_s)
      raise ArgumentError, "Invalid decimal" unless number.finite? && number.abs <= MAX
      number
    end

    def result(amount, tip)
      total = amount + tip
      raise ArgumentError, "Arithmetic overflow" if total > MAX
      { tip_amount: tip, total_amount: total }
    end
  end
end
