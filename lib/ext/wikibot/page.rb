module WikiBot
  class Page
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

