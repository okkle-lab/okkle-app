Pod::Spec.new do |s|
  s.name           = 'OkkleAI'
  s.version        = '1.0.0'
  s.summary        = 'Apple Intelligence on-device LLM for Okkle'
  s.description    = 'Wraps the iOS 26 Foundation Models framework for on-device extraction.'
  s.author         = 'Okkle'
  s.homepage       = 'https://okkle.uk'
  s.license        = 'MIT'
  s.platforms      = { :ios => '15.1' }
  s.source         = { :git => '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
