# frozen_string_literal: true

require_relative "test_helper"

class FakeConfig
  attr_reader :written_token, :deleted

  def initialize(token: nil, path: "/tmp/raindrop-cli/config.yml")
    @token = token
    @path = path
    @deleted = false
  end

  def path
    @path
  end

  def access_token
    @token.to_s
  end

  def save_access_token(token)
    @written_token = token
    @token = token
    true
  end

  def delete_access_token
    existed = !@token.nil?
    @token = nil
    @deleted = true
    existed
  end
end

class RaindropCliTest < Minitest::Test
  def run_cli(argv, stdin: "", config: FakeConfig.new)
    stdout = StringIO.new
    stderr = StringIO.new
    input = StringIO.new(stdin)

    code = RaindropCli::CLI.new(
      argv,
      stdin: input,
      stdout: stdout,
      stderr: stderr,
      config: config
    ).run

    [code, stdout.string, stderr.string, config]
  end

  def test_auth_token_saves_token_from_stdin
    code, stdout, stderr, store = run_cli(["auth", "token"], stdin: "secret-token\n")

    assert_equal 0, code
    assert_equal "secret-token", store.written_token
    assert_includes stdout, "Token saved to /tmp/raindrop-cli/config.yml"
    assert_empty stderr
  end

  def test_auth_token_rejects_empty_token
    code, stdout, stderr, = run_cli(["auth", "token"], stdin: "\n")

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Token is empty."
  end

  def test_auth_status_uses_config
    code, stdout, stderr, = run_cli(
      ["auth", "status"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 0, code
    assert_includes stdout, "Authenticated by /tmp/raindrop-cli/config.yml"
    assert_empty stderr
  end

  def test_auth_status_returns_failure_when_token_is_missing
    code, stdout, stderr, = run_cli(["auth", "status"])

    assert_equal 1, code
    assert_includes stdout, "Not authenticated."
    assert_empty stderr
  end

  def test_auth_logout_deletes_stored_token
    store = FakeConfig.new(token: "stored-token")
    code, stdout, stderr, = run_cli(["auth", "logout"], config: store)

    assert_equal 0, code
    assert store.deleted
    assert_includes stdout, "Token removed from /tmp/raindrop-cli/config.yml"
    assert_empty stderr
  end
end
