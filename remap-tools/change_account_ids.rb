version = '20170714-1'
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
  opts.on('-i', '--infile FILE_PATH', String, 'Input CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:infile] = a) : (puts 'ERROR: File does not exist!')
  end
  opts.on('-v', '--verbose', 'Enable Verbose logging including success messages.') do |a|
    options[:verbose] = a
  end
  opts.on_tail('-h', '--help', "Show this message (#{version})") do
    puts opts
    exit
  end
end.parse!
if options[:url].nil? || options[:token].nil? || options[:infile].nil?
  puts options
  puts "ERROR: Missing required fields!\nUse -h for help.\n\n"
  exit
end

# output_csv = options[:infile]+".log"        # put the full path to a blank csv file to have the errors written in.
logger = Logger.new("#{options[:infile]}.log")
logger.formatter = proc do |severity, _datetime, _progname, msg|
  severity = severity == 'INFO' ? '' : "#{severity} "
  puts "#{severity}#{msg}"
  "#{severity}#{msg}\n"
end
logger.info("======== Run started at #{Time.now} ========")
############################## DO NOT CHANGE THESE VALUES #######################
base_url = options[:url]

hydra = Typhoeus::Hydra.new(max_concurrency: 10)
CSV.foreach(options[:infile], headers: true) do |row|
  if !row.headers.include?('old_id') || !row.headers.include?('new_id')
    logger.fatal("Input file #{options[:infile]} must contain old_id and new_id columns")
    exit
  else
    # puts base_url, options[:token]
    api_url = "#{base_url}/api/v1/accounts/sis_account_id:#{URI.encode(row['old_id'])}"
    get_response = Typhoeus::Request.new(api_url,
                                         method: :put,
                                         headers: { Authorization: "Bearer #{options[:token]}" },
                                         params: { 'account[sis_account_id]' => row['new_id'] })

    get_response.on_complete do |response|
      parsed_data = nil
      if response.code.eql?(200)
        parsed_data = JSON.parse(response.body)
        if parsed_data['sis_account_id'] == row['new_id']
          options[:verbose] == true ? logger.info("Success: #{row['old_id']} -> #{row['new_id']}") : (puts "Success: #{row['old_id']} -> #{row['new_id']}")
        else
          logger.error("on #{row['old_id']}: Unable to set account's SIS ID to #{row['new_id']}")
        end
      elsif response.code.eql?(404)
        logger.error("on #{row['old_id']}: Account not found")
      elsif response.code.eql?(500)
        parsed_data = JSON.parse(response.body)
        logger.error("on #{row['old_id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{parsed_data['errors'][0]['message']} #{parsed_data['errors'][0]['error_code']} #{parsed_data['errors'][0]['message']} [error report: #{parsed_data['error_report_id']}])")
      # hydra.queue(get_response)
      elsif response.body['is already in use']
        logger.error("on #{row['old_id']}: new_id #{row['new_id']} is already in use")
      else
        logger.error("on #{row['old_id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{response.body})")
      end
    end
    hydra.queue(get_response)
  end
end
hydra.run
logger.info("========= Run finished at #{Time.now} =======")
