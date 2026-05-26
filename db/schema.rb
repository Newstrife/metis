# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_25_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "connector_credentials", force: :cascade do |t|
    t.bigint "connector_id", null: false
    t.datetime "created_at", null: false
    t.text "credentials"
    t.string "external_login"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["connector_id", "user_id"], name: "index_connector_credentials_on_connector_id_and_user_id", unique: true, nulls_not_distinct: true
    t.index ["connector_id"], name: "index_connector_credentials_on_connector_id"
    t.index ["user_id"], name: "index_connector_credentials_on_user_id"
  end

  create_table "connectors", force: :cascade do |t|
    t.string "catalog_key"
    t.datetime "created_at", null: false
    t.jsonb "definition", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.bigint "team_id", null: false
    t.integer "transport", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "catalog_key"], name: "index_connectors_on_team_id_and_catalog_key", unique: true
    t.index ["team_id", "name"], name: "index_connectors_on_team_id_and_name", unique: true
    t.index ["team_id"], name: "index_connectors_on_team_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.jsonb "agent_model", default: {}, null: false
    t.datetime "archived_at"
    t.string "backend_session_id"
    t.datetime "cancel_requested_at"
    t.jsonb "context_usage", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "e2b_sandbox_id"
    t.jsonb "runtime_state", default: {}, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "share_token"
    t.bigint "team_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["archived_at"], name: "index_conversations_on_archived_at"
    t.index ["e2b_sandbox_id"], name: "index_conversations_on_e2b_sandbox_id"
    t.index ["share_token"], name: "index_conversations_on_share_token", unique: true
    t.index ["team_id"], name: "index_conversations_on_team_id"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id"], name: "index_memberships_on_team_id"
    t.index ["user_id", "team_id"], name: "index_memberships_on_user_id_and_team_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_read_tokens"
    t.text "content"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "input_tokens"
    t.jsonb "native_ref"
    t.integer "output_tokens"
    t.text "reasoning"
    t.integer "role", null: false
    t.datetime "started_at"
    t.integer "streaming_status", default: 0, null: false
    t.string "tool_call_id"
    t.jsonb "tool_calls", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["conversation_id"], name: "index_messages_on_one_in_progress_turn", unique: true, where: "((role = 1) AND (streaming_status = ANY (ARRAY[0, 1])))"
  end

  create_table "oauth_grants", force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "provider", null: false
    t.text "refresh_token"
    t.text "scopes"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "provider"], name: "index_oauth_grants_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_oauth_grants_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.boolean "personal", default: false, null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "language"
    t.string "preferred_model"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "connector_credentials", "connectors"
  add_foreign_key "connector_credentials", "users"
  add_foreign_key "connectors", "teams"
  add_foreign_key "conversations", "teams"
  add_foreign_key "conversations", "users"
  add_foreign_key "identities", "users"
  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "oauth_grants", "users"
end
