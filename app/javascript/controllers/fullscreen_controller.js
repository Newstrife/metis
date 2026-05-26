import { Controller } from "@hotwired/stimulus";

// Fullscreens a target element on click. ESC exits — browser default.
export default class extends Controller {
  static targets = ["frame"];

  enter() {
    this.frameTarget?.requestFullscreen?.();
  }
}
