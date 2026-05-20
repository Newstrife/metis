require "test_helper"
require "tmpdir"

class Agent::SessionArchiveTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "arch@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi)
  end

  def with_tmp_dir
    Dir.mktmpdir { |dir| yield Pathname.new(dir) }
  end

  test "store then restore round-trips the session directory contents" do
    with_tmp_dir do |source|
      File.write(source.join("session.jsonl"), %({"role":"user"}\n))
      source.join("sub").mkpath
      File.write(source.join("sub/notes.txt"), "hello")
      Agent::SessionArchive.store(@conversation, from: source)
    end

    assert @conversation.pi_session_archive.attached?

    with_tmp_dir do |dest|
      Agent::SessionArchive.restore(@conversation, into: dest)
      assert_equal %({"role":"user"}\n), File.read(dest.join("session.jsonl"))
      assert_equal "hello", File.read(dest.join("sub/notes.txt"))
    end
  end

  test "restore is a no-op when no archive is attached" do
    with_tmp_dir do |dest|
      Agent::SessionArchive.restore(@conversation, into: dest)
      assert_empty Dir.children(dest)
    end
  end

  test "store skips an empty directory" do
    with_tmp_dir do |source|
      Agent::SessionArchive.store(@conversation, from: source)
    end
    refute @conversation.pi_session_archive.attached?
  end

  test "store replaces a prior archive" do
    with_tmp_dir do |source|
      File.write(source.join("v1.txt"), "first")
      Agent::SessionArchive.store(@conversation, from: source)
    end
    with_tmp_dir do |source|
      File.write(source.join("v2.txt"), "second")
      Agent::SessionArchive.store(@conversation, from: source)
    end

    with_tmp_dir do |dest|
      Agent::SessionArchive.restore(@conversation, into: dest)
      assert_equal [ "v2.txt" ], Dir.children(dest)
    end
  end
end
