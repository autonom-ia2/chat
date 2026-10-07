# The fonts an imported model may keep (#1099): the ones every e-mail program shows, each written with its fallbacks so
# a phone without it picks one of the same kind (serif stays serif). A family list keeps the first of its fonts that is
# here — "Playfair Display, Georgia, serif" becomes Georgia — and one with none of them (a web font only) becomes
# Arial. QualityGate accepts these first names on imported models; the shared library stays on Arial (#1082).
# String methods only — no regex.
module EmailCampaigns::Import::WebFonts
  DEFAULT = 'Arial, Helvetica, sans-serif'.freeze
  SERIF = 'Georgia, Times New Roman, Times, serif'.freeze
  TIMES = 'Times New Roman, Times, serif'.freeze
  MONO = 'Courier New, Courier, monospace'.freeze
  STACKS = {
    'arial' => DEFAULT, 'helvetica' => 'Helvetica, Arial, sans-serif', 'sans-serif' => DEFAULT,
    'verdana' => 'Verdana, Geneva, sans-serif', 'tahoma' => 'Tahoma, Verdana, sans-serif',
    'trebuchet ms' => 'Trebuchet MS, Helvetica, sans-serif', 'georgia' => SERIF, 'serif' => SERIF,
    'times new roman' => TIMES, 'times' => TIMES, 'courier new' => MONO, 'courier' => MONO, 'monospace' => MONO
  }.freeze
  # The first family of every stack above: what QualityGate accepts on an imported model.
  NAMES = STACKS.values.uniq.map { |stack| stack.split(',').first.strip.downcase }.freeze

  module_function

  def stack(family)
    names(family).each { |name| return STACKS[name] if STACKS.key?(name) }
    DEFAULT
  end

  # True when the font the reader sees first is one of these (nothing was replaced).
  def kept?(family)
    first = names(family).first
    first.nil? || STACKS.key?(first)
  end

  def names(family)
    family.to_s.split(',').map { |name| name.strip.delete(%q('")).downcase }.reject(&:empty?)
  end
end
