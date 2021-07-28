version = '20180711-1'
require 'optparse'
require 'csv'
require 'YAML'

# START From https://stackoverflow.com/questions/1235863/test-if-a-string-is-basically-an-integer-in-quotes-using-ruby
class String
  def is_i?
    /\A[-+]?\d+\z/ === self
  end
end
# END

def clean_name(indata)
  indata.downcase.gsub(/[^0-9A-Za-z]/, '')
end

def writecsv(filename, headers, data, use_sym, change_headers)
  csv = CSV.open(filename + '.csv', 'wb')
  use_headers = []
  if change_headers
    headers.each do |header|
      if change_headers[header]
        use_headers.push(change_headers[header])
      else
        use_headers.push(header)
      end
    end
  else
    use_headers = headers
  end
  csv << use_headers
  data.each do |row|
    out = []
    headers.each do |header|
      out << if use_sym
               row[header.to_sym]
             else
               row[header]
             end
    end
    csv << out
  end
  csv.close
end

options = {}
parse = OptionParser.new do |opts|
  opts.banner = 'Usage: script.rb [options]'
  opts.on('-c', '--client CLIENT_ALIAS', String, 'Alias for client. Other field not required when provided. (required)') do |a|
    if File.directory?(a) && File.exist?("#{a}/#{a}.yaml")
      options = YAML.load_file("#{a}/#{a}.yaml")
    else
      (puts 'ERROR: Client does not exist!')
    end
  end
  opts.on('-l', '--canvasfile [FILENAME]', String, 'Input SIS export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    puts '-s hit'
    File.exist?(a) ? (options[:canvas] = a) : (puts 'ERROR: Canvas SIS export user CSV file does not exist!')
  end
  # opts.on("-i", "--icfile [FILENAME]", String, "Input SIS App From PowerSchool staff export CSV file (required)") do |a|
  #     a="#{options[:client]}/#{a}" unless options[:client].nil?
  #     File.exist?(a) ? (options[:sisapp] = a) : (puts "ERROR: SIS App staff CSV file does not exist!")
  # end
  opts.on('-k', '--kimonostafffile [FILENAME]', String, 'Input Kimono staff export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:kimono] = a) : (puts 'ERROR: Kimono export CSV file does not exist!')
  end
  opts.on('-s', '--kimonostudentfile [FILENAME]', String, 'Input Kimono student export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:kimonostudent] = a) : (puts 'ERROR: Kimono export CSV file does not exist!')
  end
  opts.on('-m', '--matchcolumn [COLUMN_NAME]', String, 'Column header to match on for old SIS ID') do |a|
    options[:matchcolumn] = a
  end
  opts.on('-t', '--matchusertype [type]', String, 'Type of users to match', '   s: student', '   t: teacher/staff', 'a: Both students and staff/teachers') do |a|
    options[:matchusertypes] = a
  end
  opts.on('-s', '--skipdeleted', String, 'Skip Deleted Users') do |_a|
    options[:skipdeleted] = true
  end
  opts.on_tail('-h', '--help', "Show this message (#{version})") do
    puts opts
    exit
  end
end.parse!
if options[:client].nil?
  puts "ERROR: Client is required!\nUse -h for help.\n\n"
  exit
end
options[:matchcolumn] = 'num_sis_id' if options[:matchcolumn].nil?

if options[:kimono].nil?
  options[:kimono] = "#{options[:client]}/kimonostaffexport.csv"
  unless File.exist?(options[:kimono])
    puts 'ERROR: Kimono staff filename not provided and default name does not exists!'
    exit
  end
end
if options[:kimonostudent].nil?
  options[:kimonostudent] = "#{options[:client]}/kimonostudentexport.csv"
  unless File.exist?(options[:kimonostudent])
    puts 'ERROR: Kimono student filename not provided and default name does not exists!'
    exit
  end
end

if options[:canvas].nil?
  options[:canvas] = "#{options[:client]}/canvasuserprovisioning.csv"
  unless File.exist?(options[:canvas])
    puts 'Warning: Canvas user export filename not provided and default filename does not exists. Downloading report...'
    system("ruby ./get_prov_report.rb -c #{options[:client]} -d -f canvasuserprovisioning.csv")
    unless File.exist?(options[:canvas])
      puts 'ERROR: Canvas user SIS Export filename not provided and unable to download the file!'
      exit
    end
  end
end

analysisdir = "#{options[:client]}/analysis"
Dir.mkdir(analysisdir) unless Dir.exist?(analysisdir)

# puts "Loading SIS App Data..."
# sisapp = Hash.new
# CSV.foreach(options[:sisapp], headers:true) do |row|
#     sisapp['staff_'+row['id']] = row
# end
puts options[:matchusertypes]

case options[:matchusertypes]
when 's'
  kimono_file = [{ 'name' => 'Student', 'file' => options[:kimonostudent] }]
when 't'
  kimono_file = [{ 'name' => 'Staff', 'file' => options[:kimono] }]
when nil, 'a'
  kimono_file = [{ 'name' => 'Staff', 'file' => options[:kimono] }, { 'name' => 'Student', 'file' => options[:kimonostudent] }]
end
puts kimono_file

# Build comparison hashes
kimono_id = {}
kimono_lid = {}
duplicate_source_id_data = []
duplicate_source_id = {}
no_lid = [] # Array of users with no local_id
duplicate_local_id = {}
duplicate_local_id_data = []
kimono_headers = []

kimono_file.each do |kfile|
  puts "Loading Kimono #{kfile['name']} Data..."
  CSV.foreach(kfile['file'], headers: true) do |row|
    kimono_headers = row.headers if kimono_headers.empty?
    if kimono_id[row[options[:matchcolumn]]].nil? || kimono_id[row[options[:matchcolumn]]] == row
      kimono_id[row[options[:matchcolumn]]] = row
    elsif duplicate_source_id[row[options[:matchcolumn]]].nil?
      puts "   duplicate Kimono truncated source_id (#{row[options[:matchcolumn]]} - #{row['source_id']}) [1]"
      puts "   duplicate Kimono truncated source_id (#{kimono_id[row[options[:matchcolumn]]][options[:matchcolumn]]} - #{kimono_id[row[options[:matchcolumn]]]['source_id']}) [2]"
      this_data = {}
      that_data = {}
      kimono_headers.each do |header|
        this_data[header.to_sym] = row[header]
        that_data[header.to_sym] = kimono_id[row[options[:matchcolumn]]][header]
      end
      duplicate_source_id_data << that_data
      duplicate_source_id_data << this_data
      duplicate_source_id[row[options[:matchcolumn]]] = true
    else
      this_data = {}
      puts "   duplicate Kimono truncated source_id (#{row[options[:matchcolumn]]} - #{row['source_id']}) [+]"
      kimono_headers.each do |header|
        this_data[header.to_sym] = row[header]
      end
      duplicate_local_id_data << this_data
    end

    if row['local_id'].nil? || row['local_id'] == ''
      this_data = {}
      puts "   No Kimono local_id (source_id: #{row['source_id']})"
      kimono_headers.each do |header|
        this_data[header.to_sym] = row[header]
      end
      no_lid << this_data
    elsif kimono_lid[row['local_id']].nil? && duplicate_local_id[row['local_id']].nil?
      kimono_lid[row['local_id']] = row
    elsif duplicate_local_id[row['local_id']].nil?
      duplicate_local_id[row['local_id']] = [row['sis_user_id']]
      this_data = {}
      that_data = {}
      puts "   duplicate Kimono local_id (#{row['local_id']} - #{row['source_id']}) [1]"
      puts "   duplicate Kimono local_id (#{kimono_lid[row['local_id']]['local_id']} - #{kimono_lid[row['local_id']]['source_id']}) [2]"
      kimono_headers.each do |header|
        this_data[header.to_sym] = row[header]
        that_data[header.to_sym] = kimono_lid[row['local_id']][header]
      end
      duplicate_local_id_data << that_data
      duplicate_local_id_data << this_data
      kimono_lid[row['local_id']] = 'error'
    else
      duplicate_local_id[row['local_id']] << row['sis_user_id']
      this_data = {}
      puts "   duplicate Kimono local_id (#{row['local_id']}) [+]"
      kimono_headers.each do |header|
        this_data[header.to_sym] = row[header]
      end
      duplicate_local_id_data << this_data
    end
  end
end

puts "DANGER! Duplicate truncated source_ids: #{duplicate_source_id}" if duplicate_source_id.count > 0
# exit

canvas_headers = []
# Aray for data to be remapped
remap_data = []
no_remap_data = []
unknown_data = []
unmatched_data = []
potential_issues = []
only_user_id = []
missing_new_id = []
CSV.foreach(options[:canvas], headers: true) do |row|
  id = ''
  canvas_headers = row.headers if canvas_headers.empty?
  id = row['user_id'] if id == ''
  match_data = {}
  if id.nil? || id == ''
  # Do Nothing
  elsif id.is_i?
    puts "Working on user: #{row['user_id']}"
    login_id = row['login_id'].nil? ? '' : row['login_id'].downcase
    # try to get user's local_id
    not_matched = true
    # Section checks current line against the predicted Kimono legacy user_id
    if defined?(kimono_id[id]) && !kimono_id[id].nil?
      # try to get Kimono login_id
      defined?(kimono_id[id]['login_id']) && !kimono_id[id]['login_id'].nil? ? (klogin_id = kimono_id[id]['login_id'].downcase) : (klogin_id = '')
      defined?(kimono_id[id]['first_name']) && defined?(kimono_id[id]['last_name']) && !kimono_id[id]['last_name'].nil? && !kimono_id[id]['first_name'].nil? ? (kname = "#{clean_name(kimono_id[id]['first_name'])}~#{clean_name(kimono_id[id]['last_name'])}") : (kname = '')
      defined?(row['first_name']) && defined?(row['last_name']) && !row['last_name'].nil? && !row['first_name'].nil? ? (cname = "#{clean_name(row['first_name'])}~#{clean_name(row['last_name'])}") : (cname = '')
      # See if the current line matches on Kimono login_id
      if kimono_id[id]['sis_user_id'].nil? || kimono_id[id]['sis_user_id'] == ''
        this_data = {}
        puts "   user with Canvsas user_id #{id} has no new SIS ID"
        canvas_headers.each do |header|
          this_data[header.to_sym] = row[header]
        end
        missing_new_id << this_data
      elsif !klogin_id.empty? && login_id == klogin_id
        puts "   looks like a match (old ID and login_id), so #{row['user_id']} -> #{kimono_id[id]['sis_user_id']}"
        not_matched = false
        match_data[:method] = 'old_user_id+login_id'
        match_data[:match_data] = "#{klogin_id}=#{login_id}"
      elsif kname != '' && kname == cname
        puts "   looks like a match (old ID and name), so #{row['user_id']} -> #{kimono_id[id]['sis_user_id']}"
        not_matched = false
        match_data[:method] = 'old_user_id+name'
        match_data[:match_data] = "#{kname}=#{cname}"
      elsif !klogin_id.empty? && row['status'].downcase != 'deleted' && !options[:skipdeleted]
        puts '   looks like this user matched on user_id, but nothing else. Setting aside.'
        only_user_id << {
          old_id: row['user_id'],
          new_id: kimono_id[id]['sis_user_id'],
          canvas_login_id: row['login_id'],
          kimono_login_id: kimono_id[id]['login_id'],
          canvas_last_name: row['last_name'],
          kimono_last_name: kimono_id[id]['last_name'],
          canvas_first_name: row['first_name'],
          kimono_first_name: kimono_id[id]['first_name'],
          type: 'user'
        }
      end

      unless not_matched
        match_data[:old_id] = row['user_id']
        match_data[:new_id] = kimono_id[id]['sis_user_id']
        match_data[:canvas_user_id] = row['canvas_user_id']
        match_data[:canvas_login_id] = row['login_id']
        match_data[:kimono_login_id] = kimono_id[id]['login_id']
      end
    end

    if row['status'].downcase == 'deleted' && !options[:skipdeleted]
      match_data[:method] = 'deleted'
      match_data[:match_data] = 'deleted user'
      match_data[:old_id] = row['user_id']
      match_data[:new_id] = "deleted-_-#{row['user_id']}"
      match_data[:canvas_user_id] = row['canvas_user_id']
      match_data[:canvas_login_id] = row['login_id']
      not_matched = false
    end

    if not_matched
      this_data = {}
      puts "   user with user_id:#{id} not in Kimono"
      canvas_headers.each do |header|
        this_data[header.to_sym] = row[header]
      end
      this_data[:unmatched_login_id] = "unmatched_-_#{this_data[:login_id]}"
      this_data[:unmatched_user_id] = "unmatched_-_#{this_data[:user_id]}"
      this_data[:unmatched_type] = 'user'
      unmatched_data << this_data
    else
      match_data[:type] = 'user'
      if match_data[:old_id] == match_data[:new_id]
        no_remap_data << match_data
      else
        remap_data << match_data
      end
    end
  elsif row['status'].downcase == 'deleted' && !options[:skipdeleted]
    match_data[:method] = 'deleted'
    match_data[:match_data] = 'deleted user'
    match_data[:old_id] = row['user_id']
    match_data[:new_id] = "deleted-_-#{row['user_id']}"
    match_data[:canvas_user_id] = row['canvas_user_id']
    match_data[:canvas_login_id] = row['login_id']
    match_data[:type] = 'user'
    remap_data << match_data
  else
    # Unknown user_id type
    this_data = {}
    puts "unknown: #{id}"
    canvas_headers.each do |header|
      this_data[header.to_sym] = row[header]
    end
    if /\A[st]\d+\z/ === id
      potential_issues << this_data
    else
      unknown_data << this_data
    end
  end
end
unmatched_headers = canvas_headers.dup
unmatched_headers << 'unmatched_login_id'
unmatched_headers << 'unmatched_user_id'
puts "\nResult summary:"
puts "   Matched users for remap: #{remap_data.count}"
puts "   Matched users that do not need remaped: #{no_remap_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-remapdata", %w[old_id new_id type method match_data canvas_user_id canvas_login_id kimono_login_id], remap_data, true, false) unless remap_data.nil?
puts "   Unmatched users that cannot be remapped: #{unmatched_data.count}"
unless unmatched_data.nil?
  writecsv("#{analysisdir}/#{options[:client]}-unmatched_users-change-login_id", unmatched_headers, unmatched_data, true, { 'login_id' => 'previous-login_id', 'unmatched_login_id' => 'login_id' })
  writecsv("#{analysisdir}/#{options[:client]}-unmatched_users-change-user_id", %w[user_id unmatched_user_id unmatched_type login_id], unmatched_data, true, { 'user_id' => 'old_id', 'unmatched_user_id' => 'new_id', 'unmatched_type' => 'type', 'login_id' => 'canvas_login_id' })
end
puts "   Users that are not idenifiable as staff or students: #{unknown_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-unknown_users", canvas_headers, unknown_data, true, false) unless unknown_data.nil?
puts "   Kimono users that have duplicate local_ids: #{duplicate_local_id.count}"
writecsv("#{analysisdir}/#{options[:client]}-dup_local_ids", kimono_headers, duplicate_local_id_data, true, false) unless duplicate_local_id_data.nil?
puts "   #{'DANGER: ' if missing_new_id.count > 0}Canvas users with no new SIS ID: #{missing_new_id.count}"
writecsv("#{analysisdir}/#{options[:client]}-dup_tsource_ids", canvas_headers, missing_new_id, true, false) unless missing_new_id.nil?
puts "   #{'DANGER: ' if duplicate_source_id_data.count > 0}Kimono users that have duplicate truncated source_ids: #{duplicate_source_id_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-dup_tsource_ids", kimono_headers, duplicate_source_id_data, true, false) unless duplicate_source_id_data.nil?
puts "   #{'DANGER: ' if potential_issues.count > 0}Existing Canvas user_ids starting with t or s: #{potential_issues.count}"
writecsv("#{analysisdir}/#{options[:client]}-exising_users_with_ts", canvas_headers, potential_issues, true, false) unless potential_issues.nil?
puts "   #{'DANGER: ' if only_user_id.count > 0}Users that only matched user_id: #{only_user_id.count}"
writecsv("#{analysisdir}/#{options[:client]}-only_matched_user_id", %w[old_id new_id canvas_login_id kimono_login_id canvas_last_name kimono_last_name canvas_first_name kimono_first_name type], only_user_id, true, false) unless only_user_id.nil?
