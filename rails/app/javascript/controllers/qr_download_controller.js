import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "button", "status"]

  async download() {
    this.buttonTarget.disabled = true
    this.statusTarget.textContent = "Подготавливаем PNG…"
    let sourceUrl, downloadUrl
    try {
      const response = await fetch(this.imageTarget.src, { credentials: "same-origin" })
      if (!response.ok || !response.headers.get("content-type")?.includes("image/svg+xml")) throw new Error("SVG unavailable")
      sourceUrl = URL.createObjectURL(await response.blob())
      const image = new Image()
      await new Promise((resolve, reject) => {
        image.onload = resolve
        image.onerror = reject
        image.src = sourceUrl
      })
      const canvas = document.createElement("canvas")
      canvas.width = 1800
      canvas.height = 2250
      const context = canvas.getContext("2d")
      context.fillStyle = "#ffffff"
      context.fillRect(0, 0, canvas.width, canvas.height)
      context.drawImage(image, 0, 0, canvas.width, canvas.height)
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"))
      if (!blob) throw new Error("PNG unavailable")
      downloadUrl = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.href = downloadUrl
      link.download = this.imageTarget.dataset.filename
      document.body.append(link)
      link.click()
      link.remove()
      this.statusTarget.textContent = "PNG готов."
    } catch {
      this.statusTarget.textContent = "Не удалось подготовить PNG. Повторите попытку или откройте SVG."
    } finally {
      if (sourceUrl) URL.revokeObjectURL(sourceUrl)
      if (downloadUrl) setTimeout(() => URL.revokeObjectURL(downloadUrl), 10000)
      this.buttonTarget.disabled = false
    }
  }
}
