require 'colored'

Colored::COLORS.merge!(
  'dark_grey' => 90,
  'light_red' => 91,
  'light_green' => 92,
  'light_yellow' => 93,
  'light_blue' => 94,
  'light_magenta' => 95,
  'light_cyan' => 96, 
  'bright_white' => 97
)

module ColoredExtra
  Colored::COLORS.each do |color, value|
    define_method(color) do 
      colorize(self, :foreground => color)
    end

    define_method("on_#{color}") do
      colorize(self, :background => color)
    end

    Colored::COLORS.each do |highlight, value|
      next if color == highlight
      define_method("#{color}_on_#{highlight}") do
        colorize(self, :foreground => color, :background => highlight)
      end
    end
  end
end

String.send(:include, ColoredExtra)
