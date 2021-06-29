require 'json'
require 'byebug'

puts 'Enter full file path for unformatted JSON:'
file_path = gets.chomp!.gsub("'", '')
puts "ERROR: File at #{file_path} doesn't exist. Check to ensure the file exists and the full file path is provided" unless File.exist?(file_path)
exit(1) unless File.exist?(file_path)

puts 'Enter the client name to be used (\'testing\' will be used if value is not provided):'
client = gets.chomp!(&:downcase)
[''].include?(client) ? client = 'testing' : client

formatted_file = File.open(File.expand_path("#{client}_formatted.json", 'sis_parsing/raw_json'), 'w')
op = JSON.parse(File.read(file_path))
formatted_file.write(JSON.pretty_generate(op))
formatted_file.close
