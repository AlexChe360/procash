import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["launcher", "panel", "messages", "input", "send"]
  toggle() { this.panelTarget.hidden ? this.open() : this.close() }
  open() {
    this.panelTarget.hidden = false
    this.launcherTarget.setAttribute("aria-expanded", "true")
    this.inputTarget.focus()
  }
  close() {
    this.panelTarget.hidden = true
    this.launcherTarget.setAttribute("aria-expanded", "false")
    this.launcherTarget.focus()
  }
  disconnect() { this.request?.abort() }
  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      this.submit(event)
    }
  }
  suggest(event) {
    if (this.busy) return
    this.inputTarget.value = event.currentTarget.dataset.question
    this.submit(event)
  }
  message(text, kind) {
    const node = document.createElement("div")
    node.className = `assistant-message assistant-${kind}`
    node.textContent = text
    this.messagesTarget.append(node)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    return node
  }
  async submit(event) {
    event?.preventDefault()
    const question = this.inputTarget.value.trim()
    if (this.busy || question.length < 3 || question.length > 600) return
    this.busy = true
    this.sendTarget.disabled = true
    this.message(question, "question")
    this.inputTarget.value = ""
    const pending = this.message("Готовлю ответ…", "pending")
    this.request = new AbortController()
    const waiting = setTimeout(() => { pending.textContent = "Готовлю ответ… Это может занять около минуты." }, 18000)
    const timeout = setTimeout(() => this.request?.abort(), 80000)
    try {
      const response = await fetch("/assistant/messages", {
        method: "POST", credentials: "same-origin", signal: this.request.signal,
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ question })
      })
      if (response.status === 403 || response.status === 422) {
        pending.remove()
        this.message("Не удалось проверить запрос. Обновите страницу и отправьте вопрос ещё раз.", "error")
        return
      }
      const result = await response.json()
      pending.remove()
      const answer = this.message(result.answer || result.error || "Не удалось получить ответ. Откройте документацию.", response.ok ? "answer" : "error")
      if (typeof result.notice === "string" && result.notice) {
        const note = document.createElement("p")
        note.className = "assistant-important"
        note.textContent = result.notice
        answer.append(note)
      }
      if (Array.isArray(result.sources)) {
        const links = document.createElement("div")
        links.className = "assistant-sources"
        result.sources.forEach(source => {
          if (typeof source.url !== "string" || !/^\/documentation(?:#[a-z-]+)?$/.test(source.url)) return
          const link = document.createElement("a")
          link.href = source.url
          link.textContent = source.title
          links.append(link)
        })
        answer.append(links)
      }
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    } catch {
      pending.remove()
      this.message("Помощник сейчас не отвечает. Попробуйте позже или откройте документацию.", "error")
    } finally {
      clearTimeout(timeout)
      clearTimeout(waiting)
      this.busy = false
      this.sendTarget.disabled = false
      this.request = null
      if (!this.panelTarget.hidden) this.inputTarget.focus()
    }
  }
}
