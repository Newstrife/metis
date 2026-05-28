import { Controller } from "@hotwired/stimulus"

// Slash-command palette over the composer textarea. Lists installed
// skills (team + built-in) the operator can trigger by name.
//
// Open: type `/` at the start of an empty composer.
// Filter: keep typing — the popup narrows by slug substring.
// Pick: ↑ ↓ navigate, Enter or Tab inserts `/<slug> ` and closes.
// Dismiss: Esc, click outside, or Backspace past the leading `/`.
//
// The popup is purely a discovery affordance — the chat message is
// sent verbatim; AGENTS.md teaches the agent to interpret a leading
// `/<slug>` as a trigger for that skill.
export default class extends Controller {
  static values = { skills: { type: Array, default: [] } }
  static targets = ["popup", "textarea"]

  get textarea() {
    return this.hasTextareaTarget ? this.textareaTarget : this.element.querySelector("textarea")
  }

  connect() {
    this._open = false
    this._activeIndex = 0
    this._filtered = []
    this._docClick = (e) => { if (!this.element.contains(e.target)) this._close() }
    document.addEventListener("click", this._docClick)
  }

  disconnect() {
    document.removeEventListener("click", this._docClick)
  }

  onInput() {
    const value = this.textarea.value
    if (value.startsWith("/")) {
      const query = value.slice(1).split(/\s/, 1)[0].toLowerCase()
      // Close once a space is typed — the slug has been chosen, the rest is the ask.
      if (/\s/.test(value)) { this._close(); return }
      this._filter(query)
      this._open ? this._render() : this._show()
    } else {
      this._close()
    }
  }

  onKeydown(event) {
    if (!this._open) return
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this._move(1); this._render(); return
      case "ArrowUp":
        event.preventDefault()
        this._move(-1); this._render(); return
      case "Enter":
      case "Tab":
        if (this._filtered.length === 0) return
        event.preventDefault()
        event.stopPropagation()
        this._pick(this._filtered[this._activeIndex])
        return
      case "Escape":
        event.preventDefault()
        this._close()
    }
  }

  pickFromClick(event) {
    const slug = event.currentTarget.dataset.slug
    const entry = this.skillsValue.find((s) => s.slug === slug)
    if (entry) this._pick(entry)
  }

  // ── private ──────────────────────────────────────────────────────────────

  _filter(query) {
    this._filtered = query
      ? this.skillsValue.filter((s) => s.slug.toLowerCase().includes(query))
      : this.skillsValue.slice()
    this._activeIndex = 0
  }

  _show() {
    if (!this.popupTarget) return
    this._open = true
    this.popupTarget.hidden = false
    this._render()
  }

  _close() {
    if (!this._open) return
    this._open = false
    if (this.popupTarget) this.popupTarget.hidden = true
  }

  _move(delta) {
    const n = this._filtered.length
    if (n === 0) return
    this._activeIndex = (this._activeIndex + delta + n) % n
  }

  _render() {
    if (this._filtered.length === 0) { this._close(); return }
    this.popupTarget.innerHTML = this._filtered.map((s, i) => `
      <button type="button" class="skill-palette-row ${i === this._activeIndex ? "is-active" : ""}"
              data-slug="${this._escape(s.slug)}"
              data-action="mousedown->skill-palette#pickFromClick">
        <div class="skill-palette-name">
          /${this._escape(s.slug)}
          <span class="skill-palette-source">${s.source === "builtin" ? "built-in" : "team"}</span>
        </div>
        <div class="skill-palette-desc">${this._escape(s.description || "")}</div>
      </button>
    `).join("")
  }

  _pick(entry) {
    const value = this.textarea.value
    // Replace the partial `/foo` token with `/<slug> ` so the user can keep typing.
    const inserted = `/${entry.slug} `
    this.textarea.value = value.replace(/^\/[^\s]*/, inserted)
    this._close()
    this.textarea.focus()
    // Position the cursor just after the inserted slug.
    const pos = inserted.length
    this.textarea.setSelectionRange(pos, pos)
    // Re-trigger autoResize via the existing composer controller's listener.
    this.textarea.dispatchEvent(new Event("input", { bubbles: true }))
  }

  _escape(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
    }[c]))
  }
}
