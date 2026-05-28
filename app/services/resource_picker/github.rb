require "net/http"
require "json"

module ResourcePicker
  # Lists the repositories accessible to the user through their GitHub
  # OAuth grant. The GitHub App grant authorizes the App on whichever
  # repos the user (or an org admin) selected at install time;
  # `/user/repos` returns that intersection.
  #
  # Sorted updated-desc so the project the operator is most likely
  # working on right now is at the top of the picker. Capped at one
  # page (100) — operators with more than 100 active repos can type
  # `owner/name` directly if pagination ever becomes a real problem.
  module Github
    LIST_URL = URI("https://api.github.com/user/repos?per_page=100&sort=updated").freeze

    module_function

    def list(user:)
      token = OauthBroker.bearer_for(user: user, provider: "github")
      return [] if token.blank?

      response = fetch(token)
      return [] unless response.code == "200"

      JSON.parse(response.body).map { |repo| { value: repo["full_name"], label: repo["full_name"] } }
    rescue StandardError => error
      Rails.logger.warn("ResourcePicker::Github failed for user=#{user.id}: #{error.class}: #{error.message}")
      []
    end

    def fetch(token)
      request = Net::HTTP::Get.new(LIST_URL)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      ResourcePicker.https_client_for(LIST_URL).request(request)
    end
  end
end
