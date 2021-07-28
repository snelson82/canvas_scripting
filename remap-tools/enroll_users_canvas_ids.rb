# Sample input CSV format:
# canvas_user_id,canvas_section_id,role
# 12,34245,student

version = '20170807-1'
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
logger = Logger.new(options[:infile] + '.log')
logger.formatter = proc do |severity, _datetime, _progname, msg|
  severity = severity == 'INFO' ? '' : "#{severity} "
  puts "#{severity}#{msg}"
  "#{severity}#{msg}\n"
end
logger.info("======== Run started at #{Time.now} ========")
############################## DO NOT CHANGE THESE VALUES #######################

hydra = Typhoeus::Hydra.new(max_concurrency: 10)
# First column is user account that will be merged into second column. #
raise 'Unable to run script, please check token, and/or URL.' unless Typhoeus.get(options[:url]).code == 200 || 302

hydra = Typhoeus::Hydra.new(max_concurrency: 10)

CSV.foreach(options[:infile], { headers: true }) do |row|
  user_role = case row['role'].downcase
              when 'student'
                'StudentEnrollment'
              when 'teacher'
                'TeacherEnrollment'
              when 'ta'
                'TaEnrollment'
              when 'designer'
                'DesignerEnrollment'
              else
                row['role']
              end

  api_call = "#{options[:url]}/api/v1/sections/#{row['canvas_section_id']}/enrollments"
  canvas_api = Typhoeus::Request.new(api_call,
                                     method: :post,
                                     params: { 'enrollment[user_id]' => row['canvas_user_id'],
                                               'enrollment[role]' => user_role,
                                               'enrollment[enrollment_state]' => 'active',
                                               'enrollment[notify]' => 0 },
                                     headers: { 'Authorization' => "Bearer #{options[:token]}" })
  canvas_api.on_complete do |response|
    if response.code == 200
      puts "Enrolled user #{row['canvas_user_id']} into section #{row['canvas_section_id']} as a #{row['role']}"
    else
      puts "Unable to enroll user #{row['canvas_user_id']} into section #{row['canvas_section_id']} as a #{row['role']}. (Code: #{response.code}) #{response.body}"
    end
  end
  hydra.queue(canvas_api)
end
hydra.run

puts 'Successfully enrolled users.'
