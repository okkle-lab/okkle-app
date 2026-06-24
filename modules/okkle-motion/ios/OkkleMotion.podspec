Pod::Spec.new do |s|
  s.name           = 'OkkleMotion'
  s.version        = '1.0.0'
  s.summary        = 'Core Motion activity detection for Okkle'
  s.description    = 'Wraps CMMotionActivityManager to detect driving/cycling on-device.'
  s.author         = 'Okkle'
  s.homepage       = 'https://okkle.uk'
  s.license        = 'MIT'
  s.platforms      = { :ios => '15.1' }
  s.source         = { :git => '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
