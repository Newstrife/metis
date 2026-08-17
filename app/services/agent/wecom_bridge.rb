require "net/http"

module Agent
  # Minimal HTTP client for the local WeCom bridge daemon's /notify. Loopback
  # only, bearer from ENV; every failure mode degrades to `false` — a push
  # must never crash a turn or a webhook.
  module WecomBridge
    def self.configured?
      ENV["WECOM_BRIDGE_TOKEN"].present?
    end

    # payload: { chatid: "wr…" } or { to_userid: "…" }, plus content:.
    def self.push(payload)
      return false unless configured?

      Net::HTTP.post(uri, payload.to_json, headers).is_a?(Net::HTTPSuccess)
    rescue SystemCallError, SocketError
      false
    end

    def self.uri
      URI("http://127.0.0.1:#{ENV.fetch("WECOM_BRIDGE_PORT", 3201)}/notify")
    end

    def self.headers
      { "Authorization" => "Bearer #{ENV["WECOM_BRIDGE_TOKEN"]}", "Content-Type" => "application/json" }
    end
  end
end
