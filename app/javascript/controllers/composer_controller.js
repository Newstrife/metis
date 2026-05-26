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
//
// 3. Auto-resize — grows with content up to MAX_HEIGHT_PX, then scrolls.
//    Resets to the natural `rows` size on form reset (post-submit).
const MAX_HEIGHT_PX = 200

export default class extends Controller {
  connect() {
    this._focusIfIdle()
    this._streamRenderHandler = this._handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this._streamRenderHandler)
    this._resetHandler = () => this._resetSize()
    this.element.form?.addEventListener("reset", this._resetHandler)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._streamRenderHandler)
    this.element.form?.removeEventListener("reset", this._resetHandler)
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    const form = this.element.form
    if (this._streaming(form)) return

    form.requestSubmit()
  }

  autoResize() {
    this.element.style.height = "auto"
    this.element.style.height = Math.min(this.element.scrollHeight, MAX_HEIGHT_PX) + "px"
  }

  // ── private ──────────────────────────────────────────────────────────────

  _resetSize() {
    this.element.style.height = ""
  }

  _handleStreamRender(event) {
    const stream = event.detail?.newStream || event.target
    if (stream?.getAttribute("target") !== "composer_actions") return

    // Intercept the render to focus *after* the DOM has updated.
    // requestAnimationFrame here would fire too early (before the stream mutates the DOM).
    const fallbackRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await fallbackRender(streamElement)
      this._focusIfIdle()
    }
  }

  _focusIfIdle() {
    if (window.matchMedia("(pointer: coarse)").matches) return
    if (this._streaming(this.element.form)) return

    // Only treat focus on another *editable* element as a reason to bail —
    // a clicked link/button (e.g. sidebar "New chat") is not the user
    // typing somewhere else, so we should still grab focus.
    const active = document.activeElement
    if (active && active !== this.element && active.matches?.("input, textarea, select, [contenteditable=true]")) return

    // Don't steal focus if the user has highlighted text to copy/read
    if (!window.getSelection()?.isCollapsed) return

    this.element.focus()
  }

  _streaming(form) {
    return form?.querySelector("#composer_actions")?.dataset.composerState === "streaming"
  }
}
