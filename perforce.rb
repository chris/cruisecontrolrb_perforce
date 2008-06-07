require 'builder_error'

# Perforce source control implementation for CruiseControl.rb
# Written by Christopher Bailey, mailto:chris@cobaltedge.com
class Perforce
  include CommandLine

  attr_accessor :port, :client_spec, :username, :password, :path

	MAX_CHANGELISTS_TO_FETCH = 25
	
  def initialize(options = {})
    @port, @clientspec, @username, @password, @path, @interactive = 
          options.delete(:port), options.delete(:clientspec), 
					options.delete(:user), options.delete(:password), 
					options.delete(:path), options.delete(:interactive)
    raise "don't know how to handle '#{options.keys.first}'" if options.length > 0
    @clientspec or raise 'P4 Clientspec not specified'
    @port or raise 'P4 Port not specified'
    @username or raise 'P4 username not specified'
    @password or raise 'P4 password not specified'
    @path or raise 'P4 depot path not specified'
  end

  def checkout(target_directory, revision = nil)
		# No need for target_directory with Perforce, since this is controlled by
		# the clientspec.

		options = ""
    options << "#{@path}##{revision_number(revision)}" unless revision.nil?

    # need to read from command output, because otherwise tests break
    p4(:sync, options).each {|line| puts line.to_s }
  end

  def latest_revision(project)
		# Get the latest changelist for this project
		change = p4(:changes, "-m 1 #{@path}").first
		
		# TODO: This isn't right - changesets I believe is supposed to be the set
		# of files that were changed as part of this changelist.
		changesets = [ ChangesetEntry.new(change['status'], change['desc']) ]
		Revision.new(change['change'].to_i, change['user'], Time.at(change['time'].to_i), change['desc'], changesets)
  end

  def revisions_since(project, revision_number)
		# This should get all changelists since the last one we used, but when using
		# the -R flag with P4 it only seems to get the latest one.
		changelists = p4(:changes, "-m #{MAX_CHANGELISTS_TO_FETCH} #{@path}@#{revision_number},#head")
		
		changes = Array.new
		changelists.each do |cl| 
			changeset = [ ChangesetEntry.new(cl['status'], cl['desc']) ]
			changes << Revision.new(cl['change'].to_i, cl['user'], Time.at(cl['time'].to_i), cl['desc'], changeset)
		end
    changes.delete_if { |r| r.number == revision_number }

		changes
  end

  SYNC_PATTERN = /^(\/\/.+#\d+) - (\w+) .+$/
  def update(project, revision = nil)
		sync_output = p4(:sync, revision.nil? ? "" : "#{@path}@#{revision_number(revision)}")
		synced_files = Array.new
		
		sync_output.each do |line|
      match = SYNC_PATTERN.match(line['data'])
      if match
        file, operation = match[1..2]
        synced_files << ChangesetEntry.new(operation, file)
      end
    end.compact

		synced_files
  end
  
  private
  
	# Execute a P4 command, and return an array of the resulting output lines
	# The array will contain a hash for each line out output
  def p4(operation, options = nil)
		p4cmd = "p4 -R -p #{@port} -c #{@clientspec} -u #{@username} -P #{@password} "
		p4cmd << "#{operation.to_s}"
		p4cmd << " " << options if options
		
		p4_output = Array.new
		IO.popen(p4cmd, "rb") do |file|
		  while not file.eof
		    p4_output << Marshal.load(file)
		  end
		end
		
		p4_output
  end

  def revision_number(revision)
    revision.respond_to?(:number) ? revision.number : revision.to_i
  end
  
  Info = Struct.new :revision, :last_changed_revision, :last_changed_author
end
