import { Controller } from "@hotwired/stimulus";

// Shows the field group that matches the selected transport (stdio/http).
export default class extends Controller {
  static targets = ["transport", "stdio", "http"];

  connect() {
    this.switch();
  }

  switch() {
    const transport = this.transportTarget.value;
    this.stdioTarget.hidden = transport !== "stdio";
    this.httpTarget.hidden = transport !== "http";
  }
}
