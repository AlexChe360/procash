require "test_helper"
class QrRendererTest < ActiveSupport::TestCase
  test "custom palette changes accents without changing QR modules or accepting markup" do
    original = Qr::Renderer.call("https://example.test/t/1", "Стол 1")
    custom = Qr::Renderer.call("https://example.test/t/1", "Стол 1", color: "#8b5cf6")
    assert_includes custom, 'fill="#8B5CF6"'
    assert_includes custom, 'fill="#111"'
    assert_includes custom, 'fill="#fff"'
    assert_equal original[/<path d="([^"]+)"/, 1], custom[/<path d="([^"]+)"/, 1]
    assert_equal original, Qr::Renderer.call("https://example.test/t/1", "Стол 1", color: '"><script>bad</script>')
  end
  test "branded QR preserves URL and escapes table labels" do
    url = "https://example.test/t/11111111-2222-4333-8444-555555555555"
    svg = Qr::Renderer.call(url, '<script>alert("x")</script>')
    document = Nokogiri::XML(svg)
    assert_empty document.errors
    assert_empty document.xpath("//*[local-name()='script']")
    assert_includes svg, "&lt;script&gt;"
    assert_includes svg, 'width="60mm"'
    assert_includes svg, 'height="75mm"'
    assert_includes svg, "Powered by ProCash"
    assert document.at_xpath("//*[local-name()='path']")["d"].start_with?("M")
  end
end
