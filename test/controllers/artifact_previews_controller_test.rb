require "test_helper"

class ArtifactPreviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "owner@example.com", password: "password123")
    @stranger = User.create!(email: "stranger@example.com", password: "password123")
    @conversation = @user.conversations.create!(title: "T")
    @message = @conversation.messages.create!(role: :assistant, content: "x", streaming_status: :done)
    @message.artifacts.attach(
      io: StringIO.new("col\na\nb\n"),
      filename: "data.csv",
      content_type: "text/csv"
    )
    @blob = @message.artifacts.first.blob
  end

  test "renders the preview for a member of the conversation's team" do
    sign_in @user
    get artifact_preview_path(@blob.signed_id)

    assert_response :success
    assert_select "table.preview-csv"
    assert_match(/data\.csv/, response.body)
  end

  test "404s a stranger even with a valid signed_id" do
    sign_in @stranger
    get artifact_preview_path(@blob.signed_id)
    assert_response :not_found
  end

  test "404s a blob that isn't attached as an artifact (e.g. a user upload)" do
    # A leaked signed_id for the inbound :files attachment must NOT
    # resolve through this route — only outbound artifacts do.
    user_msg = @conversation.messages.create!(role: :user, content: "u", streaming_status: :done)
    user_msg.files.attach(io: StringIO.new("oops"), filename: "secret.txt", content_type: "text/plain")
    upload_blob = user_msg.files.first.blob

    sign_in @user
    get artifact_preview_path(upload_blob.signed_id)
    assert_response :not_found
  end

  test "redirects to sign-in when not authenticated" do
    get artifact_preview_path(@blob.signed_id)
    assert_redirected_to new_user_session_path
  end

  test "404s a renderer with no preview_partial (e.g. PDF — opened via blob URL, not this route)" do
    @message.artifacts.attach(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "report.pdf",
      content_type: "application/pdf"
    )
    pdf_blob = @message.artifacts.where(name: "artifacts")
                       .joins(:blob).find_by(active_storage_blobs: { filename: "report.pdf" }).blob

    sign_in @user
    get artifact_preview_path(pdf_blob.signed_id)
    assert_response :not_found
  end
end
