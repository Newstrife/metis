import { Controller } from "@hotwired/stimulus"

// Fires once per page-load for users who haven't picked a timezone:
// posts the browser's IANA zone to /profile/detect_timezone so the
// next page-load can render timestamps in the user's wall clock
// without making them open settings first.
//
// The endpoint is idempotent and no-ops once a timezone is set, so
// late-arriving Turbo navigations re-running this hook are cheap.
export default class extends Controller {
  static values = { url: String }

  connect() {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!tz) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": token || "",
        "Accept": "text/plain"
      },
      body: `timezone=${encodeURIComponent(tz)}`
    }).catch(() => {})
  }
}
