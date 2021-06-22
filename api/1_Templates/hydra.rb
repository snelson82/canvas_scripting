# WORKING AS OF 06-22-2021
require 'csv'
require 'json'
require 'typhoeus'
require 'io/console'

### Prompts to set ENV, DOMAIN, TOKEN, and CSV FILE PATH

## ENV
puts "For prod, hit enter. For Beta, enter 'beta'. For Test, enter 'test'"
env = gets.chomp!.downcase
env != '' ? env << '.' : env

## DOMAIN
puts 'Enter the domain, EX: <domain>.instructure.com'
DOMAIN = gets.chomp!.downcase
# DOMAIN = ''

## TOKEN
puts 'Enter a valid access token to perform the API calls within this script'
TOKEN = $stdin.noecho(&:gets).chomp!
# TOKEN = ''

################
### CSV FILE ###
################

puts 'Enter the full file path for CSV data. EX: /Users/person/file/to/path.csv'
MAPPING_FILE = gets.chomp!
# MAPPING_FILE = ''

# Kill if file doesn't exist
raise "CSV mapping file path is incomplete or file doesn't exist." unless File.exist?(MAPPING_FILE)

# Gather header values
required_headers = %w[user_id email] # fill this in with your headers with spaces escaped (This\ is\ one\ header)
csv_headers = CSV.open(MAPPING_FILE, &:readline)
required_headers.each do |header|
  raise "Invalid CSV headers: #{header} not found" unless csv_headers.include?(header)
end

################
################
################

API_URL = "https://#{DOMAIN}.#{env}instructure.com/api/v1/".freeze
API_HEADERS = { authorization: "Bearer #{TOKEN}" }.freeze
$hydra = Typhoeus::Hydra.new(max_concurrency: 10)

CSV.foreach(MAPPING_FILE, headers: true) do |row|
  request = Typhoeus::Request.new(
    "#{API_URL}/api_endpoint_goes_here_with_row_value_replacements",
    method: :put, # Update method appropriate for the API endpoint in use
    headers: API_HEADERS,
    body: {
      user: {
        email: row['email'].to_s
      }
    }
  )
  request.on_complete do |response|
    data = JSON.parse(response.body)
    # Use the next line to output any important value in testing or validation
    puts "edit user data: \n#{data['email']}" unless data['email']&.to_s == row['email']&.to_s

    # Typhoeus workflow to handle responses
    if response.success?
      puts "Successfully updated user #{row['user_id']}'s email address (#{response.code})"
    elsif response.timed_out?
      puts "ERROR: There was an issue processing user #{row['user_id']}'s email (#{response.code})"
    elsif response.code.zero?
      puts "ERROR: #{response.return_message}"
    else
      "HTTP request failed: #{response.code}"
    end
    # Slight pause to allow API resources to recharge
    sleep(0.2) if response.headers['X-Rate-Limit-Remaining'].to_i <= 200
  end
  $hydra.queue(request)
end

$hydra.run
