Gem::Specification.new do |s|
  s.name        = 'bespoked'
  s.version     = '0.1.0'
  s.date        = '2016-12-01'
  s.summary     = "kubernetes ingress controller w/ generic rack server support"
  s.description = "simple rack based ruby http proxy"
  s.authors     = ["Jon Bardin"]
  s.email       = 'diclophis@gmail.com'
  s.files       = Dir['lib/*.rb']
  s.homepage    = "https://github.com/diclophis/bespoked"
  s.license     = 'MIT'

  # streaming JSON parsing and encoding library for Ruby (lightweight bindings to pure C yajl parser)
  s.add_dependency 'yajl-ruby'
end
