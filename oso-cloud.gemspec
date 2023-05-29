require_relative 'lib/oso/version'

Gem::Specification.new do |spec|
  spec.name          = 'oso-cloud'
  spec.version       = OsoCloud::VERSION
  spec.authors       = ['Oso Security, Inc.']
  spec.email         = ['support@osohq.com']
  spec.summary       = 'Oso Cloud Ruby client'
  spec.homepage      = 'https://www.osohq.com/'
  spec.license       = 'Apache-2.0'

  spec.required_ruby_version = Gem::Requirement.new('>= 3.0.0')

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '>= 1.10'
  spec.add_dependency 'faraday-retry', '>= 1'
  spec.add_development_dependency 'minitest', '~> 5.15'
end
