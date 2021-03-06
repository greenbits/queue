Pod::Spec.new do |s|
  s.name         = 'EDQueue'
  s.version      = '0.10.3'
  s.license      = 'MIT'
  s.summary      = 'A persistent background job queue for iOS.'
  s.homepage     = 'https://github.com/greenbits/queue'
  s.authors      = {'Andrew Sliwinski' => 'andrewsliwinski@acm.org', 'Francois Lambert' => 'flambert@mirego.com'}
  s.source       = { :git => 'https://github.com/greenbits/queue.git', :tag => s.version  }
  s.platform     = :ios, '5.0'
  s.source_files = 'EDQueue'
  s.library      = 'sqlite3.0'
  s.requires_arc = true
  s.prefix_header_contents = <<-OBJC
#ifndef ddLogLevel
#import <CocoaLumberjack/CocoaLumberjack.h>
#ifdef DEBUG
static const int ddLogLevel = DDLogLevelVerbose;
#else
static const int ddLogLevel = DDLogLevelInfo;
#endif
#endif
OBJC
  s.dependency 'CocoaLumberjack'
  s.dependency 'FMDB', '~> 2.0'
end
