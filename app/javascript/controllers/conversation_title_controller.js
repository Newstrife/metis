import { Controller } from "@hotwired/stimulus"

// Click-to-edit for the conversation title in the header. Enter saves,
// Escape or blur-without-change cancels. The DOM is updated only after
// the server confirms — no rollback path, no flicker.
export default class extends Controller {
  static targets = ["text", "input"]
  static values  = { url: String }

  connect() {
    this._syncDocumentTitle()
    this._titleObserver = new MutationObserver(() => this._syncDocumentTitle())
    this._titleObserver.observe(this.textTarget, { childList: true, characterData: true, subtree: true })
  }

  disconnect() {
    this._titleObserver?.disconnect()
  }

  _syncDocumentTitle() {
    document.title = this.textTarget.textContent.trim() || "Metis"
  }

  edit() {
    this._previous = this.textTarget.textContent.trim()
    this.inputTarget.value = this._previous
    this.textTarget.hidden = true
    this.inputTarget.hidden = false
    this.inputTarget.select()
  }

  keydown(event) {
    if (event.key === "Enter")  { event.preventDefault(); this.save() }
    if (event.key === "Escape") { event.preventDefault(); this.cancel() }
  }

  cancel() {
    this.inputTarget.hidden = true
    this.textTarget.hidden  = false
  }

  async save() {
    // Cancel hides the input, which fires blur → save. Bail to avoid
    // saving the in-progress value the user wanted to discard.
    if (this.inputTarget.hidden) return

    const value = this.inputTarget.value.trim()
    if (!value || value === this._previous) { this.cancel(); return }

    try {
      const resp = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        },
        body: JSON.stringify({ title: value })
      })
      if (resp.ok) {
        this.textTarget.textContent = value
        this._previous = value
      }
    } catch {
      // Server didn't accept it — leave the displayed title alone.
    } finally {
      this.cancel()
    }
  }
}
