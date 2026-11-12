import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["input", "section", "link", "status"]
  connect() {
    this.filter()
  }
  filter() {
    const words = this.inputTarget.value.trim().toLocaleLowerCase("ru").split(/\s+/).filter(Boolean)
    let count = 0
    this.sectionTargets.forEach(section => {
      const text = section.textContent.toLocaleLowerCase("ru")
      const match = words.every(word => text.includes(word))
      section.hidden = !match
      if (match) count++
      this.linkTargets.filter(link => link.getAttribute("href") === `#${section.id}`).forEach(link => { link.hidden = !match })
    })
    this.statusTarget.hidden = count > 0
    this.statusTarget.textContent = count ? "" : "Ничего не найдено. Попробуйте другой запрос или очистите поиск."
  }
}
