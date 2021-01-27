# Working as of 01/27/2021
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
domain = gets.chomp!.downcase

## TOKEN
puts 'Enter a valid access token to perform the API calls within this script'
token = STDIN.noecho(&:gets).chomp!

## CSV FILE
puts 'Enter the full file path for CSV data. EX: /Users/person/file/to/path.csv'
csv_file = gets.chomp!

## AUTHENTICATION PROVIDER ID IN USE?
puts 'Will you be setting the authentication_provider_id for the new logins? y/n'
auth_pro_id = if gets.chomp!.upcase == 'Y'
                'true'
              else
                'false'
              end

## SIS USER ID IN USE?
puts 'Will you be assigning SIS IDs to the new logins? y/n'
sis_id_used = if gets.chomp!.upcase == 'Y'
                'true'
              else
                'false'
              end

base_url = "https://#{domain}.#{env}instructure.com/api/v1/accounts/self/logins/"
default_headers = { Authorization: 'Bearer ' + token }

CSV.foreach(csv_file, headers: true) do |row|
  return raise "Invalid CSV headers: 'login_id' not found" if row['login_id'].nil?
  return raise "Invalid CSV headers: 'canvas_user_id' not found" if row['canvas_user_id'].nil?
  return raise "Invalid CSV headers: 'sis_user_id' not found" if row['sis_user_id'].nil? && sis_id_used == 'true'
  return raise "Invalid CSV headers: 'authentication_provider_id' not found" if row['authentication_provider_id'].nil? && auth_pro_id == 'true'

  response = Typhoeus.post(
    base_url,
    headers: default_headers,
    body: {
      user: {
        id: row['canvas_user_id'].to_i
      },
      login: {
        unique_id: row['login_id'],
        authentication_provider_id: row['authentication_provider_id'].to_s,
        sis_user_id: row['sis_user_id'].to_s
      }
    }
  )
  # parse JSON data to save in readable array
  data = JSON.parse(response.body)
  if [200, 201].include?(response.code)
    puts "#{row['canvas_user_id']} successfully updated"
  else
    puts "ERROR - HTTP Status #{response.code}. Login creation for user #{row['canvas_user_id']} failed"
  end
end
