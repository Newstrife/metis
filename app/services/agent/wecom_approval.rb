module Agent
  # Pushes a high-risk approval request from a sandboxed turn to WeCom via
  # the local bridge (/notify). The agent never blocks mid-turn: it ends the
  # turn with "pending approval" and the operator answers in the chat — their
  # userid is the Operator identity Trust already recognizes.
  class WecomApproval
    def self.notify(conversation, params, poster: nil)
      new(conversation, params, poster:).notify
    end

    def initialize(conversation, params, poster: nil)
      @conversation = conversation
      @summary = params["summary"].to_s.strip.first(500)
      @requester = params["requester"].to_s.strip.first(64)
      @poster = poster || WecomBridge.method(:push)
    end

    def notify
      return { ok: false, error: "summary is required" } if @summary.blank?
      return { ok: false, error: "approval push is disabled" } unless Setting.get("security.approval_push")
      return { ok: false, error: "wecom bridge not configured" } unless WecomBridge.configured?

      delivered = []
      chatid = @conversation.settings["wecom_chatid"].presence
      delivered << "group" if chatid && @poster.call(chatid: chatid, content: card)
      owner_wecom = @conversation.user.wecom_userid.presence
      delivered << "operator_dm" if owner_wecom && @poster.call(to_userid: owner_wecom, content: card)

      if delivered.any?
        { ok: true, delivered_to: delivered }
      else
        { ok: false, error: "no reachable WeCom target for this conversation" }
      end
    end

    private

    def card
      from = @requester.presence || @conversation.user.wecom_userid.presence || "网页端"
      url = Rails.application.routes.url_helpers.conversation_url(
        @conversation, host: ENV.fetch("METIS_HOST", "127.0.0.1:3002"), protocol: "http"
      )
      <<~MD
        🚨 **高危操作待审批**

        **会话**: [#{@conversation.title}](#{url})
        **请求人**: #{from}
        **内容**: #{@summary}

        批准方式：Operator 直接在对话里回复批准指令即可，小百同学见到你的发言后才会执行。
      MD
    end
  end
end
