require 'date'
require 'wikibot'
require 'andand'
require 'gacbot/categorytree'
require 'gacbot/version'
require 'ext/wikibot/page'
require 'colored'
require 'ext/colored'

module GACBot
  class Bot < WikiBot::Bot
    BACKLOG_COUNT = 10 # How many items to show in the backlog list
    EXCEPTION_NOMINATIONS = 3 # Min nominations a single person needs to make to be in the exceptions list
    EXCEPTION_TAG_AGE = 7 # Min age of GAReview, etc. tag to be an exception
    EXCEPTION_NOM_AGE = 30 # Min age of nomination to be an exception

    # Wikipedia pages/links
    ARTICLE_PAGE = "Wikipedia:Good article nominations"
    REPORT_PAGE = "#{ARTICLE_PAGE}/Report"
    TEMPLATE_PAGE = "Template:GACstats"
    BACKLOG_ITEMS_PAGE = "#{ARTICLE_PAGE}/backlog/items";
    BACKLOG_SUBPAGE = "#{REPORT_PAGE}/Backlog archive" 
    ARTICLE_LINK = "[[Wikipedia:Good article nominations#%s|%s]]"
    
    # Image codes
    IMG_OH = "[[Image:Symbol wait.svg|15px|On Hold]]"
    IMG_UR = "[[Image:Searchtool.svg|15px|Under Review]]"
    IMG_2O = "[[Image:Symbol neutral vote.svg|15px|2nd Opinion Requested]]"

    MAX_QUERY_TRIES = 3
    DELAY_BETWEEN_RETRIES = 10

    attr_reader :verbosity

    def initialize(username, password, options = {})
      @tree = CategoryTree.new
      @now = DateTime.now
      @options = options
      @verbosity = options[:verbosity] || 0

      unless options[:color]
        String.class_eval do
          def color(*); "" end
          def extra(*); "" end
        end
      end

      super(username, password, options)
      start unless options[:autostart] == false
    end

    def start
      bot_date = "2016-01-08"
      comment = "Generated at #{format_date(Time.now)} by #{@config.username} v#{self.version} (#{bot_date})"
      start_time = Time.now

      message "Starting GACBot#{ readonly ? " in readonly mode".light_blue : ""}."
      puts

      login
      setup
      get_daily_stats

      # Perform the edits
      generate_template unless @options[:no_template]
      update_backlog_items unless @options[:no_backlog]
      generate_report(comment) unless @options[:no_report] 

      logout
      message "Bot completed. #{page_writes.to_s.green} pages written, #{(Time.now - start_time).to_s.green}s elapsed."

    rescue WikiBot::APIError => e
      failed "MediaWiki API responded with error code '#{e.code}' with info '#{e.info}'."

    rescue WikiBot::Page::WriteError => e
      failed "Writing failed with status '#{e.message}'."  
    end

    def version
      GACBot::VERSION
    end

    def setup
      message "Collecting articles..."

      find = /<!-- NOMINATION CATEGORIES BEGIN HERE -->\s*(.*?)\s*<!-- NOMINATION CATEGORIES END HERE -->/im
      content = page(ARTICLE_PAGE).content.match(find)[1]
      @tree.add_categories(content)

      done

      verbose(3) do
        @tree.each do |node|
          next if node.isRoot?
          
          puts "#{"  " * (node.level - 1)}#{node.name}: #{node.total}"
        end

        puts "Total: #{@tree.total}"
        puts
      end
    end

    def get_daily_stats
      nom_archive = []
      @tree.each do |node|
        next if node.content.empty?
        nominations = node.content
        nominations.each do |nomination|
          on_hold = false
          under_review = false
          second_opinion = false

          nomination[:tags].each do |tag|
            on_hold = true if tag[:status] == "on_hold"
            under_review = true if tag[:status] == "under_review"
            second_opinion = true if tag[:status] == "second_opinion"
          end if !nomination[:tags].nil?

          nom_archive.push "#{CGI::escape(nomination[:article])};" +
            (on_hold ? '1' : '0') + ";" +
            (under_review ? '1' : '0') + ";" +
            (second_opinion ? '1' : '0')
        end
      end

      archive = File.new(data_file(:nominations), "w")
      archive.puts nom_archive.join("\n")
    end

    def get_oldest(n = nil, short = false)
      noms = @tree.sort_noms_by_date.select{ |nom| !nom[:nomination_date].nil? and nom[:tags].nil? }

      wt_array = []
      n = noms.size if n.nil?
      noms[0...n].each do |nom|
        if short
          wt_array.push(ARTICLE_LINK % [nom[:category], nom[:article]])
        else
          wt_array.push("# " + ARTICLE_LINK % [nom[:category], nom[:article]] + " " + format_date(nom[:nomination_date]))
        end
      end

      wt_array
    end

    def get_backlog
      backlog = File.open(data_file(:backlog), "r") { |f| f.read }.split(/[\n\r]/).select{ |i| !i.empty? }
      backlog.push("#{@now.strftime("%s")};#{@tree.total};#{@tree.on_hold};#{@tree.on_review};#{@tree.second_opinion}")
    end

    def get_exceptions
      noms = @tree.sort_noms_by_date

      old_nominations = []
      malformed = []
      old_holds = {}
      old_reviews = {}
      old_second_opinions = {}
      nominators = {}

      noms.each do |n|
        wikilink = ARTICLE_LINK % [n[:category], n[:article]]

        if !n[:nominator].nil?
          nominators[n[:nominator]] = [] if nominators[n[:nominator]].nil?
          nominators[n[:nominator]].push(wikilink)
        end
          
        malformed.push(wikilink + " (''#{n[:malformed].join(', ')}'')") if !n[:malformed].empty?

        if !n[:nomination_date].nil? and (@now - n[:nomination_date]).to_i >= EXCEPTION_NOM_AGE
          image = ""
          n[:tags].each do |tag|
            image += case tag[:status]
              when "on_hold" then IMG_OH
              when "on_review" then IMG_UR
              when "second_opinion" then IMG_2O
            end.to_s
          end if !n[:tags].nil?

          old_nominations.push(image + " " + wikilink + " ('''#{(@now - n[:nomination_date]).to_i}''' days)")
        end

        n[:tags].each do |tag|
          tag_age = (@now - tag[:date]).to_i if !tag[:date].nil?
          case tag[:status]
            when "on_hold"
              old_holds[tag[:date]] = [] if old_holds[tag[:date]].nil?
              old_holds[tag[:date]].push(wikilink + " ('''#{tag_age}''' days)")
            when "on_review"
              old_reviews[tag[:date]] = [] if old_reviews[tag[:date]].nil?
              old_reviews[tag[:date]].push(wikilink + " ('''#{tag_age}''' days)")
            when "second_opinion"
              old_second_opinions[tag[:date]] = [] if old_second_opinions[tag[:date]].nil?
              old_second_opinions[tag[:date]].push(wikilink + " ('''#{tag_age}''' days)")
          end if !tag_age.nil? and tag_age > EXCEPTION_TAG_AGE
        end if !n[:tags].nil?
      end

      # Filter out nominators that only have one nomination
      nominators = nominators.select{ |nominator, noms| noms.size >= EXCEPTION_NOMINATIONS }.sort{|a, b| b.last.size <=> a.last.size}

      old_holds = old_holds.sort{|a, b| a.first <=> b.first}.collect{|a| a.last}.flatten
      old_reviews = old_reviews.sort{|a, b| a.first <=> b.first}.collect{|a| a.last}.flatten
      old_second_opinions = old_second_opinions.sort{|a, b| a.first <=> b.first}.collect{|a| a.last}.flatten

      report = <<eor
