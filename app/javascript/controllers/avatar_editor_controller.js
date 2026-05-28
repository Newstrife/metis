import { Controller } from "@hotwired/stimulus"

// Click-to-upload + hover-X-to-remove avatar widget. Uploads happen
// immediately on file select via PATCH /profile/avatar; the response
// is a turbo-stream that swaps this widget and the sidebar back in.
export default class extends Controller {
  static targets = ["input"]
  static values  = { url: String }

  upload() {
    const file = this.inputTarget.files[0]
    if (!file) return

    const body = new FormData()
    body.append("user[avatar]", file)
    this.#submit(body)
    // Reset so selecting the same file twice still fires `change`.
    this.inputTarget.value = ""
  }

  remove() {
    const body = new FormData()
    body.append("user[remove_avatar]", "1")
    this.#submit(body)
  }

  async #submit(body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    body.append("_method", "patch")
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token || ""
      },
      body,
      credentials: "same-origin"
    })
    const html = await response.text()
    Turbo.renderStreamMessage(html)
  }
}
