version = '20170703-1'
require 'optparse'
require 'typhoeus'
require 'csv'
require 'json'
require 'URI'
require 'YAML'

options = {}
parse = OptionParser.new do |opts|
  opts.banner = 'Usage: script.rb [options]'
  opts.on('-c', '--client [CLIENT_ALIAS]', String, 'Alias for client. Other field not required when provided') do |a|
    if File.directory?(a) && File.exist?("#{a}/#{a}.yaml")
      options = YAML.load_file("#{a}/#{a}.yaml")
    else
      (puts 'ERROR: Client does not exist!')
    end
  end
  opts.on('-u', '--url URL', String, 'Canvas URL including https:// (ex: https://canvas.instructure.com) (required)') do |a|
    a.match(%r{^https://([\w-]+\.+)+\w+$}i) ? (options[:url] = a) : (puts 'ERROR: URL must be in form httpd://example.instructure.com')
  end
  opts.on('-t', '--token TOKEN', String, 'Canvas API token (required)') do |a|
    options[:token] = a
  end
  opts.on('-p', '--prefix [FILE_PREFIX]', String, 'Prefix to prepend to downloaded filename. (Ignored with -f)') do |a|
    options[:prefix] = a
  end
  opts.on('-f', '--filename [FILENAME]', String, 'Name to give exported file. Will override default name.') do |a|
    options[:filename] = a
  end
  opts.on('-d', '--includedeleted', 'Include deleted items in export.') do |a|
    options[:incdel] = true if a == true
  end
  opts.on_tail('-h', '--help', "Show this message (#{version})") do
    puts opts
    exit
  end
end.parse!
if options[:url].nil? || options[:token].nil? || options[:client].nil?
  puts options
  puts "ERROR: Missing required fields!\nUse -h for help.\n\n"
  exit
end
options[:incdel] = false unless options[:incdel]
# output_csv = options[:infile]+".log"        # put the full path to a blank csv file to have the errors written in.
############################## DO NOT CHANGE THESE VALUES #######################
base_url = options[:url]
puts 'Starting report'
puts options[:incdel]
request = Typhoeus::Request.new("#{base_url}/api/v1/accounts/self/reports/sis_export_csv",
                                method: :post,
                                headers: { Authorization: "Bearer #{options[:token]}" },
                                params: { 'parameters' => { 'users' => true, 'include_deleted' => options[:incdel] } })
response = request.run
if response.code == 200
  parsed = JSON.parse(response.body)
  report_id = parsed['id']
  puts "Report started (id: #{report_id})...please hold..."
  report_status = 'running'
  while report_status == 'running'
    sleep 5
    puts 'Checking report status...'
    request = Typhoeus::Request.new(base_url + "/api/v1/accounts/self/reports/sis_export_csv/#{report_id}",
                                    method: :get,
                                    headers: { Authorization: "Bearer #{options[:token]}" })
    response = request.run
    parsed = JSON.parse(response.body)
    report_status = parsed['status']
  end
  if report_status == 'complete'
    puts "The report is done! Let's download it!"
    request = Typhoeus::Request.new(parsed['attachment']['url'],
                                    method: :get,
                                    followlocation: true)

    defined?(options[:client]) ? (filename = "#{options[:client]}/") : (filename = '')
    if options[:filename]
      filename = "#{filename}#{options[:filename]}"
    else
      filename = "#{filename}#{options[:prefix]}-" unless options[:prefix].nil?
      filename = "#{filename}#{parsed['attachment']['filename']}"
    end

    save_file = File.open(filename, 'wb')
    request.on_body do |chunk|
      save_file.write(chunk)
    end
    request.on_complete do |_r|
      save_file.close
    end
    request.run
    puts "Well the file should be downloaded... (#{filename})"
  else
    puts "Well that didn't work (1). Here is what we know:\nResponse Code: #{response.code}\nReponse Body: #{response.body}"
  end

else
  puts "Well that didn't work (2). Here is what we know:\nResponse Code: #{response.code}\nReponse Body: #{response.body}"
end
