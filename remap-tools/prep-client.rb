require 'csv'
require 'yaml'
require 'optparse'

version = '20180713-1'

options = {}
parse = OptionParser.new do |opts|
  opts.banner = 'Usage: script.rb [options]'

  opts.on('-u', '--url URL', String, 'Canvas URL including https:// (ex: https://canvas.instructure.com) (uses <client>.instructure.com if not provided)') do |a|
    a.match(%r{^https://([\w-]+\.+)+\w+$}i) ? (options[:url] = a) : (puts 'ERROR: URL must be in form https://example.instructure.com')
  end
  opts.on('-t', '--token TOKEN', String, 'Canvas API token (required)') do |a|
    options[:token] = a
  end
  opts.on('-c', '--client CLIENT_ALIAS', String, 'Alias for client (required)') do |a|
    File.directory?(a) ? (puts 'ERROR: Client already exists!') : (options[:client] = a)
  end
  opts.on_tail('-h', '--help', "Show this message (#{version})") do
    puts opts
    exit
  end
end.parse!
options[:url] = "https://#{options[:client]}.instructure.com" if options[:url].nil? && !options[:client].nil?
if options[:url].nil? || options[:token].nil? || options[:client].nil?
  puts "ERROR: Missing required fields!\nUse -h for help.\n\n"
  exit
end

puts 'Creating folder...'
Dir.mkdir(options[:client])
Dir.mkdir("#{options[:client]}/sisapp")
Dir.mkdir("#{options[:client]}/sistemic")
puts 'Saving config...'
File.open("#{options[:client]}/#{options[:client]}.yaml", 'w') { |f| f.puts options.to_yaml }
puts 'Done!'
