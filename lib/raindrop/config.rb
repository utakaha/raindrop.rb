# frozen_string_literal: true

require "fileutils"
require "yaml"

require_relative "errors"

module Raindrop
  class Config
    CONFIG_DIR_MODE = 0o700
    CONFIG_FILE_MODE = 0o600

    attr_reader :path

    def initialize
      @path = File.expand_path(self.class.default_path)
    end

    def self.default_path
      config_home = ENV.fetch("XDG_CONFIG_HOME") do
        File.join(Dir.home, ".config")
      end

      File.join(config_home, "raindrop-cli", "config.yml")
    end

    def access_token
      data.dig("auth", "access_token").to_s.strip
    end

    def auth_type
      data.dig("auth", "type").to_s.strip
    end

    def refresh_token?
      !data.dig("auth", "refresh_token").to_s.strip.empty?
    end

    def token_type
      data.dig("auth", "token_type").to_s.strip
    end

    def expires_in
      data.dig("auth", "expires_in")
    end

    def save_oauth_token(payload)
      access_token = payload["access_token"].to_s.strip
      raise ConfigError, "OAuth response did not include an access token." if access_token.empty?

      update do |data|
        data["auth"] = {
          "type" => "oauth",
          "access_token" => access_token
        }
        data["auth"]["refresh_token"] = payload["refresh_token"].to_s unless payload["refresh_token"].to_s.empty?
        data["auth"]["token_type"] = payload["token_type"].to_s unless payload["token_type"].to_s.empty?
        data["auth"]["expires_in"] = payload["expires_in"] if payload.key?("expires_in")
      end

      true
    end

    def delete_access_token
      return false unless File.file?(@path)

      data = read_data
      token = data.dig("auth", "access_token").to_s.strip
      return false if token.empty?

      data.delete("auth")
      write_data(data)

      true
    end

    private

    def data
      return {} unless File.file?(@path)

      read_data
    end

    def update
      data = self.data
      yield data
      write_data(data)
    end

    def read_data
      YAML.safe_load_file(@path, permitted_classes: [], aliases: false) || {}
    rescue Psych::SyntaxError => e
      raise ConfigError, "Failed to read config file: #{e.message}"
    end

    def write_data(data)
      if data.empty?
        File.delete(@path) if File.file?(@path)
        return
      end

      ensure_parent_directory!
      File.write(@path, YAML.dump(data), mode: "w", perm: CONFIG_FILE_MODE)
      File.chmod(CONFIG_FILE_MODE, @path)
    end

    def ensure_parent_directory!
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir, mode: CONFIG_DIR_MODE)
      File.chmod(CONFIG_DIR_MODE, dir)
    end
  end
end
