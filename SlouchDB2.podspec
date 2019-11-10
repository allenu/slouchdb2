#
# Be sure to run `pod lib lint SlouchDB2.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SlouchDB2'
  s.version          = '0.2.0'
  s.summary          = 'A distributed, single-user database'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
SlouchDB2 is a distributed, single-user database that uses third party storage
as the sync mechanism.
                       DESC

  s.homepage         = 'https://github.com/allenu/slouchdb2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'allenu' => '1897128+allenu@users.noreply.github.com' }
  s.source           = { :git => 'https://github.com/allenu/SlouchDB2.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/ussherpress'

  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.14'

  s.source_files = 'SlouchDB2/Source/**/*'
  s.swift_versions = ['4.0']
  
  # s.resource_bundles = {
  #   'SlouchDB2' => ['SlouchDB2/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
