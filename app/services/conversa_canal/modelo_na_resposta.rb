# Junta o modelo de e-mail das Campanhas à resposta (#1786). O navegador compila o MJML do modelo sem o rodapé de
# descadastro e com os campos preenchidos, e manda em `content_attributes.email_modelo`:
#   { template_id:, html:, so_modelo: true|false }
# Aqui o HTML do modelo vira o corpo do e-mail: o texto do atendente entra no começo do <body>, e o histórico, no fim.
# Por segurança o HTML recebido é limpo de novo: sem script/iframe/formulário, sem atributos on*, sem o rodapé
# travado (footer-locked) e sem pixel ou link de rastreio de campanha. Só vale modelo salvo DA CONTA.
class ConversaCanal::ModeloNaResposta
  LIMITE = EmailCampaignTemplate::BODY_MAX
  PROIBIDAS = %w[script iframe object embed form input button base meta[http-equiv]].freeze
  RASTREIO = '/email_campaigns/t/'.freeze
  ESQUEMAS_PROIBIDOS = %w[javascript: vbscript:].freeze
  ESTILO_DO_TEXTO = 'font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#1f1f1f;' \
                    'max-width:600px;margin:0 auto;padding:16px 12px'.freeze

  def initialize(account:, pedido:)
    @account = account
    @pedido = (pedido || {}).to_h.with_indifferent_access
  end

  def valido?
    html_recebido.present? && html_recebido.length <= LIMITE && modelo_da_conta?
  end

  def so_modelo?
    ActiveModel::Type::Boolean.new.cast(@pedido[:so_modelo])
  end

  # Documento inteiro (o <head> do modelo traz os estilos do MJML, que o e-mail precisa).
  def html(texto_html:, citacao_html:)
    doc = documento.dup
    corpo = doc.at('body') || doc.root
    corpo.prepend_child(Nokogiri::HTML::DocumentFragment.parse("<div style=\"#{ESTILO_DO_TEXTO}\">#{texto_html}</div>")) unless so_modelo?
    corpo.add_child(Nokogiri::HTML::DocumentFragment.parse("<div style=\"#{ESTILO_DO_TEXTO}\">#{citacao_html}</div>")) if citacao_html.present?
    doc.to_html
  end

  def texto
    (documento.at('body') || documento.root).text.lines.map(&:strip).compact_blank.join("\n")
  end

  private

  def html_recebido
    @pedido[:html].to_s
  end

  def modelo_da_conta?
    ConversaCanal::ModeloDeEmail.da_conta(@account).exists?(id: @pedido[:template_id])
  end

  def documento
    @documento ||= limpar(Nokogiri::HTML(html_recebido))
  end

  def limpar(doc)
    [*PROIBIDAS, '.footer-locked'].each { |seletor| doc.css(seletor).each(&:remove) }
    tirar_eventos(doc)
    tirar_enderecos(doc)
    doc
  end

  def tirar_eventos(doc)
    doc.xpath('//@*').each { |atributo| atributo.remove if atributo.name.downcase.start_with?('on') }
  end

  def tirar_enderecos(doc)
    doc.css('img[src]').each { |no| no.remove if endereco_proibido?(no['src']) }
    doc.css('a[href]').each { |no| no.remove if endereco_proibido?(no['href']) }
  end

  # O navegador ignora espaço, tab e quebra de linha dentro do esquema ("java\tscript:"): saem antes de olhar.
  def endereco_proibido?(endereco)
    endereco = endereco.to_s.each_char.reject { |letra| letra.ord <= 32 }.join.downcase
    endereco.include?(RASTREIO) || ESQUEMAS_PROIBIDOS.any? { |esquema| endereco.start_with?(esquema) }
  end
end
