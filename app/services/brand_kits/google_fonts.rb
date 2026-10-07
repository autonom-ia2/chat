# Famílias populares do Google Fonts (#1076). Quando o site serve a fonte por conta própria (next/font,
# arquivo local), o link do Google Fonts não aparece na página; se a família está aqui, o e-mail pode
# carregá-la pelo Google com `mj-font` — e o Arial continua de reserva onde o leitor não suporta.
# Família fora da lista fica sem link (o e-mail usa a reserva) e a importação avisa.
module BrandKits::GoogleFonts
  BASE_URL = 'https://fonts.googleapis.com/css2'.freeze
  FAMILIES = [
    'Abril Fatface', 'Alegreya', 'Alegreya Sans', 'Archivo', 'Archivo Black', 'Arimo', 'Asap', 'Barlow', 'Barlow Condensed',
    'Be Vietnam Pro', 'Bebas Neue', 'Bitter', 'Cabin', 'Cairo', 'Caveat', 'Comfortaa', 'Cormorant Garamond', 'Crimson Text',
    'DM Sans', 'DM Serif Display', 'Dancing Script', 'Domine', 'Dosis', 'EB Garamond', 'Exo 2', 'Figtree', 'Fira Sans',
    'Fjalla One', 'Fraunces', 'Heebo', 'Hind', 'IBM Plex Sans', 'IBM Plex Serif', 'Inconsolata', 'Inter', 'Josefin Sans',
    'Jost', 'Kanit', 'Karla', 'Lato', 'Lexend', 'Libre Baskerville', 'Libre Franklin', 'Lobster', 'Lora', 'Manrope',
    'Merriweather', 'Merriweather Sans', 'Montserrat', 'Mukta', 'Mulish', 'MuseoModerno', 'Nanum Gothic', 'Noto Sans',
    'Noto Serif', 'Nunito', 'Nunito Sans', 'Open Sans', 'Oswald', 'Outfit', 'Overpass', 'Oxygen', 'PT Sans', 'PT Serif',
    'Pacifico', 'Playfair Display', 'Plus Jakarta Sans', 'Poppins', 'Prompt', 'Quicksand', 'Raleway', 'Red Hat Display',
    'Roboto', 'Roboto Condensed', 'Roboto Mono', 'Roboto Slab', 'Rubik', 'Sora', 'Source Code Pro', 'Source Sans 3',
    'Source Serif 4', 'Space Grotesk', 'Teko', 'Titillium Web', 'Ubuntu', 'Urbanist', 'Varela Round', 'Work Sans', 'Zilla Slab'
  ].to_set.freeze
  BY_NAME = FAMILIES.index_by(&:downcase).freeze

  module_function

  def include?(family)
    BY_NAME.key?(family.to_s.downcase)
  end

  # Só o peso regular: um peso que a família não tem faria o Google recusar o pedido inteiro.
  def url_for(families)
    names = families.filter_map { |family| BY_NAME[family.to_s.downcase] }.uniq
    return nil if names.empty?

    "#{BASE_URL}?#{names.map { |name| "family=#{name.tr(' ', '+')}" }.join('&')}&display=swap"
  end
end
