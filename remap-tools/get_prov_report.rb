version = '20170719-1'
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
  opts.on('-d', '--includedeleted', 'Include deleted in export.') do |a|
    options[:incdel] = true if a == true
  end
  opts.on('-o', '--options [aceghmostux]', String, 'File types to download. Include all options with no spaces (example: -o ucs', '   all - Select all options', '   a - Accounts', '   c - Courses', '   e - Enrollments', '   g - Groups', '   h - Group Categories', '   m - Group Membership', '   o - User Observers', '   s - Sections', '   t - Terms', '   u - Users (default if no options provided)', '   x - Xlist') do |a|
    options[:params] = {}
    a.downcase!
    if a == 'all'
      a = 'aceghmostux'
    elsif a == 'allee'
      a = 'acghmostux'
    end
    a.split('').each do |i|
      case i
      when 'a'
        options[:params]['accounts'] = true
      when 'c'
        options[:params]['courses'] = true
      when 'e'
        options[:params]['enrollments'] = true
      when 'g'
        options[:params]['groups'] = true
      when 'h'
        options[:params]['group_categories'] = true
      when 'm'
        options[:params]['group_membership'] = true
      when 'o'
        options[:params]['user_observers'] = true
      when 's'
        options[:params]['sections'] = true
      when 't'
        options[:params]['terms'] = true
      when 'u'
        options[:params]['users'] = true
      when 'x'
        options[:params]['xlist'] = true
      end
    end
  end
  opts.on_tail('-h', '--help', "Show this message (#{version})") do
    puts opts
    exit
  end
end.parse!
options[:incdel] = false unless options[:incdel]
options[:params] = { 'users' => true } if options[:params].nil?
options[:params]['include_deleted'] = options[:incdel]
if options[:url].nil? || options[:token].nil? || options[:client].nil?
  puts options
  puts "ERROR: Missing required fields!\nUse -h for help.\n\n"
  exit
end
# output_csv = options[:infile]+".log"        # put the full path to a blank csv file to have the errors written in.
############################## DO NOT CHANGE THESE VALUES #######################
base_url = options[:url]
puts 'Starting report'
# puts options[:incdel]
puts options[:params]
# exit
request = Typhoeus::Request.new("#{base_url}/api/v1/accounts/self/reports/provisioning_csv",
                                method: :post,
                                headers: { Authorization: "Bearer #{options[:token]}" },
                                params: { 'parameters' => options[:params] })
response = request.run
if response.code == 200
  parsed = JSON.parse(response.body)
  report_id = parsed['id']
  puts "Report started (id: #{report_id})...please hold..."
  report_status = 'running'
  while report_status == 'running'
    sleep 5
    puts 'Checking report status...'
    request = Typhoeus::Request.new(base_url + "/api/v1/accounts/self/reports/provisioning_csv/#{report_id}",
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