=== Holds over #{EXCEPTION_TAG_AGE} days old ===
#{!old_holds.empty? ? "#" + old_holds.join("\n#") : "None"}

=== Old reviews ===
:''Nominations that have been marked under review for #{EXCEPTION_TAG_AGE} days or longer.''
#{!old_reviews.empty? ? "#" + old_reviews.join("\n#") : "None"}

=== Old requests for 2nd opinion ===
:''Nominations that have been marked requesting a second opinion for #{EXCEPTION_TAG_AGE} days or longer.''
#{!old_second_opinions.empty? ? "#" + old_second_opinions.join("\n#") : "None"}

=== Old nominations ===
:''All nominations that were added #{EXCEPTION_NOM_AGE} days ago or longer, regardless of other activity.''
#{!old_nominations.empty? ? "#" + old_nominations.join("\n#") : "None"}

=== Malformed nominations ===
#{!malformed.empty? ? "#" + malformed.join("\n#") : "None"}

=== Nominators with multiple nominations ===
eor

      if nominators.empty?
        report += "None"
      else
        nominators.each do |n|
          report += ";#{n.first} (#{n.last.size})\n:#{n.last.join(", ")}\n"
        end
      end

      report.strip
    end

    def get_summary
      out = []
      @tree.each do |node|
        next if node.isRoot?

        summary = ":" * [node.level - 1, 0].max + "'''" + ARTICLE_LINK % [node.name, node.name] + "''' (#{node.total})"

        if node.total > 0
          summary += ": "
          summary += IMG_OH + " x #{node.on_hold}; " if node.on_hold > 0 
          summary += IMG_UR + " x #{node.on_review}; " if node.on_review > 0 
          summary += IMG_2O + " x #{node.second_opinion}; " if node.second_opinion > 0 

          if oldest = node.sort_noms_by_date.first || node.content.first
            oldest_age = (@now - oldest[:nomination_date]).to_i if !oldest[:nomination_date].nil?
            oldest_name = oldest[:article]
              
            summary += "Oldest: #{oldest_name} (#{oldest_age.nil? ? "''unparseable date''" : oldest_age.to_s + " days"})"
          end
        end

        out << summary
      end
      out.join("\n")
    end

    def generate_report(comment = nil)
      # Create a text string to write to the wiki.
      message "Generating report..."
      
      template = load_template(:report)
      backlog = get_backlog

      edit_msg = "Daily [[WP:GAN]] report"
      wikitext = template % [
        get_oldest(10).join("\n"),
        format_backlog(backlog.reverse[0...BACKLOG_COUNT]).join("<br />\n"),
        get_exceptions,
        get_summary
      ]
      wikitext += "\n<!-- #{comment} -->" if !comment.nil?

      page(@options[:output] || REPORT_PAGE).write(wikitext, edit_msg)

      done

      update_backlog_archive(backlog)
    end

    def generate_template
      # Create a template of important stats.
      message "Generating GACStats template..."

      template = load_template(:stats)

      wikitext = template % [@tree.total, @tree.on_hold, @tree.on_review, @tree.second_opinion, format_date(@now)]
      edit_msg = "Update of [[WP:GAN]] stats template";

      page(@options[:output] || TEMPLATE_PAGE).write(wikitext, edit_msg)

      done
    end

    def update_backlog_items
      message "Updating backlog items template..."

      backlog = get_oldest(10, true)
      
      template = load_template(:backlog)

      wikitext = template % [backlog[0...5].join("\n&bull; "), backlog[5..-1].join("\n&bull; ")]
      edit_msg = "Update of [[WP:GAC]] backlog list";

      page(@options[:output] || BACKLOG_ITEMS_PAGE).write(wikitext, edit_msg)
      
      done
    end

    def update_backlog_archive(backlog)
      message "Updating backlog archive..."

      File.open(data_file(:backlog), "w") { |f| f.write backlog.join("\n") } unless @debug

      if backlog.size > BACKLOG_COUNT
        # Update the backlog archive page
        archive = format_backlog(backlog[0...-BACKLOG_COUNT])
        wikitext = "{{/top}}\n\n" + archive.join("<br />\n")
        edit_msg = "Update of GAN report backlog"
        page(@options[:output] || BACKLOG_SUBPAGE).write(wikitext, edit_msg, 0)
      end

      done
    end

    def login
      message "Logging in as #{@config.username}..."
      super
      done

    rescue WikiBot::Bot::LoginError => e
      failed "Login to wikipedia failed with status '#{e.message}'."
    end

    def logout
      message "Logging out..."
      super
      done
    end

    def query_api(method, raw_data = {}, dry_run = false)
      tries = 1

      begin
        verbose(raw_data[:action] == :edit ? 2 : 1) do
          message "Querying API: #{raw_data.to_querystring} [#{method.to_s.upcase}]", false
        end

        super

      rescue WikiBot::CurbError => e
        color = tries < MAX_QUERY_TRIES ? :light_red : :red

        message "Attempt ##{tries} failed with error:", color
        message "Curb failed with response code #{e.curb.response_code}.", color

        if tries < MAX_QUERY_TRIES
          delay = DELAY_BETWEEN_RETRIES * tries

          message "Sleeping for #{delay}s...", color
          sleep delay

          message "Retrying... (attempt ##{tries + 1} of #{MAX_QUERY_TRIES})", color
          puts

          tries += 1
          retry
        else
          verbose(2) do
            message "URL: #{e.curb.url}", false
            message "Headers:", false
            message e.curb.headers.inspect, false
            message "Response Headers:", false
            message e.curb.header_str, false

            if e.curb.body_str
              message "Response Body:", false
              message Zlib::GzipReader.new(StringIO.new(e.curb.body_str)).read, false
            end
          end

          message "No more retries"
          failed
        end
      end
    end

  private

    def message(msg, color = :bright_white, meth = :puts)
      msg = msg.colorize(msg, :foreground => color) if color
      time = Time.now

      send(meth, "[#{time.strftime("%Y-%m-%d %H:%I:%S")}.#{((time.to_f * 1000.0).to_i % 1000).to_s.ljust(3, '0')}] #{msg}")
      $stdout.flush
    end

    def done
      message 'Done.', :green
      puts
    end

    def failed(msg = nil)
      puts
      message(msg, :red) if msg
      logout if logged_in?
      exit 1
    end

    def verbose(level = 1)
      return unless verbosity >= level

      print "".color(:dark_grey)
      yield
      print "\r".extra(:clear)
    end

    def format_backlog(backlog)
      backlog.inject([]) do |out, bl|
        timestamp, total, on_hold, under_review, second_opinion = bl.split(';').map{ |e| e.to_i }
        second_opinion = 0 if second_opinion.nil?

        date = format_date(Time.at(timestamp.to_i))
        not_reviewed = total - on_hold - under_review - second_opinion

        str = "%s &ndash; %d nomination%s outstanding; %d not reviewed; #{IMG_OH} x %d; #{IMG_UR} x %d"
        str << "; #{IMG_2O} x %d" if second_opinion > 0

        out << str % [date, total, ('s' if total != 1), not_reviewed, on_hold, under_review, second_opinion]
      end
    end

    def data_file(name)
      data_dir = Pathname.new(@options[:data] || File.expand_path(File.dirname(__FILE__)) + "/data")
      file_name = case name
        when :backlog
          'gac-backlog.dat'

        when :nominations
          'gac-yesterdays-noms.dat'

        when :nom_change
          'gac-nominations-backlog.dat'
      end

      data_dir.join(file_name)
    end

    def load_template(name)
      template = File.expand_path("../../templates/#{name}.tpl", __FILE__)
      File.read(template)
    end
  end
end
