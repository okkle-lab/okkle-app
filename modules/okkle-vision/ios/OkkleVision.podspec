Pod::Spec.new do |s|
  s.name           = 'OkkleVision'
  s.version        = '1.0.0'
  s.summary        = 'On-device receipt OCR for Okkle (Apple Vision)'
  s.description    = 'Wraps VNRecognizeTextRequest to read receipt text on-device.'
  s.author         = 'Okkle'
  s.homepage       = 'https://okkle.uk'
  s.license        = 'MIT'
  s.platforms      = { :ios => '15.1' }
  s.source         = { :git => '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
