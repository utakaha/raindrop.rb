# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_save_and_read_access_token
    Dir.mktmpdir do |dir|
      with_config_home(dir) do
        config = RaindropCli::Config.new

        assert config.save_access_token("secret-token")
        assert_equal "secret-token", config.access_token
      end
    end
  end

  def test_save_access_token_sets_directory_and_file_permissions
    Dir.mktmpdir do |dir|
      path = File.join(dir, "raindrop-cli", "config.yml")
      with_config_home(dir) do
        config = RaindropCli::Config.new

        config.save_access_token("secret-token")

        assert_equal "700", mode_string(File.dirname(path))
        assert_equal "600", mode_string(path)
      end
    end
  end

  def test_delete_access_token_removes_config_file_when_empty
    Dir.mktmpdir do |dir|
      path = File.join(dir, "raindrop-cli", "config.yml")
      with_config_home(dir) do
        config = RaindropCli::Config.new

        config.save_access_token("secret-token")

        assert config.delete_access_token
        refute File.exist?(path)
        assert_empty config.access_token
      end
    end
  end

  def test_delete_access_token_preserves_non_auth_config
    Dir.mktmpdir do |dir|
      path = File.join(dir, "raindrop-cli", "config.yml")
      with_config_home(dir) do
        config = RaindropCli::Config.new

        config.save_access_token("secret-token")
        File.write(
          path,
          {
            "auth" => {
              "type" => "test_token",
              "access_token" => "secret-token"
            },
            "defaults" => {
              "collection_id" => 0
            }
          }.to_yaml,
          mode: "w",
          perm: 0o600
        )

        assert config.delete_access_token

        data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
        assert_equal({ "collection_id" => 0 }, data.fetch("defaults"))
        refute data.key?("auth")
      end
    end
  end

  private

  def with_config_home(dir)
    original = ENV["XDG_CONFIG_HOME"]
    ENV["XDG_CONFIG_HOME"] = dir
    yield
  ensure
    ENV["XDG_CONFIG_HOME"] = original
  end

  def mode_string(path)
    format("%o", File.stat(path).mode & 0o777)
  end
end
