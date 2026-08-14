module Idempotency
  extend ActiveSupport::Concern

  WRITABLE_METHODS = %w[POST PATCH PUT].freeze
  TTL = 24.hours
  HEADER = "Idempotency-Key"
  CACHED_HEADERS = %w[
    Content-Type
    Location
    X-RateLimit-Bucket
    X-RateLimit-Limit
    X-RateLimit-Remaining
    X-RateLimit-Reset
  ].freeze

  included do
    around_action :wrap_in_idempotency
  end

  private
    def wrap_in_idempotency
      key = request.headers[HEADER]
      return yield unless key.present? && WRITABLE_METHODS.include?(request.method) && Current.api_token

      cache_key = idempotency_cache_key(key)
      body_hash = Digest::SHA256.hexdigest(request.raw_post.to_s)
      cached = read_idempotency_entry(cache_key)

      if cached
        if cached[:body_hash] != body_hash
          raise Api::Error::Conflict.new(
            "Idempotency-Key has already been used with a different request body.",
            details: { idempotency_key: key }
          )
        end

        replay_cached_response(cached)
        return
      end

      # `rescue_from` runs at the controller level, *outside* this around_action,
      # so any post-yield code is skipped when the action raises. To honor the
      # Stripe-style replay contract for 4xx responses, dispatch the rescue
      # handler ourselves, write the cache entry based on the rendered status,
      # then re-raise unhandled exceptions.
      begin
        yield
      rescue StandardError => error
        raise unless rescue_with_handler(error)
      end

      write_idempotency_entry(cache_key, body_hash) if response.status >= 200 && response.status < 500
    end

    def idempotency_cache_key(key)
      "idem:#{Current.api_token.account_id}:#{controller_path}##{action_name}:#{request.path}:#{key}"
    end

    def read_idempotency_entry(cache_key)
      Rails.cache.read(cache_key)
    rescue StandardError => error
      Rails.logger.warn("Idempotency cache read failed: #{error.class}: #{error.message}")
      nil
    end

    def write_idempotency_entry(cache_key, body_hash)
      return unless Current.api_token

      if response.body.is_a?(Enumerator) || response.headers["Transfer-Encoding"] == "chunked"
        Rails.logger.warn("Idempotency cache write skipped for streaming response")
        return
      end

      Rails.cache.write(
        cache_key,
        {
          status: response.status,
          body: response.body,
          headers: response.headers.slice(*CACHED_HEADERS),
          body_hash: body_hash,
          created_at: Time.current
        },
        expires_in: TTL
      )
    rescue StandardError => error
      Rails.logger.warn("Idempotency cache write failed: #{error.class}: #{error.message}")
    end

    def replay_cached_response(entry)
      entry[:headers].each { |name, value| response.set_header(name, value) }
      response.set_header("Idempotent-Replayed", "true")
      self.response_body = entry[:body]
      response.status = entry[:status]
    end
end
