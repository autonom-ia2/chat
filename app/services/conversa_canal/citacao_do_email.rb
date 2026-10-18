# Histórico e encaminhado da resposta de e-mail (#1786). A caixa de resposta nova pede, em
# `content_attributes.email_citacao`, `{ tipo: 'historico' | 'encaminhado', message_id: <id> }`. Este serviço monta o
# trecho que vai embaixo do texto do atendente, com o original formatado (HTML) e a linha de atribuição em português,
# no fuso da conta, no formato que o Gmail e o Outlook reconhecem e recolhem:
#   histórico   → "Em sáb., 17 de out. de 2026 às 10:15, Marina Costa <marina@…> escreveu:" + <blockquote> do original
#   encaminhado → "---------- Mensagem encaminhada ----------" + De / Data / Assunto / Para + o original
# Só cita mensagem da MESMA conversa, de entrada ou saída e não privada; qualquer outra coisa é ignorada (o e-mail sai
# só com o texto do atendente). O `content` da mensagem não muda: o CRM e a IA continuam lendo só o que o atendente
# escreveu (combinado com o Multifunnel).
class ConversaCanal::CitacaoDoEmail
  TIPOS = %w[historico encaminhado].freeze
  ESTILO_DO_BLOCO = 'margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex'.freeze

  def initialize(conversation:, pedido:)
    @conversation = conversation
    @pedido = (pedido || {}).to_h.with_indifferent_access
  end

  def valida?
    TIPOS.include?(tipo) && original.present?
  end

  # O pedido é de encaminhar (mesmo que a mensagem citada não valha): sem Para, o builder recusa.
  def encaminhado?
    tipo == 'encaminhado'
  end

  # O encaminhado leva os arquivos do original, como no Gmail. O mesmo arquivo guardado, sem cópia.
  def anexos_assinados
    return [] unless valida? && encaminhado?

    original.attachments.filter_map { |anexo| anexo.file.blob&.signed_id }
  end

  # "Enc: Proposta" no idioma da conta. O encaminhado é um fio novo para quem recebe, não "Re:" do fio do cliente.
  def assunto_do_encaminhado
    assunto = dados['subject'].presence || @conversation.additional_attributes.to_h['mail_subject'].to_s
    no_idioma_da_conta { "#{I18n.t('conversa_canal.email.prefixo_encaminhado')} #{assunto}".strip }
  end

  # Palavras e data no idioma da conta: quem lê é o cliente, não quem está logado.
  def html
    return '' unless valida?

    no_idioma_da_conta { tipo == 'historico' ? html_do_historico : html_do_encaminhado }
  end

  def texto
    return '' unless valida?

    no_idioma_da_conta do
      cabecalho = tipo == 'historico' ? [atribuicao] : linhas_do_encaminhado
      citado = texto_original.lines.map { |linha| tipo == 'historico' ? "> #{linha}" : linha }.join
      "\n\n#{cabecalho.join("\n")}\n#{citado}"
    end
  end

  private

  def tipo
    @pedido[:tipo].to_s
  end

  def no_idioma_da_conta(&)
    idioma = @conversation.account.locale.presence || I18n.default_locale
    I18n.with_locale(I18n.available_locales.map(&:to_s).include?(idioma.to_s) ? idioma : I18n.default_locale, &)
  end

  def original
    return @original if defined?(@original)

    @original = @conversation.messages
                             .where(id: @pedido[:message_id], private: false, message_type: %i[incoming outgoing])
                             .first
  end

  def html_do_historico
    <<~HTML.squish
      <br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">#{escapar(atribuicao)}<br></div>
      <blockquote class="gmail_quote" style="#{ESTILO_DO_BLOCO}">#{html_original}</blockquote></div>
    HTML
  end

  def html_do_encaminhado
    linhas = linhas_do_encaminhado.map { |linha| escapar(linha) }.join('<br>')
    <<~HTML.squish
      <br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">#{linhas}<br></div><br>#{html_original}</div>
    HTML
  end

  def linhas_do_encaminhado
    [
      I18n.t('conversa_canal.email.encaminhada'),
      linha(:de, remetente),
      linha(:data, data_legivel),
      linha(:assunto, dados['subject']),
      linha(:para, Array(dados['to']).join(', '))
    ].compact
  end

  def linha(rotulo, valor)
    return if valor.blank?

    "#{I18n.t("conversa_canal.email.#{rotulo}")}: #{valor}"
  end

  def atribuicao
    I18n.t('conversa_canal.email.escreveu', data: data_legivel, remetente: remetente)
  end

  def dados
    @dados ||= (original.content_attributes || {}).with_indifferent_access[:email] || {}
  end

  # O que veio do cliente: o From dele. O que saiu da plataforma não tem From gravado: vale o endereço da caixa (o que o
  # cliente viu), nunca o e-mail de login do atendente; o nome é o do atendente ou, de robô e automação, o da caixa.
  def remetente
    endereco, nome = original.outgoing? ? remetente_da_caixa : remetente_do_cliente
    return endereco.to_s if nome.blank? || nome == endereco
    return nome.to_s if endereco.blank?

    "#{nome} <#{endereco}>"
  end

  def remetente_do_cliente
    [Array(dados['from']).first.presence || original.sender.try(:email), original.sender.try(:name)]
  end

  def remetente_da_caixa
    caixa = @conversation.inbox
    nome = original.sender.is_a?(User) ? original.sender.available_name : caixa.name
    [Array(dados['from']).first.presence || caixa.channel.try(:email), nome]
  end

  # "sáb., 17 de out. de 2026 às 10:15", no fuso da conta.
  def data_legivel
    quando = original.created_at.in_time_zone(fuso)
    I18n.t(
      'conversa_canal.email.data_completa',
      dia_da_semana: I18n.t('conversa_canal.email.dias_curtos')[quando.wday],
      dia: quando.day,
      mes: I18n.t('conversa_canal.email.meses_curtos')[quando.month - 1],
      ano: quando.year,
      hora: quando.strftime('%H:%M')
    )
  end

  def fuso
    ActiveSupport::TimeZone[Crm::Timezone::Resolver.new(account: @conversation.account).name_or_default] || Time.zone
  end

  # O HTML do e-mail original (o completo, com o histórico dele), limpo: sem script, sem evento, sem formulário.
  def html_original
    bruto = dados.dig('html_content', 'full').presence ||
            ChatwootMarkdownRenderer.new(original.content.to_s).render_message.to_s
    Rails::HTML5::SafeListSanitizer.new.sanitize(sem_cabeca(bruto), tags: TAGS_PERMITIDAS, attributes: ATRIBUTOS_PERMITIDOS)
  end

  # O sanitizador tira a tag, mas deixa o texto de dentro: o CSS do Outlook (`/* Font Definitions */ @font-face …`),
  # o título e o script apareceriam na citação. Aqui eles saem inteiros, com o conteúdo.
  def sem_cabeca(bruto)
    documento = Nokogiri::HTML5(bruto.to_s)
    documento.css('head, style, title, script, noscript, template').each(&:remove)
    documento.at('body')&.inner_html.to_s
  end

  def texto_original
    dados.dig('text_content', 'full').presence || original.content.to_s
  end

  def escapar(texto)
    ERB::Util.html_escape(texto)
  end

  TAGS_PERMITIDAS = %w[
    a abbr b blockquote br caption center code col colgroup dd del div dl dt em font h1 h2 h3 h4 h5 h6 hr i img ins li
    ol p pre s small span strike strong sub sup table tbody td tfoot th thead tr u ul
  ].freeze
  ATRIBUTOS_PERMITIDOS = %w[
    align alt bgcolor border cellpadding cellspacing class color colspan dir face height href lang rowspan size src
    style target title valign width
  ].freeze
  private_constant :TAGS_PERMITIDAS, :ATRIBUTOS_PERMITIDOS
end
