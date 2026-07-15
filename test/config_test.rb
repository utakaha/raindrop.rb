# frozen_string_literal: true

require_relative 'test_helper'

class ConfigTest < Minitest::Test
  def test_save_oauth_token_sets_directory_and_file_permissions
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'raindrop-cli', 'config.yml')
      with_config_home(dir) do
        config = Raindrop::Config.new

        config.save_oauth_token('access_token' => 'access-token')

        assert_equal '700', mode_string(File.dirname(path))
        assert_equal '600', mode_string(path)
      end
    end
  end

  def test_save_oauth_token
    Dir.mktmpdir do |dir|
      with_config_home(dir) do
        config = Raindrop::Config.new

        assert config.save_oauth_token(
          'access_token' => 'access-token',
          'refresh_token' => 'refresh-token',
          'token_type' => 'Bearer',
          'expires_in' => 3600
        )

        assert_equal 'oauth', config.auth_type
        assert_equal 'access-token', config.access_token
        assert config.refresh_token?
        assert_equal 'Bearer', config.token_type
        assert_equal 3600, config.expires_in
      end
    end
  end

  def test_save_oauth_token_requires_access_token
    Dir.mktmpdir do |dir|
      with_config_home(dir) do
        config = Raindrop::Config.new

        error = assert_raises(Raindrop::ConfigError) do
          config.save_oauth_token('refresh_token' => 'refresh-token')
        end

        assert_equal 'OAuth response did not include an access token.', error.message
      end
    end
  end

  def test_delete_access_token_removes_config_file_when_empty
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'raindrop-cli', 'config.yml')
      with_config_home(dir) do
        config = Raindrop::Config.new

        config.save_oauth_token('access_token' => 'access-token')

        assert config.delete_access_token
        refute File.exist?(path)
        assert_empty config.access_token
      end
    end
  end

  def test_delete_access_token_removes_oauth_credentials
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'raindrop-cli', 'config.yml')
      with_config_home(dir) do
        config = Raindrop::Config.new
        config.save_oauth_token(
          'access_token' => 'access-token',
          'refresh_token' => 'refresh-token'
        )

        assert config.delete_access_token
        refute File.exist?(path)
        assert_empty config.access_token
      end
    end
  end

  def test_delete_access_token_preserves_non_auth_config
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'raindrop-cli', 'config.yml')
      with_config_home(dir) do
        config = Raindrop::Config.new

        config.save_oauth_token('access_token' => 'access-token')
        File.write(
          path,
          {
            'auth' => {
              'type' => 'oauth',
              'access_token' => 'access-token'
            },
            'defaults' => {
              'collection_id' => 0
            }
          }.to_yaml,
          mode: 'w',
          perm: 0o600
        )

        assert config.delete_access_token

        data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
        assert_equal({ 'collection_id' => 0 }, data.fetch('defaults'))
        refute data.key?('auth')
      end
    end
  end

  private

  def with_config_home(dir)
    original = ENV['XDG_CONFIG_HOME']
    ENV['XDG_CONFIG_HOME'] = dir
    yield
  ensure
    ENV['XDG_CONFIG_HOME'] = original
  end

  def mode_string(path)
    format('%o', File.stat(path).mode & 0o777)
  end
end
