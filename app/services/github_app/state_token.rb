module GithubApp
  # Signs the user id carried as the `state` param through the GitHub
  # OAuth flow. The callback verifies the signature, then resolves the
  # credential to the same user the session authenticated — defence in
  # depth on top of the session itself. See docs/connectors.md.
  class StateToken
    EXPIRY = 30.minutes
    PURPOSE = "github_oauth_connect".freeze

    class InvalidError < StandardError; end

    class << self
      def generate(user_id:)
        verifier.generate({ user_id: user_id.to_i }, purpose: PURPOSE, expires_in: EXPIRY)
      end

      def verify(token)
        raise InvalidError, "Missing state" if token.blank?

        data = verifier.verify(token, purpose: PURPOSE)
        user_id = data[:user_id] || data["user_id"]
        raise InvalidError, "Missing user_id" if user_id.nil?

        Integer(user_id)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, TypeError => e
        raise InvalidError, "Invalid state: #{e.message}"
      end

      private

      def verifier
        Rails.application.message_verifier(:github_oauth_state)
      end
    end
  end
end
