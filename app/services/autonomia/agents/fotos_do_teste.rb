# #1427 — as fotos mandadas no Testar da Fase 2, conferidas como a foto do material (FotoConferida: tipo pelos bytes, até
# 5 MB, até 40 MP, sem animada). Chegam como data-url (data:image/<tipo>;base64,<conteúdo>); o tipo declarado não vale:
# a data-url que segue ao modelo leva o tipo lido dos bytes. Uma foto recusada recusa o pedido inteiro, com o motivo em
# texto para a tela (`recusa`): nada some calado. Não grava nada; a data-url conferida segue no pedido temporário do Testar
# (Crm::Ai::InteractiveRequest, no Redis, até 30 min). Não vai ao log do Rails (`images` no filter_parameters) nem ao
# Sentry (`images` no SentryHttpAuthScrubber, que lê o corpo JSON cru).
class Autonomia::Agents::FotosDoTeste
  PREFIXO = 'data:'.freeze
  MARCA_BASE64 = ';base64'.freeze
  ESPACOS = " \t\r\n".freeze
  # Base64 ocupa 4/3 do original; com folga para quebras de linha. Acima disso já passou dos 5 MB, sem decodificar.
  MAX_BASE64 = (Autonomia::Agents::Config::MAX_IMAGE_BYTES * 4 / 3) + 1024
  # As do material que também servem ao teste; a animada tem frase própria (a do material fala de "material").
  MENSAGENS = {
    tipo: 'autonomia.source.foto_tipo',
    tamanho: 'autonomia.source.foto_tamanho',
    pixels: 'autonomia.source.foto_pixels',
    animada: 'autonomia.teste.foto_animada',
    muitas: 'autonomia.teste.foto_muitas'
  }.freeze

  attr_reader :data_urls

  def initialize(images)
    lista = Array(images)
    @data_urls = []
    @motivo = lista.size > Autonomia::Agents::Config::MAX_IMAGES_PER_MESSAGE ? :muitas : primeiro_problema(lista)
    @data_urls = [] if @motivo
  end

  # nil quando todas passam; senão a frase do primeiro problema.
  def recusa
    @motivo && I18n.t(MENSAGENS.fetch(@motivo), max: Autonomia::Agents::Config::MAX_IMAGES_PER_MESSAGE)
  end

  private

  def primeiro_problema(lista)
    lista.each do |raw|
      problema = conferir(raw.to_s)
      return problema if problema
    end
    nil
  end

  def conferir(raw)
    cabecalho, conteudo = raw.split(',', 2)
    return :tipo unless data_url_base64?(cabecalho, conteudo)
    return :tamanho if conteudo.bytesize > MAX_BASE64

    bytes = Base64.strict_decode64(conteudo.delete(ESPACOS))
    problema = Autonomia::Agents::Knowledge::FotoConferida.problema(bytes)
    @data_urls << "data:#{Marcel::MimeType.for(StringIO.new(bytes))};base64,#{Base64.strict_encode64(bytes)}" if problema.nil?
    problema
  rescue ArgumentError
    :tipo # base64 inválido
  end

  # O cabeçalho só precisa ser uma data-url em base64; o tipo dela é ignorado (os bytes decidem).
  def data_url_base64?(cabecalho, conteudo)
    conteudo.present? && cabecalho.start_with?(PREFIXO) && cabecalho.end_with?(MARCA_BASE64)
  end
end
