version = '20170803-1'
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
options[:infile] = "#{options[:client]}/analysis/#{options[:client]}-remapdata.csv" if options[:infile].nil? && !options[:client].nil? && File.exist?("#{options[:client]}/analysis/#{options[:client]}-remapdata.csv")
if options[:url].nil? || options[:token].nil? || options[:infile].nil?
  puts options
  puts "ERROR: Missing required fields!\nUse -h for help.\n\n"
  exit
end

# output_csv = options[:infile]+".log"        # put the full path to a blank csv file to have the errors written in.
logger = Logger.new(options[:infile] + '.log')
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
    logger.fatal("Error: Input file #{options[:infile]} must contain old_id and new_login_id columns")
    exit
  else
    # puts base_url, options[:token]
    api_url = "#{base_url}/api/v1/users/sis_user_id:#{URI.encode(row['old_id'])}/logins?per_page=100"
    get_response = Typhoeus::Request.new(api_url,
                                         method: :get,
                                         headers: { Authorization: "Bearer #{options[:token]}" })

    get_response.on_complete do |response|
      export_id = ''
      exported_sis_id = ''
      parsed_data = nil

      if response.code.eql?(200)
        parsed_data = JSON.parse(response.body)
        parsed_data.each do |login|
          next unless login['sis_user_id'].eql?(row['old_id'])

          export_id = login['id'] unless nil
          exported_sis_id = login['sis_user_id'] unless nil
          break
        end
        if parsed_data && exported_sis_id.eql?(row['old_id'])
          # binding.pry
          api_url = "#{base_url}/api/v1/accounts/self/logins/#{export_id}"
          put_response = Typhoeus::Request.new(api_url,
                                               method: :put,
                                               headers: { Authorization: "Bearer #{options[:token]}", 'Content-Type' => 'application/x-www-form-urlencoded' },
                                               params: { 'login[sis_user_id]' => row['new_id'] })
          # parse JSON data to save in readable array
          put_response.on_complete do |response|
            if response.code.eql?(200)
              if options[:verbose].nil? || options[:verbose] == false
                puts "Success: #{exported_sis_id} -> #{row['new_id']}"
              else
                logger.info("Success: #{exported_sis_id} -> #{row['new_id']}")
              end
            elsif response.body['is already in use']
              logger.error("on #{row['old_id']}: new_id #{row['new_id']} is already in use")
            else
              logger.error("Unable to update sis_user_id for user #{exported_sis_id} to #{row['new_id']}. (#{response.body})")
              # hydra.queue(put_response)
            end
          end

          hydra.queue(put_response)
        else
          # puts "Error on #{row['old_id']}: exported sis_user_id is different than the old_user_sis_id row in the csv file"
          logger.error("on #{row['old_id']}: exported sis_user_id is different than the old_user_sis_id row in the csv file")
        end
      elsif response.code.eql?(404)
        logger.error("on #{row['old_id']}: User not found")
      elsif response.code.eql?(500)
        parsed_data = JSON.parse(response.body)
        logger.error("on #{row['old_id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{parsed_data['errors'][0]['message']} #{parsed_data['errors'][0]['error_code']} #{parsed_data['errors'][0]['message']} [error report: #{parsed_data['error_report_id']}])")
      # hydra.queue(get_response)
      elsif response.body['is already in use']
        logger.error("on #{row['old_id']}: new_account_id #{row['new_id']} is already in use")
      else
        logger.error("on #{row['old_id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{response.body})")
      end
    end
    hydra.queue(get_response)
  end
end
hydra.run
logger.info("======== Run finished at #{Time.now} ========")
