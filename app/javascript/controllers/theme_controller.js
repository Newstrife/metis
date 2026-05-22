import { Controller } from "@hotwired/stimulus"

// Flips the color scheme between light and dark. The no-flash script in
// the layout head applies the saved value on load; this persists changes.
// data-theme lives on <html>, which Turbo keeps across navigations.
export default class extends Controller {
  toggle() {
    const root = document.documentElement
    const next = root.dataset.theme === "dark" ? "light" : "dark"
    root.dataset.theme = next
    localStorage.setItem("metisTheme", next)
  }
}
