version = '20180710-1'
require 'optparse'
require 'typhoeus'
require 'csv'
require 'json'
require 'URI'
require 'YAML'

options = { import_options: {} }
parse = OptionParser.new do |opts|
  opts.banner = 'Usage: script.rb [options]'
  opts.on('-c', '--client [CLIENT_ALIAS]', String, 'Alias for client. Other field not required when provided') do |a|
    if File.directory?(a) && File.exist?("#{a}/#{a}.yaml")
      coptions = YAML.load_file("#{a}/#{a}.yaml")
      puts coptions
      options = options.merge(coptions)
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
  opts.on('-i', '--infile FILE_PATH', String, 'Canvas Input file') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:infile] = a) : (puts 'ERROR: File does not exist!')
  end
  opts.on('-o', '--options [co]', String, 'SIS Import options. Include all options with no spaces (example: -o o', '   o - Override UI Changes', '   c - Clear Stickiness (requires o)') do |a|
    a.downcase!
    a.split('').each do |i|
      case i
      when 'c'
        options[:import_options]['clear_sis_stickiness'] = true
      when 'o'
        options[:import_options]['override_sis_stickiness'] = true
      end
    end
  end
  opts.on('-a', '--infilealias ALIAS', String, 'Input file alias', '   remap (or r) - Use the analysis remap file', '   unmatched (or u) - Use the analysis unmatched file', '   unmatchedremap (or t) - Use the analysis unmatched remap file', '   onlymatchid (or o) - Use the analysis only matched on ID file') do |a|
    analysisdir = "#{options[:client]}/analysis"
    case a
    when 'remap', 'r'
      a = "#{analysisdir}/#{options[:client]}-remapdata.csv"
    when 'unmatchedremap', 't'
      a = "#{analysisdir}/#{options[:client]}-unmatched_users-change-user_id.csv"
    when 'onlymatchid', 'o'
      a = "#{analysisdir}/#{options[:client]}-only_matched_user_id.csv"
    when 'unmatched', 'u'
      a = "#{analysisdir}/#{options[:client]}-unmatched_staff_users.csv"
      File.exist?(a) ? (options[:infile] = a) : a = "#{analysisdir}/#{options[:client]}-unmatched_users-change-login_id.csv"
      options[:import_options]['override_sis_stickiness'] = true
    end
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
options[:import_options]['attachment'] = File.open(options[:infile])
request = Typhoeus::Request.new(base_url + '/api/v1/accounts/self/sis_imports?import_type=instructure_csv',
                                method: :post,
                                headers: { Authorization: "Bearer #{options[:token]}" },
                                body: options[:import_options])
response = request.run
if response.code == 200
  parsed = JSON.parse(response.body)
  import_id = parsed['id']
  puts "Import started (id: #{import_id})...please hold..."
  workflow_state = 'created'
  while %w[created importing].include?(workflow_state)
    sleep 5
    puts 'Checking import status...'
    request = Typhoeus::Request.new(base_url + "/api/v1/accounts/self/sis_imports/#{import_id}",
                                    method: :get,
                                    headers: { Authorization: "Bearer #{options[:token]}" })
    response = request.run
    parsed = JSON.parse(response.body)
    workflow_state = parsed['workflow_state']
    puts "   #{workflow_state}"
  end
  logger.info('The import is done (for good or for bad)! Here are the deets:')
  logger.info(JSON.pretty_generate(parsed))
  logger.info("Import Result: #{parsed['workflow_state']}")
  parsed['data']['counts'].each do |k, v|
    logger.info("   #{k}: #{v}") if v != 0
  end
else
  logger.error("Well that didn't work (2). Here is what we know:\nResponse Code: #{response.code}\nReponse Body: #{response.body}")
end
logger.info("======== Run finished at #{Time.now} ========")
