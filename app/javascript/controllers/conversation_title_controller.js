import { Controller } from "@hotwired/stimulus"

// Handles click-to-edit for conversation titles in both the sidebar row
// and the conversation header. Enter or blur saves via PATCH; Escape
// reverts. The DOM is updated optimistically on save and rolled back on
// network error.
export default class extends Controller {
  static targets = ["text", "input"]
  static values  = { url: String }

  edit(event) {
    event.preventDefault()
    event.stopPropagation()
    this._previous = this.textTarget.textContent.trim()
    this.inputTarget.value = this._previous
    this.textTarget.hidden = true
    this.inputTarget.hidden = false
    this.inputTarget.select()
  }

  keydown(event) {
    if (event.key === "Enter")  { event.preventDefault(); this.inputTarget.blur() }
    if (event.key === "Escape") { this._reverting = true; this.inputTarget.blur() }
  }

  async save() {
    // Escape sets _reverting before triggering blur — revert and bail.
    if (this._reverting) {
      this._reverting = false
      this.textTarget.textContent = this._previous
      this._close()
      return
    }

    const value = this.inputTarget.value.trim()

    // Unchanged or blank — just close without saving.
    if (!value || value === this._previous) {
      this._close()
      return
    }

    // Optimistic update: show the new title immediately.
    this.textTarget.textContent = value
    this._close()

    try {
      const resp = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ title: value })
      })
      if (resp.ok) {
        this._previous = value
      } else {
        this.textTarget.textContent = this._previous
      }
    } catch {
      this.textTarget.textContent = this._previous
    }
  }

  _close() {
    this.inputTarget.hidden = true
    this.textTarget.hidden  = false
  }
}
