version="20170712-1"
require 'optparse'
require 'typhoeus'
require 'csv'
require 'json'
require 'URI'
require 'YAML'

options = {}
parse = OptionParser.new do |opts|
    opts.banner = "Usage: script.rb [options]"
    opts.on("-c", "--client [CLIENT_ALIAS]", String, "Alias for client. Other field not required when provided") do |a|
        if (File.directory?(a) && File.exists?("#{a}/#{a}.yaml"))
            options = YAML::load_file("#{a}/#{a}.yaml")
        else
            (puts "ERROR: Client does not exist!")
        end
    end
    opts.on("-u", "--url URL", String, "Canvas URL including https:// (ex: https://canvas.instructure.com) (required)") do |a|
        a.match(/^https\:\/\/([\w-]+\.+)+\w+$/i) ? (options[:url] = a) : (puts "ERROR: URL must be in form httpd://example.instructure.com")
    end
    opts.on("-t", "--token TOKEN", String, "Canvas API token (required)") do |a|
        options[:token] = a
    end
    opts.on("-i", "--infile FILE_PATH", String, "Input CSV file (required)") do |a|
        a="#{options[:client]}/#{a}" unless options[:client].nil?
        File.exist?(a) ? (options[:infile] = a) : (puts "ERROR: File does not exist!")
    end
    opts.on("-v","--verbose","Enable Verbose logging including success messages.") do |a|
        options[:verbose] = a
    end
    opts.on_tail("-h", "--help", "Show this message (#{version})") do
        puts opts
        exit
    end
end.parse!

if(options[:infile].nil? && !options[:client].nil?)
    unless File.exist?("#{options[:client]}/school.csv")
        puts "Warning: SISApp school.csv filename was not provided and the default file name does not exists."
        exit
    end
    options[:infile]="#{options[:client]}/school.csv"
end
if(options[:url].nil? || options[:token].nil? || options[:infile].nil?)
    puts options
    puts "ERROR: Missing required fields!\nUse -h for help.\n\n"
    exit
end

# output_csv = options[:infile]+".log"        # put the full path to a blank csv file to have the errors written in.
logger = Logger.new(options[:infile]+".log")
logger.formatter = proc do |severity, datetime, progname, msg|
    severity == "INFO" ? severity = "" : severity = "#{severity} "
    puts "#{severity}#{msg}"
    "#{severity}#{msg}\n"
end
logger.info("======== Run started at #{Time.now} ========")
############################## DO NOT CHANGE THESE VALUES #######################
logger.info("Running file: #{options[:infile]}")
base_url = options[:url]
hydra = Typhoeus::Hydra.new(max_concurrency: 10)
had_error = false
CSV.foreach(options[:infile], headers: true) do |row|
    if !row.headers.include?('id') || !row.headers.include?('school_number')
        logger.fatal("Input file #{options[:infile]} must contain id and school_number columns")
        exit
    else
        # puts base_url, options[:token]
        api_url = "#{base_url}/api/v1/accounts/sis_account_id:#{URI::encode(row['id'])}"
        get_response = Typhoeus::Request.new(api_url,
                                                method: :put,
                                                headers: { Authorization: "Bearer #{options[:token]}" },
                                                params: { 'account[sis_account_id]' => "remap-#{row['id']}" })

        get_response.on_complete do |response|
            parsed_data = nil
            if response.code.eql?(200)
                parsed_data = JSON.parse(response.body)
                if parsed_data['sis_account_id'] == "remap-#{row['id']}"
                    options[:verbose] == true ? logger.info("Success: #{row['id']} -> #{parsed_data['sis_account_id']}") : (puts "Success: #{row['id']} -> #{parsed_data['sis_account_id']}")
                else
                    logger.error("on #{row['id']}: Unable to set account's SIS ID to #{row['school_number']}")
                    had_error = true
                end
            else
                if response.code.eql?(404)
                    logger.error("on #{row['id']}: Account not found")
                elsif response.code.eql?(500)
                    parsed_data = JSON.parse(response.body)
                    logger.error("on #{row['id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{parsed_data['errors'][0]['message']} #{parsed_data['errors'][0]['error_code']} #{parsed_data['errors'][0]['message']} [error report: #{parsed_data['error_report_id']}])")
                    # hydra.queue(get_response)
                elsif response.body["is already in use"]
                    logger.error("on #{row['id']}: school_number #{row['school_number']} is already in use")
                else
                    logger.error("on #{row['id']}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{response.body})")
                end
                had_error = true
            end
        end
        hydra.queue(get_response)
    end
end
hydra.run

if had_error
    logger.fatal("An error occured during change to interim ID. Process stopping.")
else
    logger.info("**Starting Remap to new IDs**")
    hydra = Typhoeus::Hydra.new(max_concurrency: 10)
    CSV.foreach(options[:infile], headers: true) do |row|
        if !row.headers.include?('id') || !row.headers.include?('school_number')
            logger.fatal("Input file #{options[:infile]} must contain id and school_number columns")
            exit
        else
            account_id = "remap-#{row['id']}"
            # puts base_url, options[:token]
            api_url = "#{base_url}/api/v1/accounts/sis_account_id:#{URI::encode(account_id)}"
            get_response = Typhoeus::Request.new(api_url,
                                                    method: :put,
                                                    headers: { Authorization: "Bearer #{options[:token]}" },
                                                    params: { 'account[sis_account_id]' => row['school_number'] })

            get_response.on_complete do |response|
                parsed_data = nil
                if response.code.eql?(200)
                    parsed_data = JSON.parse(response.body)
                    if parsed_data['sis_account_id'] == row['school_number']
                        options[:verbose] == true ? logger.info("Success: #{account_id} -> #{row['school_number']}") : (puts "Success: #{account_id} -> #{row['school_number']}")
                    else
                        logger.error("on #{account_id}: Unable to set account's SIS ID to #{row['school_number']}")
                    end
                else
                    if response.code.eql?(404)
                        logger.error("on #{account_id}: Account not found")
                    elsif response.code.eql?(500)
                        parsed_data = JSON.parse(response.body)
                        logger.error("on #{account_id}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{parsed_data['errors'][0]['message']} #{parsed_data['errors'][0]['error_code']} #{parsed_data['errors'][0]['message']} [error report: #{parsed_data['error_report_id']}])")
                        # hydra.queue(get_response)
                    elsif response.body["is already in use"]
                        logger.error("on #{account_id}: school_number #{row['school_number']} is already in use")
                    else
                        logger.error("on #{account_id}: Trouble connecting to #{api_url} while doing API call. (#{response.code}: #{response.body})")
                    end 
                end
            end
            hydra.queue(get_response)
        end
    end
    hydra.run
end
logger.info("========= Run finished at #{Time.now} =======")