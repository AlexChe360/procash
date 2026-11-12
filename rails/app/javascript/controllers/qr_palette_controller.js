import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["enabled", "picker", "hex", "preview", "svg", "print", "savedColor"]
  connect() { this.refresh() }
  toggle() { this.refresh() }
  pick() {
    this.enabledTarget.checked = true
    this.hexTarget.value = this.pickerTarget.value.toUpperCase()
    this.refresh()
  }
  hex() {
    if (!/^#[0-9a-f]{6}$/i.test(this.hexTarget.value)) return
    this.pickerTarget.value = this.hexTarget.value
    this.enabledTarget.checked = true
    this.refresh()
  }
  swatch(event) {
    this.pickerTarget.value = event.currentTarget.dataset.color
    this.pick()
  }
  refresh() {
    const active = this.enabledTarget.checked
    const color = this.pickerTarget.value.toUpperCase()
    this.hexTarget.disabled = !active
    this.savedColorTargets.forEach(input => { input.value = active ? color : "" })
    this.element.querySelectorAll('input[type="hidden"][name="color"]').forEach(input => { input.value = active ? color : "" })
    ;[this.previewTarget, this.svgTarget, ...this.printTargets].forEach(element => {
      const attribute = element.tagName === "IMG" ? "src" : "href"
      const url = new URL(element.getAttribute(attribute), window.location.href)
      if (active) url.searchParams.set("color", color)
      else url.searchParams.delete("color")
      if (element.getAttribute(attribute) !== url.href) element.setAttribute(attribute, url.href)
    })
    this.element.querySelectorAll(".qr-color-swatch").forEach(button => {
      button.setAttribute("aria-pressed", String(active && button.dataset.color.toUpperCase() === color))
    })
  }
}
