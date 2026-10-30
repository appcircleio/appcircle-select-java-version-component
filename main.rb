require 'open3'
require 'colored'

def get_info_msg(message)
  puts " \n#{message.green}"
end

def get_env_variable(key)
  ENV[key].nil? || ENV[key] == '' ? nil : ENV[key]
end

def env_has_key(key)
  value = get_env_variable(key)
  return value unless value.nil? || value.empty?

  abort("Input #{key} is missing.")
end

def run_command(command)
  stdout_str, stderr_str, status = Open3.capture3(command)
  return stderr_str.empty? ? stdout_str : stderr_str if status.success?

  raise stderr_str
end

def run_command_with_log(command)
  puts "@@[command] #{command}"
  begin
    output = run_command(command)
    puts output unless output.empty?
    output
  rescue StandardError => e
    puts "@@[error] Command failed:\n#{e.message}"
    raise e
  end
end

def get_java_version(full_version: false)
  output = run_command('javac -version')
  version = output.match(/javac (\d+)(\.\d+\.\d+)?/)

  return "#{version[1]}#{version[2]}" if full_version

  version[1]
end

def abort_with1(message)
  puts "@@[error] #{message}".red
  exit 1
end

# Reads the installed versions from the JAVA_HOME_<version>_X64 variables of the runner.
def get_available_java_versions
  ENV.select { |key, value| key.match?(/\AJAVA_HOME_\d+_X64\z/) && !value.to_s.empty? }
     .keys
     .map { |key| key[/\d+/].to_i }
     .sort
     .join(', ')
end

# Points the SDKMAN `current` link to the candidate, which is what `sdk default java` does.
# Calling `sdk` is not necessary: it checks the internet connection at start and its legacy
# `default` command is deprecated.
def switch_sdkman_java(sdkman_dir, java_home)
  java_candidates_dir = File.join(sdkman_dir, 'candidates', 'java')
  candidate_dir = File.join(java_candidates_dir, File.basename(java_home))
  unless File.directory?(candidate_dir)
    abort_with1("Java candidate #{candidate_dir} is not installed in SDKMAN.")
  end

  current_link = File.join(java_candidates_dir, 'current')
  temp_link = "#{current_link}.#{Process.pid}.tmp"
  puts "@@[command] ln -sfn #{candidate_dir} #{current_link}"
  begin
    File.symlink(candidate_dir, temp_link)
    File.rename(temp_link, current_link)
  rescue SystemCallError => e
    File.delete(temp_link) if File.symlink?(temp_link)
    abort_with1("Failed to point #{current_link} to #{candidate_dir}: #{e.message}")
  end
end

sdkman_dir = env_has_key('SDKMAN_DIR')
ac_selected_java_version = env_has_key('AC_SELECTED_JAVA_VERSION')

selected_java_version = get_env_variable("JAVA_HOME_#{ac_selected_java_version}_X64")
unless selected_java_version
  abort_with1("Java version #{ac_selected_java_version} is not available on the runner. Available Java versions: #{get_available_java_versions}.")
end

current_java_version = get_java_version

puts "Current (default) Java version: #{current_java_version.blue}"
puts "Selected Java version: #{ac_selected_java_version.blue}"

if ac_selected_java_version == current_java_version
  puts 'The current Java version is already the same as the selected Java version.'.yellow
  exit 0
end

puts "Changing the default Java version from #{current_java_version.blue} to #{ac_selected_java_version.blue}."
switch_sdkman_java(sdkman_dir, selected_java_version)

open(ENV['AC_ENV_FILE_PATH'], 'a') do |f|
  f.puts "JAVA_HOME=#{selected_java_version}"
end

get_info_msg("Java version: #{get_java_version(full_version: true)}")
