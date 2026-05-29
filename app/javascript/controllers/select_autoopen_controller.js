import { Controller } from "@hotwired/stimulus"

// Drop-in on the picker partial: once the loaded <select> mounts,
// open its dropdown so the user doesn't have to click twice (once
// to fetch the options, again to see them). showPicker() needs
// transient user activation — the original placeholder click keeps
// the activation valid for a couple seconds, long enough for the
// usual GitHub/Linear roundtrip. If activation has expired (very
// slow request) or the browser doesn't support showPicker (older
// Safari), we fall back to focusing the select so the keyboard path
// still works.
export default class extends Controller {
  connect() {
    const select = this.element.querySelector("select")
    if (!select) return

    select.focus()
    try {
      select.showPicker?.()
    } catch {
      // Outside the activation window or unsupported — focus is the fallback.
    }
  }
}
