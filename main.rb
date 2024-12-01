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

def get_available_java_versions
  all_java_versions = [8, 11, 17, 21]
  available_java_versions = []

  all_java_versions.each do |java_version|
    available_java_versions << java_version if get_env_variable("JAVA_HOME_#{java_version}_X64")
  end

  available_java_versions.join(', ')
end

sdkman_dir = env_has_key('SDKMAN_DIR')
ac_selected_java_version = env_has_key('AC_SELECTED_JAVA_VERSION')
puts "Selected Java version: #{ac_selected_java_version.blue}"

selected_java_version = get_env_variable("JAVA_HOME_#{ac_selected_java_version}_X64")
unless selected_java_version
  abort_with1("Java version #{selected_java_version} is not available on the runner. Available Java versions: #{get_available_java_versions}.")
end

current_java_version = get_java_version
puts "Current Java version: #{current_java_version.blue}"

if ac_selected_java_version == current_java_version
  puts "Current Java version is already the same as the selected Java version: #{ac_selected_java_version}.".yellow
  exit 0
end

puts "Changing default Java version from #{current_java_version.blue} to selected #{ac_selected_java_version.blue}."
open(ENV['AC_ENV_FILE_PATH'], 'a') do |f|
  f.puts "JAVA_HOME=#{selected_java_version}"
end

run_command_with_log("bash -l -c \"source '#{sdkman_dir}/bin/sdkman-init.sh' && sdk default java $(basename #{selected_java_version})\"")

get_info_msg("New Java version: #{get_java_version(full_version: true)}")
