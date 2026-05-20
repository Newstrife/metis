import { Controller } from "@hotwired/stimulus"

// Manages photo/file attachments in the message composer: accumulates
// picked and dropped files, renders removable previews, and keeps the
// file input's FileList in sync (via DataTransfer) so the form submits
// exactly what the previews show.
export default class extends Controller {
  static targets = ["input", "previews"]

  connect() {
    this.transfer = new DataTransfer();
  }

  disconnect() {
    this.revokeObjectUrls();
  }

  filesPicked() {
    for (const file of this.inputTarget.files) {
      this.transfer.items.add(file);
    }
    this.sync();
  }

  dragOver(event) {
    event.preventDefault();
    this.element.classList.add("ring-2", "ring-gray-400");
  }

  dragLeave(event) {
    event.preventDefault();
    this.element.classList.remove("ring-2", "ring-gray-400");
  }

  drop(event) {
    event.preventDefault();
    this.element.classList.remove("ring-2", "ring-gray-400");
    for (const file of event.dataTransfer.files) {
      this.transfer.items.add(file);
    }
    this.sync();
  }

  remove(event) {
    const index = Number(event.params.index);
    const kept = new DataTransfer();
    Array.from(this.transfer.files).forEach((file, i) => {
      if (i !== index) kept.items.add(file);
    });
    this.transfer = kept;
    this.sync();
  }

  // Push the accumulated files back onto the input and repaint previews.
  sync() {
    this.inputTarget.files = this.transfer.files;
    this.render();
  }

  render() {
    this.revokeObjectUrls();
    const chips = Array.from(this.transfer.files).map((file, i) => this.chip(file, i));
    this.previewsTarget.replaceChildren(...chips);
  }

  chip(file, index) {
    const chip = document.createElement("div");
    chip.className =
      "flex items-center gap-2 rounded-md border border-gray-200 bg-gray-50 px-2 py-1 text-xs";

    if (file.type.startsWith("image/")) {
      const img = document.createElement("img");
      img.src = URL.createObjectURL(file);
      img.dataset.objectUrl = "true";
      img.className = "h-10 w-10 rounded object-cover";
      chip.appendChild(img);
    } else {
      const name = document.createElement("span");
      name.className = "max-w-[12rem] truncate font-medium text-gray-700";
      name.textContent = file.name;
      chip.appendChild(name);
    }

    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "×";
    remove.className = "text-base leading-none text-gray-400 hover:text-gray-700";
    remove.dataset.action = "file-upload#remove";
    remove.dataset.fileUploadIndexParam = index;
    chip.appendChild(remove);

    return chip;
  }

  revokeObjectUrls() {
    this.previewsTarget
      .querySelectorAll("img[data-object-url]")
      .forEach((img) => URL.revokeObjectURL(img.src));
  }
}
