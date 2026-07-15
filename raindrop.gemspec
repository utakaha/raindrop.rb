# frozen_string_literal: true

require_relative 'lib/raindrop/version'

Gem::Specification.new do |spec|
  spec.name = 'raindrop'
  spec.version = Raindrop::VERSION
  spec.authors = ['utakaha']
  spec.summary = 'Command line client for Raindrop.io'
  spec.description = 'A small Ruby command line client for searching and managing Raindrop.io bookmarks.'
  spec.homepage = 'https://github.com/utakaha/raindrop.rb'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata = {
    'source_code_uri' => spec.homepage
  }

  spec.files = Dir[
    'README.md',
    'exe/*',
    'lib/**/*.rb'
  ]
  spec.bindir = 'exe'
  spec.executables = ['raindrop']
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '>= 2.0', '< 3.0'
end
