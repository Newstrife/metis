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
        chatid = params[:chatid].to_s.strip.first(64).presence
        return render json: { error: "content and from_userid are required" }, status: :unprocessable_entity if content.blank? || from.blank?

        conversation = conversation_for(sender, from, chatid)
        return render json: { error: "busy" }, status: :conflict if conversation.turn_in_progress?

        # 群消息带上发言人标识，agent 才能区分指令来自谁
        turn_content = chatid ? "[群成员 #{from}] #{content}" : content
        _user_message, assistant = ConversationTurn.start(conversation, content: turn_content, sender: sender)
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

      def sender
        @sender ||= User.provision_for_wecom!(params[:from_userid].to_s.strip.first(64))
      end

      # The deployment-level account that owns group conversations, so the
      # operator can see every group's turns in the web UI.
      def bridge_owner
        @bridge_owner ||= User.find_by!(email: ENV.fetch("WECOM_BRIDGE_USER_EMAIL", "admin@metis.local"))
      end

      # One long-lived conversation per WeCom context — a group chat
      # (chatid) gets its own under the bridge owner, direct messages one
      # per sender under their own account — so pi's session continuity
      # stays scoped to the group/scene.
      def conversation_for(sender, from, chatid)
        owner = chatid ? bridge_owner : sender
        scope = chatid ? owner.conversations.for_wecom_chat(chatid) : owner.conversations.for_wecom_user(from)
        scope.first_or_create! do |conversation|
          conversation.team = owner.personal_team
          conversation.title = chatid ? "企业微信群 · #{chatid.last(6)}" : "企业微信 · #{from}"
          conversation.visibility = :personal
          conversation.settings = chatid ? { "wecom_chatid" => chatid } : { "wecom_userid" => from }
        end
      end
    end
  end
end
