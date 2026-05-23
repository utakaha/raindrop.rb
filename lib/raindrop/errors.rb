# frozen_string_literal: true

module Raindrop
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class ApiError < Error; end
  class ConfigError < Error; end
  class SearchError < Error; end
end
