#!/usr/bin/env ruby
#
#

require 'time'
require 'tempfile'

ME=File.basename($0, ".rb")
MD=File.dirname(File.realpath($0))

# notification recipients
RECIP=File.join(MD, ME+".notify")
NOTIFY=File.exist?(RECIP) ? File.read(RECIP) : ""

class CheckKernelVersion
	RE_KERNEL_STRING_SPLIT=/\s+/

	class << self
		attr_accessor :kernels, :platform, :latest, :current, :kernels_map
	end

	def self.kernel_time(kernel)
		bits=kernel.split(RE_KERNEL_STRING_SPLIT, 2)
		raise "Unexpected kernel string: #{kernel}" unless bits.length == 2
		[ bits[0],Time.parse(bits[1]) ]
	end

	def self.kernels_map
		# ensure that kernels list is initialized
		kernels
		unless defined? @@kernels_map
			@@kernels_map={}
			valid=@@kernels.length > 0
			@@kernels.each { |kernel|
				begin
					k,time=kernel_time(kernel)
					@@kernels_map[k]=time
				rescue => e
					valid=false
					puts e.to_s
				end
			}
			raise "kernel listing invalid" unless valid
		end
		@@kernels_map
	end

	def self.latest
		# set idx to 1 to change latest to an earlier kernel for testing
		idx=0
		unless defined? @@latest
			k,time=kernel_time(@@kernels[idx])
			@@latest={
				:kernel=>k,
				:time=>time
			}
		end
		@@latest
	end

	def self.current
		# ensure that kernels_map is initialized
		kernels_map
		unless defined? @@current
			kernel="kernel-#{%x/uname -r/.strip}"
			time=@@kernels_map[kernel]
			raise "Kernel from 'uname -r' not found in kernel map: #{kernel}" if time.nil?
			@@current={
				:kernel=>kernel,
				:time=>time
			}
		end
		@@current
	end

	# kernel-4.13.5-200.fc26.x86_64                 Wed 11 Oct 2017 02:00:36 AM EDT
	# kernel-4.13.4-200.fc26.x86_64                 Thu 05 Oct 2017 02:01:48 AM EDT
	# kernel-4.12.14-300.fc26.x86_64                Thu 28 Sep 2017 02:00:35 AM EDT
	def self.kernels
		unless defined? @@kernels
			@@kernels = %x/rpm -q kernel --last/.split(/\n/)
			kernels_map
			latest
			current
		end
		@@kernels
	rescue => e
		raise "Failed to list kernels: "+e.to_s
	end

	def self.platform
		@@platform=%x/uname -p/.strip
	rescue => e
		raise "Failed to grok uname platform string"
	end

	def self.is_current
		current
		latest
		@@current[:kernel].eql?(@@latest[:kernel]) && @@current[:time].eql?(@@latest[:time])
	end
	
	def self.as_string(kernel, time)
		"#{kernel} [#{time}]"
	end

	def self.map_as_string(entry)
		as_string(entry[:kernel], entry[:time])
	end

	def self.kernel_dump_test(out=STDOUT)
		out.puts "      Number of kernels=#{kernels.length}"
		out.puts "             Kernel map="+kernels_map.inspect
		out.puts "         Running kernel="+map_as_string(@@current)
		out.puts "          Latest kernel="+map_as_string(@@latest)
		kernels_map.sort_by { |k,t| t }.reverse.each { |kernel,time|
			out.puts "                 Kernel="+as_string(kernel, time)
		}
		out.puts "        Test if current="+is_current.inspect

		out.puts
	end

	def self.notify(email, quiet=true)
		return 0 if is_current

		output = Tempfile.new(ME)

		kernel_dump_test(output)
		summary(output)

		output.flush
		output.close

		host=%x/hostname -s/.strip

		# mail -s #{host}: new kernel available #{@@latest}" -a #{output.path}
		cmd=%/cat #{output.path} | mail -s "#{host}: new kernel available #{@@latest[:kernel]}" #{email}/

		unless quiet
			puts cmd
			puts %x/cat #{output.path}/
		end

		%x/#{cmd}/ unless email.empty?

		is_current
	end

	def self.summary(out=STDOUT)
		out.puts "Running = #{CheckKernelVersion.map_as_string(CheckKernelVersion.current)}"
		out.puts " Newest = #{CheckKernelVersion.map_as_string(CheckKernelVersion.latest)}"
	end

end

puts "Warning: email recipients file not found: #{RECIP}" if NOTIFY.empty?

exit CheckKernelVersion.notify(NOTIFY, true)

