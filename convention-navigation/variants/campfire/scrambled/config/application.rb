require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Campfire
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.2

    # Source layout.
    #
    # Application code is organised by deployment concern rather than by the
    # framework's default app/ tree: platform/ holds code that runs regardless
    # of how a request arrived, delivery/ holds the parts tied to a transport.
    # Rails is told where each moved tree now lives.
    #
    # These assignments come before anything that appends to autoload_paths or
    # eager_load_paths. Both of those memoize from config.paths the first time
    # they are read, so a path reassigned afterwards is silently ignored.
    config.paths["app/views"] = "delivery/http/render"
    config.paths["app/helpers"] = "delivery/http/render_support"
    config.paths["db/migrate"] = "db/changes"

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks rails_ext])

    # Rails derives autoload roots from the app/ directory, including the
    # per-layer concerns/ directories. Nothing derives them once the layers live
    # elsewhere, so each root is registered by hand. A concerns/ directory left
    # unregistered does not fail loudly: Zeitwerk simply reads it as a namespace
    # and every constant inside it moves under Concerns::.
    %w[
      platform/core/entities
      platform/core/entities/concerns
      delivery/http/handlers
      delivery/http/handlers/concerns
      delivery/http/render_support
      platform/async/workers
      delivery/sockets
      delivery/sockets/concerns
    ].each do |relative|
      absolute = config.root.join(relative).to_s
      config.autoload_paths << absolute
      config.eager_load_paths << absolute
    end

    # Fallback to English if translation key is missing
    config.i18n.fallbacks = true
  end
end
