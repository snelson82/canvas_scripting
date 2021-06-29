# Working as of 01/27/2021
require 'csv'
require 'json'
require 'byebug'
require 'typhoeus'
require 'io/console'
require_relative '../../lib/progressbar'

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

puts 'Enter the full file path for CSV data. EX: /Users/person/path/to/file.csv'
MAPPING_FILE = gets.chomp!
# MAPPING_FILE = ''

# Kill if file doesn't exist
raise "CSV mapping file path is incomplete or file doesn't exist." unless File.exist?(MAPPING_FILE)

# Gather header values
required_headers = %w[canvas_user_id login_id] # fill this in with your headers with spaces escaped (This\ is\ one\ header)
csv_headers = CSV.open(MAPPING_FILE, &:readline)

puts 'Will you be setting the authentication_provider_id for the new logins? y/n'
AUTH_PRO_ID = if gets.chomp!.upcase == 'Y'
                'true'
              else
                'false'
              end

puts 'Will you be assigning SIS IDs to the new logins? y/n'
SIS_ID_USED = if gets.chomp!.upcase == 'Y'
                'true'
              else
                'false'
              end

required_headers << 'authentication_provider_id' if AUTH_PRO_ID == 'true'
required_headers << 'sis_user_id' if SIS_ID_USED == 'true'

required_headers.each do |header|
  raise "Invalid CSV headers: #{header} not found" unless csv_headers.include?(header)
end

API_URL = "https://#{DOMAIN}.#{env}instructure.com/api/v1/accounts/self/logins/".freeze
API_HEADERS = { authorization: "Bearer #{TOKEN}" }.freeze

CSV.foreach(MAPPING_FILE, headers: true) do |row|
  # Add additional data checks to skip the row if needed
  @id        = row['canvas_user_id'].to_i
  @unique_id = row['login_id']

  request = if AUTH_PRO_ID == 'true' && SIS_ID_USED == 'true'
              Typhoeus::Request.new(
                API_URL,
                method: :post,
                headers: API_HEADERS,
                body: {
                  user: {
                    id: @id
                  },
                  login: {
                    unique_id: @unique_id,
                    authentication_provider_id: row['authentication_provider_id'].to_s,
                    sis_user_id: row['sis_user_id'].to_s
                  }
                }
              )
            elsif AUTH_PRO_ID == 'true' && SIS_ID_USED == 'false'
              Typhoeus::Request.new(
                API_URL,
                method: :post,
                headers: API_HEADERS,
                body: {
                  user: {
                    id: @id
                  },
                  login: {
                    unique_id: @unique_id,
                    authentication_provider_id: row['authentication_provider_id'].to_s
                  }
                }
              )
            elsif AUTH_PRO_ID == 'false' && SIS_ID_USED == 'true'
              Typhoeus::Request.new(
                API_URL,
                method: :post,
                headers: API_HEADERS,
                body: {
                  user: {
                    id: @id
                  },
                  login: {
                    unique_id: @unique_id,
                    sis_user_id: row['sis_user_id'].to_s
                  }
                }
              )
            elsif AUTH_PRO_ID == 'false' && SIS_ID_USED == 'false'
              Typhoeus::Request.new(
                API_URL,
                method: :post,
                headers: API_HEADERS,
                body: {
                  user: {
                    id: @id
                  },
                  login: {
                    unique_id: @unique_id
                  }
                }
              )
            else
              raise 'Error: AUTH_PRO_ID and/or SIS_ID_USED are not correctly being set to true/false'
            end
  request.on_complete do |response|
    data = JSON.parse(response.body)
    # Use the next line to output any important value in testing or validation

    # Typhoeus workflow to handle responses
    if response.success?
      puts "The user with the canvas_id of #{row['canvas_user_id']} was updated successfully"
    elsif response.timed_out?
      puts "ERROR (#{response.code}) - Request timed out"
    elsif response.code.zero?
      puts "ERROR (#{response.code}) - #{response.return_message}"
    else
      puts "ERROR (#{response.code}) - #{data['errors'].keys.first}: #{data['errors'][data['errors'].keys.first].first['message']}"
    end
    # Slight pause to allow API resources to recharge
    sleep(0.2) if response.headers['X-Rate-Limit-Remaining'].to_i <= 200
  end
  request.run
end
