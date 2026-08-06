module Api
  module Wecom
    # Inbound channel for the WeCom intelligent-robot bridge daemon
    # (clients/wecom-bridge). The daemon owns the WebSocket to WeCom and
    # POSTs incoming chat messages here (#create starts a normal turn);
    # it then polls #show until the assistant message settles and relays
    # the content back over the socket. Bearer-authed by the shared,
    # deployment-level WECOM_BRIDGE_TOKEN.
    class MessagesController < ActionController::API
      before_action :authenticate_bridge!

      def create
        content = params[:content].to_s.strip
        from = params[:from_userid].to_s.strip.first(64)
        return render json: { error: "content and from_userid are required" }, status: :unprocessable_entity if content.blank? || from.blank?

        conversation = conversation_for(from)
        return render json: { error: "busy" }, status: :conflict if conversation.turn_in_progress?

        _user_message, assistant = ConversationTurn.start(conversation, content: content, sender: user)
        render json: { conversation_id: conversation.id, message_id: assistant.id }, status: :created
      rescue ActiveRecord::RecordNotUnique
        # turn_in_progress? 与落库之间存在竞态窗口，唯一索引是真正的闸门
        render json: { error: "busy" }, status: :conflict
      end

      # Poll target for the daemon: content is present only once the turn
      # settled successfully; errored/canceled surface as terminal status.
      def show
        message = Message.find_by(id: params[:id], role: :assistant)
        return head :not_found unless message

        render json: { status: message.streaming_status, content: message.done? ? message.content : nil }
      end

      private

      def authenticate_bridge!
        expected = ENV["WECOM_BRIDGE_TOKEN"].presence
        return head :service_unavailable unless expected

        token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1].to_s
        head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(token, expected)
      end

      # v1: every WeCom sender maps to this one Metis account. Per-member
      # mapping lands later with a wecom_userid on User.
      def user
        @user ||= User.find_by!(email: ENV.fetch("WECOM_BRIDGE_USER_EMAIL", "admin@metis.local"))
      end

      # One long-lived conversation per WeCom sender — pi's session
      # continuity carries context across messages.
      def conversation_for(from)
        user.conversations.for_wecom_user(from).first_or_create! do |conversation|
          conversation.team = user.personal_team
          conversation.title = "企业微信 · #{from}"
          conversation.visibility = :personal
          conversation.settings = { "wecom_userid" => from }
        end
      end
    end
  end
end
