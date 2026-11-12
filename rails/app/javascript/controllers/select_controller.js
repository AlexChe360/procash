import { Controller } from "@hotwired/stimulus"

// Keep the original select as the form value and as a no-JavaScript fallback.
export default class extends Controller {
  static targets = ["native", "enhanced", "trigger", "text", "panel", "search", "list", "empty"]

  connect() {
    this.labels = Array.from(this.nativeTarget.labels || [])
    this.triggerTarget.id = `${this.nativeTarget.id}-trigger`
    this.labels.forEach(label => { label.htmlFor = this.triggerTarget.id })
    this.listTarget.id = `${this.nativeTarget.id}-listbox`
    this.triggerTarget.setAttribute("aria-controls", this.listTarget.id)
    this.triggerTarget.setAttribute("aria-required", String(this.nativeTarget.required))
    this.searchTarget.setAttribute("aria-controls", this.listTarget.id)
    this.searchTarget.setAttribute("role", "combobox")
    this.searchTarget.setAttribute("aria-autocomplete", "list")
    this.searchTarget.setAttribute("aria-expanded", "false")
    this.nativeTarget.hidden = true
    this.enhancedTarget.hidden = false
    this.sync()
  }

  disconnect() {
    this.reset()
    this.nativeTarget.hidden = false
    this.enhancedTarget.hidden = true
    this.labels?.forEach(label => { label.htmlFor = this.nativeTarget.id })
  }

  toggle() { this.panelTarget.hidden ? this.open() : this.close() }

  open() {
    if (this.nativeTarget.disabled) return
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.searchTarget.setAttribute("aria-expanded", "true")
    this.searchTarget.value = ""
    this.filter()
    this.searchTarget.focus()
    this.position()
    this.highlight(this.activeIndex)
  }

  close(focus = false) {
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.searchTarget.setAttribute("aria-expanded", "false")
    this.searchTarget.removeAttribute("aria-activedescendant")
    if (focus) this.triggerTarget.focus()
  }

  reset() { this.close() }
  outside(event) { if (!this.element.contains(event.target)) this.close() }

  sync() {
    const option = this.nativeTarget.selectedOptions[0]
    this.textTarget.textContent = option?.textContent || "Выберите значение"
    this.triggerTarget.classList.toggle("is-placeholder", !this.nativeTarget.value)
    this.triggerTarget.disabled = this.nativeTarget.disabled
    this.triggerTarget.removeAttribute("aria-invalid")
    if (!this.panelTarget.hidden) this.filter()
  }

  invalid(event) {
    event.preventDefault()
    this.triggerTarget.setAttribute("aria-invalid", "true")
    this.open()
  }

  filter() {
    const words = this.searchTarget.value.trim().toLocaleLowerCase("ru").split(/\s+/).filter(Boolean)
    this.options = Array.from(this.nativeTarget.options).filter(option => option.value && !option.disabled && words.every(word => option.textContent.toLocaleLowerCase("ru").includes(word)))
    this.listTarget.replaceChildren()
    let group = null
    this.options.forEach((option, index) => {
      const section = option.dataset.group
      if (section && section !== group) {
        const heading = document.createElement("div")
        heading.className = "pc-select-group"
        heading.setAttribute("role", "presentation")
        heading.textContent = section
        this.listTarget.append(heading)
        group = section
      }
      const row = document.createElement("div")
      row.className = "pc-select-option"
      row.id = `${this.listTarget.id}-${index}`
      row.setAttribute("role", "option")
      row.setAttribute("aria-selected", String(option.selected))
      const text = document.createElement("span")
      const prefix = section ? `${section} · ` : ""
      text.textContent = prefix && option.textContent.startsWith(prefix) ? option.textContent.slice(prefix.length) : option.textContent
      const check = document.createElement("span")
      check.className = "pc-select-check"
      check.setAttribute("aria-hidden", "true")
      check.textContent = option.selected ? "✓" : ""
      row.append(text, check)
      row.addEventListener("mousedown", event => event.preventDefault())
      row.addEventListener("click", () => this.choose(index))
      row.addEventListener("mouseenter", () => this.highlight(index, false))
      this.listTarget.append(row)
    })
    this.emptyTarget.hidden = this.options.length > 0
    this.activeIndex = Math.max(0, this.options.findIndex(option => option.selected))
    this.highlight(this.activeIndex)
  }

  highlight(index, scroll = true) {
    this.activeIndex = index
    const rows = this.listTarget.querySelectorAll('[role="option"]')
    rows.forEach((row, item) => row.classList.toggle("is-highlighted", item === index))
    const row = rows[index]
    if (row) {
      this.searchTarget.setAttribute("aria-activedescendant", row.id)
      if (scroll) {
        const viewport = this.listTarget.getBoundingClientRect()
        const bounds = row.getBoundingClientRect()
        if (bounds.top < viewport.top) this.listTarget.scrollTop -= viewport.top - bounds.top
        if (bounds.bottom > viewport.bottom) this.listTarget.scrollTop += bounds.bottom - viewport.bottom
      }
    } else this.searchTarget.removeAttribute("aria-activedescendant")
  }

  choose(index) {
    const option = this.options[index]
    if (!option) return
    this.nativeTarget.value = option.value
    this.nativeTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.close(true)
  }

  keydown(event) {
    if (this.panelTarget.hidden) {
      if (event.target === this.triggerTarget && ["ArrowDown", "ArrowUp"].includes(event.key)) {
        event.preventDefault()
        this.open()
      }
      return
    }
    if (event.key === "Escape") { event.preventDefault(); this.close(true) }
    else if (event.key === "Tab") this.close()
    else if (["ArrowDown", "ArrowUp"].includes(event.key)) {
      event.preventDefault()
      if (this.options.length) this.highlight((this.activeIndex + (event.key === "ArrowDown" ? 1 : -1) + this.options.length) % this.options.length)
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.choose(this.activeIndex)
    }
  }

  position() {
    const trigger = this.triggerTarget.getBoundingClientRect()
    const availableBelow = window.innerHeight - trigger.bottom
    const availableAbove = trigger.top
    const above = availableBelow < 240 && availableAbove > availableBelow
    this.element.classList.toggle("opens-above", above)
    const available = above ? availableAbove : availableBelow
    this.listTarget.style.maxHeight = `${Math.max(80, Math.min(240, available - 125))}px`
  }
}
