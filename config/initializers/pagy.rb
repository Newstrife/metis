# frozen_string_literal: true

# Pagy 43+ has near-zero required setup: paginators and helpers are
# autoloaded on first use. We just load the gem here so `Pagy::Method`
# is available where ApplicationController includes it.
#
# Per-page limits are passed explicitly at the call site
# (see ApplicationController#set_sidebar).
require "pagy"
