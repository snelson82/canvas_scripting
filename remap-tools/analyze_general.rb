version = '20190521-1'
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
  csv = CSV.open("#{filename}.csv", 'wb')
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
  opts.on('-e', '--canvasfile [FILENAME]', String, 'Input SIS export CSV file') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:canvas] = a) : (puts 'ERROR: Canvas SIS export user CSV file does not exist!')
  end
  opts.on('-z', '--canvasadminfile [FILENAME]', String, 'Input SIS admin user export CSV file') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:canvasadmins] = a) : (puts 'ERROR: Canvas SIS admin user CSV file does not exist!')
  end
  opts.on('-x', '--canvaslastloginfile [FILENAME]', String, 'Input SIS last login CSV file') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:canvaslastlogin] = a) : (puts 'ERROR: Canvas SIS export admin CSV file does not exist!')
  end
  # opts.on("-i", "--icfile [FILENAME]", String, "Input SIS App From PowerSchool staff export CSV file (required)") do |a|
  #     a="#{options[:client]}/#{a}" unless options[:client].nil?
  #     File.exist?(a) ? (options[:sisapp] = a) : (puts "ERROR: SIS App staff CSV file does not exist!")
  # end
  opts.on('-j', '--stafffile [FILENAME]', String, 'Input staff export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:kimono] = a) : (puts 'ERROR: Kimono export CSV file does not exist!')
  end
  opts.on('-s', '--studentfile [FILENAME]', String, 'Input student export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:kimonostudent] = a) : (puts 'ERROR: Kimono export CSV file does not exist!')
  end
  opts.on('-k', '--matchcolumn [COLUMN_NAME]', String, 'Input column header to match on for old SIS ID') do |a|
    options[:matchcolumn] = a
  end
  opts.on('-m', '--matchcanvascolumn [COLUMN_NAME]', String, 'Canvas file column header to match on for old SIS ID') do |a|
    options[:matchcanvascolumn] = a
  end
  opts.on('-t', '--matchusertype [type]', String, 'Type of users to match', '   s: student', '   t: teacher/staff', 'a: Both students and staff/teachers') do |a|
    options[:matchusertypes] = a
  end
  opts.on('-n', '--newidcolumn [COLUMN_NAME]', String, 'Input column header of the new SIS ID') do |a|
    options[:newidcolumn] = a
  end
  opts.on('-d', '--skipdeleted', String, 'Skip Deleted Users') do |_a|
    options[:skipdeleted] = true
  end
  opts.on('-a', '--skiplastaccess', String, 'Skip Last User Access Report') do |_a|
    options[:skiplastaccess] = true
  end
  opts.on('-g', '--skiploginmatch', String, 'Skip login_id match') do |_a|
    options[:skiploginmatch] = true
  end
  opts.on('-l', '--lowercasematch', String, 'Match Canvas value lowercase') do |_a|
    options[:lowercasematch] = true
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
options[:matchcanvascolumn] = 'user_id' if options[:matchcanvascolumn].nil?
options[:newidcolumn] = 'sis_user_id' if options[:matchcanvascolumn].nil?

puts options[:matchusertypes]

check_students = false
check_staff = false
kimono_file = []

case options[:matchusertypes]
when 's'
  check_students = true
  puts 'Processing Student File Only'
when 't'
  check_staff = true
  puts 'Processing Staff File Only'
when nil, 'a'
  check_students = true
  check_staff = true
  puts 'Processing Staff and Student Files'
end

if options[:kimono].nil? && check_staff
  options[:kimono] = "#{options[:client]}/kimonostaffexport.csv"
  unless File.exist?(options[:kimono])
    puts 'ERROR: Kimono staff filename not provided and default name does not exists!'
    exit
  end
end
if options[:kimonostudent].nil? && check_students
  options[:kimonostudent] = "#{options[:client]}/kimonostudentexport.csv"
  unless File.exist?(options[:kimonostudent])
    puts 'ERROR: Kimono student filename not provided and default name does not exists!'
    exit
  end

end
kimono_file.push({ 'name' => 'Staff', 'file' => options[:kimono] }) if check_staff
kimono_file.push({ 'name' => 'Student', 'file' => options[:kimonostudent] }) if check_students
puts kimono_file

if options[:canvas].nil?
  options[:canvas] = "#{options[:client]}/canvasuserprovisioning.csv"
  unless File.exist?(options[:canvas])
    puts 'Warning: Canvas user export filename not provided and default filename does not exists. Downloading report...'
    system("ruby ./get_prov_report.rb -c #{options[:client]} -d -o u -f canvasuserprovisioning.csv")
    unless File.exist?(options[:canvas])
      puts 'ERROR: Canvas user SIS Export filename not provided and unable to download the file!'
      exit
    end
  end
end
if options[:canvasadmins].nil?
  options[:canvasadmins] = "#{options[:client]}/canvasuseradmin.csv"
  unless File.exist?(options[:canvasadmins])
    puts 'Warning: Canvas admin export filename not provided and default filename does not exists. Downloading report...'
    system("ruby ./get_prov_report.rb -c #{options[:client]} -o d -f canvasuseradmin.csv")
    unless File.exist?(options[:canvasadmins])
      puts 'ERROR: Canvas admin SIS Export filename not provided and unable to download the file!'
      exit
    end
  end
end
if options[:canvaslastlogin].nil?
  options[:canvaslastlogin] = "#{options[:client]}/canvaslastlogin.csv"
  unless File.exist?(options[:canvaslastlogin]) || !options[:skiplastaccess].nil?
    puts 'Warning: Canvas last login export filename not provided and default filename does not exists. Downloading report...'
    system("ruby ./get_last_access_report.rb -c #{options[:client]} -f canvaslastlogin.csv")
    unless File.exist?(options[:canvaslastlogin])
      puts 'ERROR: Canvas last login SIS Export filename not provided and unable to download the file!'
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
    unless row[options[:matchcolumn]].nil? || row[options[:matchcolumn]].strip == ''
      kid = row[options[:matchcolumn]]
      kid = row[options[:matchcolumn]].downcase if options[:lowercasematch]
      if kimono_id[kid].nil? || kimono_id[kid] == row
        kimono_id[kid] = row
      elsif duplicate_source_id[kid].nil?
        puts "   duplicate Kimono truncated source_id (#{kid} - #{row['source_id']}) [1]"
        puts "   duplicate Kimono truncated source_id (#{kimono_id[kid][options[:matchcolumn]]} - #{kimono_id[kid]['source_id']}) [2]"
        this_data = {}
        that_data = {}
        kimono_headers.each do |header|
          this_data[header.to_sym] = row[header]
          that_data[header.to_sym] = kimono_id[kid][header]
        end
        duplicate_source_id_data << that_data
        duplicate_source_id_data << this_data
        duplicate_source_id[kid] = true
      else
        this_data = {}
        puts "   duplicate Kimono truncated source_id (#{kid} - #{row['source_id']}) [+]"
        kimono_headers.each do |header|
          this_data[header.to_sym] = row[header]
        end
        duplicate_local_id_data << this_data
      end
    end
  end
end

last_login = {}
last_login_headers = []
if options[:skiplastaccess].nil?
  puts 'Loading Last Login Data...'
  CSV.foreach(options[:canvaslastlogin], headers: true) do |row|
    last_login_headers = row.headers if last_login_headers.empty?
    last_login[row['user id']] = row['last access at'] unless row['user sis id'] == ''
  end
else
  puts 'Skiping last login check...'
end

admin_users = {}
admin_users_headers = []
puts 'Loading Admin Data...'
CSV.foreach(options[:canvasadmins], headers: true) do |row|
  admin_users_headers = row.headers if admin_users_headers.empty?
  admin_users[row['canvas_user_id']] = 'true'
end

puts "DANGER! Duplicate input match values: #{duplicate_source_id}" if duplicate_source_id.count.positive?
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
  id = row[options[:matchcanvascolumn]] if id == ''
  id = id.downcase if !id.nil? && (options[:lowercasematch])
  match_data = {}
  if id.nil? || id == '' || row['user_id'].nil? || row['user_id'] == ''
  # Do Nothing
  elsif id != ''
    puts "Working on user: #{id}"
    login_id = if options[:matchcanvascolumn] == 'login_id' || options[:skiploginmatch]
                 ''
               else
                 row['login_id'].nil? ? '' : row['login_id'].downcase
               end
    # try to get user's local_id
    not_matched = true
    not_partial_matched = true
    # Section checks current line against the predicted Kimono legacy user_id
    if defined?(kimono_id[id]) && !kimono_id[id].nil? && row['status'].downcase != 'deleted'
      # try to get Kimono login_id
      defined?(kimono_id[id]['login_id']) && !kimono_id[id]['login_id'].nil? ? (klogin_id = kimono_id[id]['login_id'].downcase) : (klogin_id = '')
      defined?(kimono_id[id]['first_name']) && defined?(kimono_id[id]['last_name']) && !kimono_id[id]['last_name'].nil? && !kimono_id[id]['first_name'].nil? ? (kname = "#{clean_name(kimono_id[id]['first_name'])}~#{clean_name(kimono_id[id]['last_name'])}") : (kname = '')
      defined?(row['first_name']) && defined?(row['last_name']) && !row['last_name'].nil? && !row['first_name'].nil? ? (cname = "#{clean_name(row['first_name'])}~#{clean_name(row['last_name'])}") : (cname = '')
      # See if the current line matches on Kimono login_id
      if kimono_id[id][options[:newidcolumn]].nil? || kimono_id[id][options[:newidcolumn]] == ''
        this_data = {}
        puts "   user with Canvsas user_id #{id} has no new SIS ID"
        canvas_headers.each do |header|
          this_data[header.to_sym] = row[header]
        end
        missing_new_id << this_data
      elsif !klogin_id.empty? && login_id == klogin_id
        puts "   looks like a match (old ID and login_id), so #{row['user_id']} -> #{kimono_id[id][options[:newidcolumn]]}"
        not_matched = false
        match_data[:method] = 'old_user_id+login_id'
        match_data[:match_data] = "#{klogin_id}=#{login_id}"
      elsif kname != '' && kname == cname
        puts "   looks like a match (old ID and name), so #{row['user_id']} -> #{kimono_id[id][options[:newidcolumn]]}"
        not_matched = false
        match_data[:method] = 'old_user_id+name'
        match_data[:match_data] = "#{kname}=#{cname}"
      elsif !kimono_id[id].nil? && row['status'].downcase != 'deleted'
        puts '   looks like this user matched on user_id, but nothing else. Setting aside.'
        only_user_id << {
          old_id: row['user_id'],
          new_id: kimono_id[id][options[:newidcolumn]],
          canvas_login_id: row['login_id'],
          kimono_login_id: kimono_id[id]['login_id'],
          canvas_last_name: row['last_name'],
          kimono_last_name: kimono_id[id]['last_name'],
          canvas_first_name: row['first_name'],
          kimono_first_name: kimono_id[id]['first_name'],
          type: 'user'
        }
        not_partial_matched = false
      end

      unless not_matched
        match_data[:old_id] = row['user_id']
        match_data[:new_id] = kimono_id[id][options[:newidcolumn]]
        match_data[:canvas_user_id] = row['canvas_user_id']
        match_data[:canvas_login_id] = row['login_id']
        match_data[:kimono_login_id] = kimono_id[id]['login_id']
      end
    end

    if row['status'].downcase == 'deleted' && !options[:skipdeleted] && row['user_id'].slice(0, 10) != 'deleted-_-'
      match_data[:method] = 'deleted'
      match_data[:match_data] = 'deleted user'
      match_data[:old_id] = row['user_id']
      match_data[:new_id] = "deleted-_-#{row['user_id']}"
      match_data[:canvas_user_id] = row['canvas_user_id']
      match_data[:canvas_login_id] = row['login_id']
      not_matched = false
    end
    if row['user_id'].slice(0, 10) == 'deleted-_-' || row['user_id'].slice(0, 12) == 'unmatched_-_'
    # Skip...we already changed them.
    elsif not_matched && not_partial_matched
      this_data = {}
      puts "   user with user_id:#{id} not in Kimono"
      canvas_headers.each do |header|
        this_data[header.to_sym] = row[header]
      end
      this_data[:unmatched_login_id] = "unmatched_-_#{this_data[:login_id]}"
      this_data[:unmatched_user_id] = "unmatched_-_#{this_data[:user_id]}"
      this_data[:unmatched_type] = 'user'
      this_data[:last_access] = last_login[row['canvas_user_id']]
      this_data[:user_is_admin] = admin_users[row['canvas_user_id']].nil? ? 'no' : 'yes'
      unmatched_data << this_data
    elsif not_partial_matched
      match_data[:type] = 'user'
      if match_data[:old_id] == match_data[:new_id]
        no_remap_data << match_data
      else
        # match_data[:new_data_user_id] = kimono_id[id]['user_id']
        remap_data << match_data
      end
    end
  elsif row['status'].downcase == 'deleted' && !options[:skipdeleted] && id != '' && row['user_id'].slice(0, 10) != 'deleted-_-'
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
unmatched_headers << 'last_access'
unmatched_headers << 'user_is_admin'
puts "\nResult summary:"
puts "   Matched users for remap: #{remap_data.count}"
puts "   Matched users that do not need remaped: #{no_remap_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-remapdata", %w[old_id new_id type method match_data canvas_user_id canvas_login_id kimono_login_id new_data_user_id], remap_data, true, false) unless remap_data.nil?
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
writecsv("#{analysisdir}/#{options[:client]}-missing_new_id", missing_new_id[0].keys, missing_new_id, true, false) unless missing_new_id.empty?
puts "   #{'DANGER: ' if duplicate_source_id_data.count > 0}Kimono users that have duplicate input file match IDs: #{duplicate_source_id_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-dup_tsource_ids", kimono_headers, duplicate_source_id_data, true, false) unless duplicate_source_id_data.nil?
puts "   #{'DANGER: ' if potential_issues.count > 0}Existing Canvas user_ids starting with t or s: #{potential_issues.count}"
writecsv("#{analysisdir}/#{options[:client]}-exising_users_with_ts", canvas_headers, potential_issues, true, false) unless potential_issues.nil?
puts "   #{'DANGER: ' if only_user_id.count > 0}Users that only matched #{options[:matchcanvascolumn]}: #{only_user_id.count}"
writecsv("#{analysisdir}/#{options[:client]}-only_matched_user_id", %w[old_id new_id canvas_login_id kimono_login_id canvas_last_name kimono_last_name canvas_first_name kimono_first_name type], only_user_id, true, false) unless only_user_id.nil?
