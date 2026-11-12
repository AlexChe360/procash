require "rqrcode"
require "erb"
require "base64"
module Qr
  class Renderer
    DESIGNS = { "classic" => "Классический", "mint" => "Мятный", "blue" => "Синий" }.freeze
    def self.color(value)
      value.to_s.match?(/\A#[0-9a-fA-F]{6}\z/) ? value.upcase : nil
    end
    def self.tint(color, white)
      channels = color.delete_prefix("#").scan(/../).map { |hex| hex.to_i(16) }
      "#" + channels.map { |channel| (channel + (255 - channel) * white).round.to_s(16).rjust(2, "0") }.join.upcase
    end
    def self.call(url, table_name, design: nil, logo: nil, color: nil)
      code = RQRCode::QRCode.new(url, level: :m)
      path = code.modules.each_with_index.flat_map { |row, y| row.each_with_index.filter_map { |dark, x| "M#{x},#{y}h1v1h-1z" if dark } }.join
      scale = 388.0 / (code.modules.length + 8)
      x, y = 106 + 4 * scale, 256 + 4 * scale
      name = ERB::Util.html_escape(table_name)
      svg = <<~SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="60mm" height="75mm" viewBox="0 0 600 750">
        <rect width="600" height="750" rx="28" fill="#fff"/>
        <rect x="6" y="6" width="588" height="738" rx="22" fill="none" stroke="#E9E6E2" stroke-width="2"/>
        <g font-family="Inter,Arial,sans-serif"><text x="64" y="78" font-size="38" font-weight="800" fill="#1E1E1E">Pro</text><text x="132" y="78" font-size="38" font-weight="800" fill="#E66353">Cash</text>
        <text x="64" y="104" font-size="12" font-weight="700" letter-spacing="1.8" fill="#B8B0A8">QR ДЛЯ ОПЛАТЫ</text>
        <text x="64" y="148" font-size="28" font-weight="800" fill="#1E1E1E">#{name}</text>
        <text x="64" y="178" font-size="14" fill="#7C7C7C">Отсканируйте, чтобы открыть счёт</text></g>
        <rect x="64" y="214" width="472" height="472" rx="24" fill="#FCFBFA" stroke="#ECE7E2" stroke-width="2"/>
        <rect x="106" y="256" width="388" height="388" fill="#fff"/>
        <g transform="translate(#{x.round(6)} #{y.round(6)}) scale(#{scale.round(6)})" shape-rendering="crispEdges"><path d="#{path}" fill="#111"/></g>
        <text x="300" y="716" text-anchor="middle" font-family="Inter,Arial,sans-serif" font-size="14" fill="#7C7C7C">Powered by ProCash</text>
        </svg>
      SVG
      if logo.present?
        svg.sub!(%r{<text x="64" y="78".*?</text><text x="132" y="78".*?</text>}, "<image x=\"64\" y=\"28\" width=\"220\" height=\"58\" preserveAspectRatio=\"xMinYMid meet\" href=\"data:image/png;base64,#{Base64.strict_encode64(logo)}\"/>")
      end
      palette = case design
      when "mint" then { "#E66353" => "#16A365", "#E9E6E2" => "#D7E8DE", "#FCFBFA" => "#F3FAF5", "#ECE7E2" => "#DCEDE1", "#B8B0A8" => "#799888" }
      when "blue" then { "#E66353" => "#466DD8", "#E9E6E2" => "#DCE3F2", "#FCFBFA" => "#F5F7FC", "#ECE7E2" => "#DFE6F5", "#B8B0A8" => "#8799BA" }
      else {}
      end
      if (accent = self.color(color))
        palette = { "#E66353" => accent, "#E9E6E2" => tint(accent, 0.82), "#FCFBFA" => tint(accent, 0.96), "#ECE7E2" => tint(accent, 0.86), "#B8B0A8" => "#7C7C7C" }
      end
      svg.gsub(/#[0-9A-Fa-f]{6}/) { |color| palette.fetch(color, color) }
    end
  end
end
