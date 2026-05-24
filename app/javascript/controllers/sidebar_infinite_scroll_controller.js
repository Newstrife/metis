import { Controller } from "@hotwired/stimulus"

// Endless scrolling for the sidebar conversation list.
//
// The sentinel is rendered at the bottom of the `.convos` scroll
// container whenever there's a next page. When it intersects the
// viewport (a bit before, via rootMargin), we fetch the next page as
// a turbo_stream and let Turbo apply it — the response appends rows
// into the right recency-bucket and replaces this sentinel with a
// fresh one (or an empty hidden div when the list is exhausted).
//
// Re-connecting on each replacement is automatic: Stimulus re-runs
// `connect()` for the newly-inserted sentinel, so the observer wires
// itself up again until there's no next page.
export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue) return

    const root = this.element.closest(".convos")
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) this.load()
      },
      { root: root || null, rootMargin: "200px" }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  async load() {
    if (this.loading) return
    this.loading = true
    // One-shot: stop observing immediately so a quick scroll doesn't
    // fire the same fetch twice while it's in flight.
    this.observer?.disconnect()

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (!response.ok) return
      const stream = await response.text()
      window.Turbo.renderStreamMessage(stream)
    } catch (_error) {
      // Network blip — leave the (now disconnected) sentinel in place;
      // the user can scroll again to try later if it ever reconnects.
    } finally {
      this.loading = false
    }
  }
}
