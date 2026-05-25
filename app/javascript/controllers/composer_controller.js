import { Controller } from "@hotwired/stimulus"

// The message composer textarea:
//
// 1. Submit on Enter — Enter sends, Shift+Enter inserts a newline.
//    Enter is ignored mid-IME-composition (so confirming a
//    Chinese/Japanese candidate doesn't send) and while a turn streams.
//
// 2. Auto-focus — on initial load, Turbo Drive navigation, and after a
//    streaming turn ends. Skipped on touch-primary devices and when the
//    user is focused on something else (so we don't steal a selection).
export default class extends Controller {
  connect() {
    this._focusIfIdle()
    this._streamRenderHandler = this._handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this._streamRenderHandler)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._streamRenderHandler)
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    const form = this.element.form
    if (this._streaming(form)) return

    form.requestSubmit()
  }

  // ── private ──────────────────────────────────────────────────────────────

  _handleStreamRender(event) {
    const stream = event.detail?.newStream
    if (stream?.getAttribute("target") !== "composer_actions") return

    requestAnimationFrame(() => this._focusIfIdle())
  }

  _focusIfIdle() {
    if (window.matchMedia("(pointer: coarse)").matches) return
    if (this._streaming(this.element.closest("form"))) return

    const active = document.activeElement
    if (active && active !== document.body && active !== this.element) return

    this.element.focus()
  }

  _streaming(form) {
    return form?.querySelector("#composer_actions")?.dataset.composerState === "streaming"
  }
}
