# Lê a prévia de uma página como o WhatsApp faz (#1702): og:title, og:description, og:image e og:site_name, com o
# <title> e a meta description como reserva. Fonte dos campos:
# https://developers.facebook.com/documentation/business-messaging/whatsapp/link-previews/
#
# A página vem de fora e o endereço vem de quem escreveu a mensagem, então tudo passa pelo SafeFetch (ssrf_filter):
# endereço privado, loopback, link-local e o metadata da nuvem (169.254.169.254) são recusados, o IP resolvido é o
# mesmo em que se conecta (sem DNS rebinding) e cada redirecionamento é revalidado. Aqui somam-se: só http/https
# nas portas 80/443 também em cada redirecionamento (`allowed_ports`), prazo total de 5 s, no máximo 3
# redirecionamentos, só os primeiros 512 KB do HTML (`truncate_at_max_bytes`: o <head> está no começo; página
# maior é cortada, não recusada) e sem cookie (o Net::HTTP não guarda nenhum).
# O HTML é lido pelo Nokogiri, sem expressão regular.
class ConversaCanal::LeitorDeOpenGraph
  PORTAS = [80, 443].freeze
  MAX_BYTES = 512.kilobytes
  PRAZO_TOTAL = 5
  PRAZO_CONEXAO = 2
  PRAZO_LEITURA = 3
  MAX_REDIRECIONAMENTOS = 3
  TIPOS_HTML = %w[text/html application/xhtml+xml].freeze
  USER_AGENT = 'Chat2You-LinkPreview/1.0'.freeze
  TITULO_MAX = 200
  DESCRICAO_MAX = 300
  SITE_MAX = 100

  def self.ler(url)
    new(url).ler
  end

  def self.opcoes_do_fetch(tipos:, max_bytes:)
    {
      max_bytes: max_bytes,
      open_timeout: PRAZO_CONEXAO,
      read_timeout: PRAZO_LEITURA,
      total_timeout: PRAZO_TOTAL,
      max_redirects: MAX_REDIRECIONAMENTOS,
      allowed_ports: PORTAS,
      allowed_content_type_prefixes: [],
      allowed_content_types: tipos,
      headers: { 'User-Agent' => USER_AGENT }
    }
  end

  # Só http/https em porta padrão. Os saltos seguintes são conferidos pelo `allowed_ports` do SafeFetch.
  def self.endereco_permitido?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present? && PORTAS.include?(uri.port)
  rescue URI::InvalidURIError
    false
  end

  def initialize(url)
    @url = url
  end

  # => { 'url', 'final_url', 'title', 'description', 'site_name', 'image_source' } ou nil quando a página não tem título.
  # `image_source` é o endereço da og:image na página; quem grava baixa a imagem e não o guarda. `final_url` é o
  # endereço lido de fato, depois dos redirecionamentos (#1775: a IA diz de que site veio o texto, não o do link enviado,
  # que pode ser um redirecionador).
  def ler
    return unless self.class.endereco_permitido?(@url)

    SafeFetch.fetch(@url, **opcoes) do |resultado|
      extrair(Nokogiri::HTML(resultado.tempfile.read, nil, resultado.charset), resultado.url)
    end
  end

  private

  def opcoes
    base = self.class.opcoes_do_fetch(tipos: TIPOS_HTML, max_bytes: MAX_BYTES)
    base.merge(truncate_at_max_bytes: true,
               headers: base[:headers].merge('Accept' => TIPOS_HTML.join(','), 'Range' => "bytes=0-#{MAX_BYTES - 1}"))
  end

  def extrair(doc, url_final)
    titulo = limpo(meta(doc, 'og:title') || doc.at_css('title')&.text, TITULO_MAX)
    return if titulo.blank?

    {
      'url' => @url,
      'final_url' => url_final.presence,
      'title' => titulo,
      'description' => limpo(meta(doc, 'og:description') || meta(doc, 'description'), DESCRICAO_MAX),
      'site_name' => limpo(meta(doc, 'og:site_name'), SITE_MAX),
      'image_source' => imagem(meta(doc, 'og:image:secure_url') || meta(doc, 'og:image'), url_final)
    }.compact
  end

  # Open Graph usa `property`; muitos sites usam `name`. O valor é comparado inteiro, sem padrão.
  def meta(doc, nome)
    no = doc.css('meta').find { |tag| [tag['property'], tag['name']].compact.any? { |valor| valor.strip.casecmp?(nome) } }
    no&.[]('content').presence
  end

  def limpo(texto, maximo)
    texto&.squish&.truncate(maximo).presence
  end

  # Endereço relativo é montado sobre o endereço final (depois dos redirecionamentos).
  def imagem(valor, url_final)
    return if valor.blank?

    absoluto = URI.join(url_final || @url, valor.strip).to_s
    absoluto if self.class.endereco_permitido?(absoluto)
  rescue URI::Error, ArgumentError
    nil
  end
end
