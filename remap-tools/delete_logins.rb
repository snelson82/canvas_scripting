version = '20170705-1'
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
    File.exist?(a) ? (options[:infile] = a) : (puts "ERROR: Input file does not exist! (#{a})"; exit;)
  end
  opts.on('-v', '--verbose', 'Enable Verbose logging including success messages.') do |a|
    options[:verbose] = a
  end
  opts.on_tail('-h', '--help', "Show this message (#{version})") do
    puts opts
    exit
  end
end.parse!
options[:infile] = "#{options[:client]}/analysis/#{options[:client]}-remapdata.csv" if options[:infile].nil? && !options[:client].nil? && File.exist?("#{options[:client]}/analysis/#{options[:client]}-remapdata.csv")
if options[:url].nil? || options[:token].nil? || options[:infile].nil?
  # puts options
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
  if !row.headers.include?('user_id') || !row.headers.include?('old_login_id')
    logger.fatal("Error: Input file #{options[:infile]} must contain user_id and old_login_id columns")
    exit
  else
    # puts base_url, options[:token]
    api_url = "#{base_url}/api/v1/users/sis_user_id:#{URI.encode(row['user_id'])}/logins?per_page=100"
    get_response = Typhoeus::Request.new(api_url,
                                         method: :get,
                                         headers: { Authorization: "Bearer #{options[:token]}" })

    get_response.on_complete do |response|
      export_id = ''
      exported_sis_id = ''
      parsed_data = nil

      if response.code.eql?(200)
        exported_sis_id = ''
        parsed_data = JSON.parse(response.body)
        parsed_data.each do |login|
          # puts login['sis_user_id']
          # puts login['unique_id']
          next unless login['sis_user_id'].eql?(row['user_id']) && login['unique_id'].eql?(row['old_login_id'])

          export_id = login['id'] unless nil
          exported_sis_id = login['sis_user_id'] unless nil
          break
        end
        if parsed_data && exported_sis_id.eql?(row['user_id'])
          # binding.pry
          api_url = "#{base_url}/api/v1/users/sis_user_id:#{URI.encode(row['user_id'])}/logins/#{export_id}"
          delete_response = Typhoeus::Request.new(api_url,
                                                  method: :delete,
                                                  headers: { Authorization: "Bearer #{options[:token]}", 'Content-Type' => 'application/x-www-form-urlencoded' })
          # parse JSON data to save in readable array
          delete_response.on_complete do |response|
            if response.code.eql?(200)
              if options[:verbose].nil? || options[:verbose] == false
                puts "Success: #{exported_sis_id}: #{row['old_login_id']} deleted"
              else
                logger.info("Success: #{exported_sis_id}: #{row['old_login_id']} deleted")
              end
            else
              logger.error("(1) Unable to delete login for user #{exported_sis_id}: #{row['old_login_id']}. (#{response.body})")
              # hydra.queue(delete_response)
            end
          end

          hydra.queue(delete_response)
        else
          logger.error("(2) Unable to delete login for user #{exported_sis_id}: #{row['old_login_id']}. (#{response.body})")
        end
      elsif response.code.eql?(404)
        logger.error("on #{row['user_id']}: User not found")
      elsif response.code.eql?(500)
        parsed_data = JSON.parse(response.body)
        logger.error("on #{row['user_id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{parsed_data['errors'][0]['message']} #{parsed_data['errors'][0]['error_code']} #{parsed_data['errors'][0]['message']} [error report: #{parsed_data['error_report_id']}])")
      # hydra.queue(get_response)
      else
        logger.error("on #{row['user_id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{response.body})")
      end
    end
    hydra.queue(get_response)
  end
end
hydra.run
logger.info("======== Run finished at #{Time.now} ========")
