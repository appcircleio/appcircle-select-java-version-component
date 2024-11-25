require 'open3'
require 'colored'

def get_info_msg(message)
	puts " \n#{message.green}"
end

def get_env_variable(key)
  return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end
 
def env_has_key(key)
	value = get_env_variable(key)
	return value unless value.nil? || value.empty?

	abort("Input #{key} is missing.")
end

def run_command(command)
	puts "@@[command] #{command}"
	stdout_str, stderr_str, status = Open3.capture3(command)

	if status.success?
		puts stdout_str unless stdout_str.empty?
		puts stderr_str unless stderr_str.empty?
		return stderr_str.empty? ? stdout_str : stderr_str
	else
		puts "@@[error] Command failed:\n#{stderr_str}"
		raise stderr_str
	end
end

def abort_with1(message)
	puts "@@[error] #{message}".red
	exit 1
end

def get_available_java_versions()
	all_java_versions = [8, 11, 17, 21]
	available_java_versions = []

	all_java_versions.each do |java_version|
		available_java_versions << java_version unless !get_env_variable("JAVA_HOME_#{java_version}_X64")
	end

	available_java_versions.join(', ')
end

sdkman_dir = env_has_key('SDKMAN_DIR')
ac_selected_java_version = env_has_key('AC_SELECTED_JAVA_VERSION')
puts "Selected Java version: #{ac_selected_java_version}"

selected_java_version = get_env_variable("JAVA_HOME_#{ac_selected_java_version}_X64")
if !selected_java_version
  abort_with1("Java version #{selected_java_version} is not available on the runner. Available Java versions: #{get_available_java_versions()}.")
end

current_java_version = run_command('javac -version').match(/javac (\d+)\.\d+\.\d+/)[1]
puts "Current Java Version: #{current_java_version}"

if ac_selected_java_version == current_java_version
	puts "Current Java version is already the same as the selected Java version: #{ac_selected_java_version}.".yellow
  exit 0
end

puts "Changing default Java version from #{current_java_version} to selected #{ac_selected_java_version}."
open(ENV['AC_ENV_FILE_PATH'], 'a') { |f|
	f.puts "JAVA_HOME=#{selected_java_version}"
}

run_command("bash -l -c \"source '#{sdkman_dir}/bin/sdkman-init.sh' && sdk default java $(basename #{selected_java_version})\"")
run_command("javac --version")

get_info_msg("New Java version (JAVA_HOME) path: #{selected_java_version}.")