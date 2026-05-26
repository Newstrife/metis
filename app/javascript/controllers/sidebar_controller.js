import { Controller } from "@hotwired/stimulus"

// Mobile sidebar drawer toggle. On wide viewports the sidebar is
// always visible (CSS), so open/close are visual no-ops there. We
// auto-close when the #main turbo-frame swaps (tapping a conversation)
// so the user lands on the picked chat without having to dismiss
// the drawer first.
export default class extends Controller {
  connect() {
    this._onFrameLoad = (event) => {
      if (event.target?.id === "main") this.close()
    }
    document.addEventListener("turbo:frame-load", this._onFrameLoad)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this._onFrameLoad)
    document.body.classList.remove("drawer-open")
  }

  toggle() {
    this.element.classList.contains("sidebar-open") ? this.close() : this.open()
  }
  open() {
    this.element.classList.add("sidebar-open")
    document.body.classList.add("drawer-open")
  }
  close() {
    this.element.classList.remove("sidebar-open")
    document.body.classList.remove("drawer-open")
  }
}
