module WikiBot
  class Page
    def write_with_verbose(text, summary, section = nil, minor = false)
      write_without_verbose(text, summary, section, minor)

      l = lambda do |name|
        lambda do
          verbose do
            message "Wrote to #{name}: #{summary}", false
          end

          verbose(4) do
            message text, false
          end
        end
      end
      
      @wiki_bot.instance_eval &l.call(name)
    end

    alias_method :write_without_verbose, :write
    alias_method :write, :write_with_verbose

    def write_with_debug(text, summary, section = nil, minor = false)
      if @wiki_bot.debug 
        puts summary
        puts text
      else
        write_without_debug(text, summary, section, minor)
      end
    end
  end
end

