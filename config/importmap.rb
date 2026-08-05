# Pin npm packages by running ./bin/importmap

pin "application"
pin "frame_missing"
pin "native_haptics"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Chart.js (vendored ESM build — dist/chart.js with its helpers chunk and the
# @kurkle/color dep) for inline chart blocks in assistant messages.
pin "chart.js", to: "chart.js"
pin "chart.js/helpers", to: "chunks/helpers.dataset.js"
pin "@kurkle/color", to: "kurkle-color.js"
pin_all_from "app/javascript/controllers", under: "controllers"
