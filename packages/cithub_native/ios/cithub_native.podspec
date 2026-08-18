Pod::Spec.new do |s|
  s.name             = 'cithub_native'
  s.version          = '1.0.0'
  s.summary          = 'Native WebVPN, academic and Tieba protocol support for Cithub.'
  s.description      = <<-DESC
Native iOS implementation of the Cithub WebVPN, academic-system and Tieba protocols.
                       DESC
  s.homepage         = 'https://github.com/aquasofts/cithub-flutter'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AquaSofts' => 'opensource@aquasofts.org' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.frameworks = 'Security', 'WebKit', 'CryptoKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.9'
end
