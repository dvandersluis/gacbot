require 'tree'

module GACBot
  class CategoryTree
    attr_accessor :total, :on_hold, :on_review, :second_opinion

    def initialize
      @root = Node.new("root", {}, self)
      @total = @on_hold = @on_review = @second_opinion = 0
    end

    def method_missing(name, *args, &block)
      @root.send(name, *args, &block)
    end

    class Node < Tree::TreeNode
      attr_accessor :total, :on_hold, :on_review, :second_opinion

      def initialize(name, content = nil, tree = nil)
        @tree = tree
        @total = @on_hold = @on_review = @second_opinion = 0
        super(name, content)
      end

      def level
        parentage.nil? ? 0 : parentage.size
      end

      def add_categories(content, level = 2)
        regex = Regexp.new('^\s*(' + ("=" * level) + ')(?!=)\s*(.+?)\s*\1\s*$')
        offset = 0
        matches = []

        while !(match = regex.match(content[offset..-1])).nil?
          matches.push( {:offset => offset + match.offset(0)[0], :name => match[2]} )
          offset += match.offset(0)[1]
        end

        matches.each_with_index do |match, index|
          offset = match[:offset]
          next_offset = -1
          next_offset = matches[index+1][:offset] if index + 1 < matches.size 

          content_stub = content[offset..next_offset]

          # Create a new node and then set its content
          # Needs to be done like that so that the count instance vars will be set for the right node
          node = Node.new(match[:name], "", @tree)
          node.content = node.get_nominations(content_stub, level).each { |nom| nom[:category] = match[:name] }
          node.add_categories(content_stub, level + 1)

          self << node
        end unless matches.empty?
      end

      def get_nominations(content, level)
        nominations = []

        # In case the section has subsections, extract only the section text itself to work on:
        regex = Regexp.new('^\s*(' + ("=" * level) + ')(?!=)\s*(?:.+?)\s*\1\s*$(.+?)(?=(^=+)|\Z)', Regexp::MULTILINE)
        nom_text = content.match(regex)[2]

        # Parse the nominations:
        #regex = /^#.*?\{\{(?:article|la)\|(.+?)\}\}.*?$/i # OLD FORMAT
        regex = /^#.*?\{\{GANentry\|(?:1=)?(.+?)(?:\|(?:2=)?(.+?))\}\}.*?$/i
        offset = 0
        matches = []

        while !(match = regex.match(nom_text[offset..-1])).nil?
          matches.push( {:offset => offset + match.offset(0)[0], :nomination => match[0], :article => match[1]} )
          offset += match.offset(0)[1]
        end

        if !matches.empty?
          # Some regexes that will be used later:
          months = /J(?:anuary|une|uly)|February|M(?:arch|ay)|A(?:pril|ugust)|September|October|November|December/
          date_regex = /(\d{2}):(\d{2}),?\s(\d{1,2})\s(#{months})\s(\d{4})\s\(UTC\)/im
          user_regex = /(?:\[\[(?:User(?:(?:_|\s)talk)?:|Special:Contributions\/)|\{\{User\d*\|)(.+?)(?:\|.*?)?(?:\]|\}){2}/im

          matches.each_with_index do |match, index|
            offset = match[:offset]
            next_offset = -1
            next_offset = matches[index+1][:offset] if index + 1 < matches.size 
            nom_params = {:malformed => [], :article => match[:article]}

            # A nomination can have more than one line if it's on hold, being reviewed, etc.
            nomination = nom_text[offset..next_offset].strip.split(/[\n\r\s]*^#\s*/m).select{ |n| !n.empty? }

            # Get the nominator:
            if !nomination[0].match(user_regex).nil?
              nom_params[:nominator] = $~[1]
            else
              nom_params[:malformed].push "Nominator not found"
            end

            # Get the nomination date:
            if !nomination[0].match(date_regex).nil?
              hour, min, day, month, year = $~.captures
              begin
                if !DateTime.valid_time?(hour.to_i, min.to_i, 0).nil? and Date.valid_civil?(year.to_i, Date.parse("1 #{month} #{year}").mon, day.to_i)
                  nom_params[:nomination_date] = DateTime.parse("#{day} #{month} #{year} #{hour}:#{min}")
                else
                  nom_params[:malformed].push "Nomination date is not valid"
                end
              rescue Exception => e
                nom_params[:malformed].push "Nomination date is not valid"
              end
            else
              nom_params[:malformed].push "Nomination date not found"
            end

            nomination.shift
            if nomination[0]
              # Nomination has more than one line:
              nomination = nomination.join("\n")
              ga_tags = []
                
              # Parse GAReview tag
              if nomination =~ /\{\{GAReview(?:\s*\|\s*status\s*=\s*((?:on\s*)?hold|2nd\s*opinion)\s*)?\}\}/im
                status = $~.captures.first

                status = "on review" if status.nil? or status.empty?
                status = status.strip.gsub(/\s+/, "_")
                status = "on_hold" if status == "onhold" or status == "hold"
                status = "second_opinion" if status == "2ndopinion" || status == "2nd_opinion"

                case status
                  when "on_review" then @on_review += 1 and @tree.on_review += 1
                  when "on_hold" then @on_hold += 1 and @tree.on_hold += 1
                  when "second_opinion" then @second_opinion += 1 and @tree.second_opinion += 1
                end

                regex = /\{\{GAReview.*?\}\}.*?#{user_regex}.+?#{date_regex}/im
                
                if nomination.match(regex)
                  reviewer, hour, min, day, month, year = $~.captures

                  begin
                    date = DateTime.parse("#{day} #{month} #{year} #{hour}:#{min}")
                  rescue Exception => e
                    nom_params[:malformed].push "GAReview date is not valid"
                  end
                else
                  nom_params[:malformed].push "GAReview found but malformed"
                end

                ga_tag = {:status => status}
                ga_tag[:reviewier] = reviewer if !reviewer.nil?
                ga_tag[:date] = date if !date.nil?

                ga_tags.push(ga_tag)
              end

              # Parse GAOnHold tag -- deprecated but handled just in case
              if nomination.match(/\{\{GAOnHold(?:\|(.+?))?\}\}/im)
                @on_hold += 1
                @tree.on_hold += 1

                if $~[1].nil?
                  nom_params[:malformed].push "GAOnHold parameter missing"
                elsif $~[1] != match[:article]
                  nom_params[:malformed].push "GAOnHold parameter does not match article title"
                end

                regex = /\{\{GAOnHold\|.+?\}\}.*?#{user_regex}.+?#{date_regex}/im
                if nomination.match(regex)
                  reviewer, hour, min, day, month, year = $~.captures

                  begin
                    date = DateTime.parse("#{day} #{month} #{year} #{hour}:#{min}")
                  rescue Exception => e
                    nom_params[:malformed].push "GAOnHold date is not valid"
                  end

                  ga_tags.push({
                    :status => 'on_hold',
                    :reviewer => reviewer,
                    :date => date
                  }) if date
                else
                  nom_params[:malformed].push "GAOnHold found but malformed"
                end
              end
              
              # Parse GA2ndopinion tag -- deprecated but handled just in case
              if nomination.match(/\{\{GA2ndopinion(?:\|(.+?))?\}\}/im)
                @second_opinion += 1
                @tree.second_opinion += 1

                if $~[1].nil?
                  nom_params[:malformed].push "GA2ndopinion parameter missing"
                elsif $~[1] != match[:article]
                  nom_params[:malformed].push "GA2ndopinion parameter does not match article title"
                end

                regex = /\{\{GA2ndopinion\|.+?\}\}.*?#{user_regex}.+?#{date_regex}/im
                if nomination.match(regex)
                  reviewer, hour, min, day, month, year = $~.captures

                  begin
                    date = DateTime.parse("#{day} #{month} #{year} #{hour}:#{min}")
                  rescue Exception => e
                    nom_params[:malformed].push "GA2ndopinion date is not valid"
                  end

                  ga_tags.push({
                    :status => "second_opinion",
                    :reviewer => reviewer,
                    :date => date
                  }) if date
                else
                  nom_params[:malformed].push "GAOnHold found but malformed"
                end
              end

              if ga_tags.size > 1
                nom_params[:malformed].push "Nomination has more than one GA status template"
              end

              nom_params[:tags] = ga_tags if !ga_tags.empty?
            end
            nominations.push nom_params
          end
        end

        @total += nominations.size
        @tree.total += nominations.size
        nominations 
      end

      def sort_noms_by_date(force = false)
        @sorted_by_date = nil if force

        @sorted_by_date ||= begin
          noms = []
          self.each do |node|
            next if node.content.empty?
            noms.push(node.content)
            #nominations = node.content
            #noms.push(nominations.select{ |nom| !nom[:nomination_date].nil? })
          end

          noms.flatten.sort do |a,b|
            a_date = a[:nomination_date] || DateTime.new
            b_date = b[:nomination_date] || DateTime.new
            a_date <=> b_date
          end
        end
      end
    end
  end
end

