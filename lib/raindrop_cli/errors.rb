# frozen_string_literal: true

module RaindropCli
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class ConfigError < Error; end
end
