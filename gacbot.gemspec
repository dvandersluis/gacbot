# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gacbot/version'

Gem::Specification.new do |gem|
  gem.name          = "gacbot"
  gem.version       = GACBot::VERSION
  gem.authors       = ["Daniel Vandersluis"]
  gem.email         = ["daniel.vandersluis@gmail.com"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'wikibot', '0.2.4.3'
  gem.add_dependency 'andand', '1.3.1'
  gem.add_dependency 'rubytree', '0.5.2'
  gem.add_dependency 'colored'
end
