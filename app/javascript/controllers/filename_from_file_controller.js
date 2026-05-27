import { Controller } from "@hotwired/stimulus"

// Auto-fills a filename input from a paired file picker when the
// filename field is blank — so the common case ("upload style.md
// and save it as style.md") needs zero typing. Editing the filename
// or picking a different file later doesn't get clobbered: once the
// user touches the filename input we leave it alone.
export default class extends Controller {
  static targets = ["filename", "file"]

  connect() {
    this._userEdited = false
  }

  filenameChanged() {
    this._userEdited = this.filenameTarget.value.length > 0
  }

  filePicked() {
    if (this._userEdited && this.filenameTarget.value.length > 0) return
    const picked = this.fileTarget.files[0]
    if (!picked) return
    this.filenameTarget.value = picked.name
  }
}
