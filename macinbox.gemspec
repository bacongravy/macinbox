lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "macinbox/version"

Gem::Specification.new do |s|
  s.name          = "macinbox"
  s.version       = Macinbox::VERSION
  s.authors       = ["David Kramer"]
  s.email         = ["bacongravy@icloud.com"]

  s.summary       = "Puts macOS in a Vagrant box"
  s.homepage      = "https://github.com/bacongravy/macinbox"
  s.license       = "MIT"

  s.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  s.bindir        = "exe"
  s.executables   = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency "bundler", "~> 1.16"
  s.add_development_dependency "rake", "~> 10.0"

  s.required_ruby_version = '~> 2.3'

  s.requirements << "macOS Catalina"
  s.requirements << "macOS Catalina installer app"
  s.requirements << "Vagrant"

end
