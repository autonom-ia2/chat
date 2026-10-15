# Por onde (e se) uma mensagem automática do agendamento pode sair (#1192, PLANO §2.5). Só decide; quem envia é o
# `Notices::Delivery`. Regra por tipo de caixa de avisos:
#
# - WhatsApp oficial (Cloud/360dialog): janela de 24 h aberta pelo cliente (`MessagingWindow`) → texto; fora dela,
#   modelo APROVADO na Meta configurado para o aviso; sem modelo → `template_required`; modelo cujo corpo não leva o
#   `{{3}}` (link de gestão, onde fica o "Parar avisos", J2-A9/RA-18) → `template_without_link`; modelo que pede o que o
#   aviso não preenche (variável além de `{{1}}`..`{{3}}` no corpo, variável ou mídia no topo, botão com link variável:
#   a Meta recusaria) → `template_unsupported`.
#   Híbrido (#1349, decisão do Rodrigo em 12/10): onde o modelo não resolve (`template_required`,
#   `template_without_link`, `template_unsupported`) e a caixa oficial tem o WhatsApp Híbrido pronto para este contato
#   (conta no piloto, conexão pronta, janela oficial fechada, origem `automation` ligada, conversa desta caixa e deste
#   contato, telefone real), o aviso sai como TEXTO (`mode: :session`, `via: :hybrid_web`) e o roteador do Híbrido o manda
#   pela WAHA. O modelo aprovado e adequado continua sempre primeiro. Sem essas condições: o motivo de antes.
#   Modelo v2 com botões (#1524, decisão do Rodrigo: o aprovado passa na frente): com `kind:`, ANTES do modelo
#   configurado, o `Whatsapp::Templates::Garantir` é consultado só para LER (`criar: false`: nunca cria nem fala com a
#   Meta, também na requisição web do `will_send?`). `:pronto` + UTILITY → `native_template` com `campos` (corpo) e
#   `botoes` ("Ver meu horário" e "Parar avisos"), que o `Notices::TemplateFill` preenche. Qualquer outro resultado
#   (`em_analise`, `indisponivel`, `ausente`, `sem_base_url`, outra categoria): a regra acima, sem mudança.
# - WAHA (#1270, decisão do Rodrigo em 11/10): texto, sem exigir mensagem do cliente nas últimas 24 h; sem conversa e
#   sem telefone → `no_phone`. Os tetos (4 por número em 24 h e o teto por conta) e o "Parar avisos" são conferidos
#   antes, no `Notices::Sender` e no `TestInvite`, e contêm o risco de bloqueio do número.
# - Canal API de campanhas (não WAHA): janela do canal → texto; fora dela, modelo do canal por id; senão
#   `template_required`.
#
# Conversa: a indicada (a do convite) quando é desta caixa e deste contato; senão a mais recente do contato nesta
# caixa; sem nenhuma, o modelo (ou o texto da WAHA) abre uma nova (o `Delivery` cria). No oficial e no canal API, sem
# conversa e sem modelo, o número digitado no link público não recebe mensagem automática.
class Crm::BookingV2::Notices::Route
  # Variável do corpo do modelo da Meta que recebe o link de gestão (`Notices::Delivery`).
  LINK_PLACEHOLDER = '{{3}}'.freeze
  # Variáveis do corpo que o aviso preenche: {{1}} primeiro nome, {{2}} dia e hora, {{3}} link de gestão.
  FILLED_VARIABLES = %w[1 2 3].freeze
  # Topo com mídia pede o arquivo no envio, que o aviso não manda.
  MEDIA_HEADERS = %w[IMAGE VIDEO DOCUMENT LOCATION].freeze

  # Origem que o Híbrido dá à mensagem do aviso: sem remetente (`Delivery` não passa usuário nesse caminho), o
  # `WhatsappHybrid::Router#origin_of` devolve `automation`. Se a conexão a desligou, o aviso não usa o Híbrido.
  HYBRID_ORIGIN = 'automation'.freeze
  # Marca, na decisão e na mensagem (`content_attributes.crm_booking_notice_via`), do aviso que saiu pelo Híbrido.
  HYBRID_WEB = :hybrid_web

  # campos/botoes: só no modelo v2 (`Garantir` `:pronto`), para o `Notices::TemplateFill`.
  Decision = Struct.new(:mode, :reason, :conversation, :template, :via, :campos, :botoes, keyword_init: true) do
    def send?
      reason.nil?
    end
  end

  # Texto do corpo de um modelo da Meta (item da lista sincronizada da caixa).
  def self.native_body(template)
    component = Array(template.to_h['components']).find { |item| item['type'].to_s.casecmp?('body') }
    component.to_h['text'].to_s
  end

  # O aviso consegue preencher o modelo: no corpo só {{1}}, {{2}} e {{3}}; no topo, só texto fixo; botão sem link
  # variável. Leitura por `split` (sem regex): o que vem entre `{{` e `}}` é o nome da variável.
  def self.fillable_template?(template)
    variables = native_body(template).split('{{').drop(1).map { |part| part.split('}}').first.to_s.strip }
    variables.all? { |name| FILLED_VARIABLES.include?(name) } && Array(template.to_h['components']).none? { |item| asks_more?(item) }
  end

  def self.asks_more?(component)
    case component.to_h['type'].to_s.upcase
    when 'HEADER' then MEDIA_HEADERS.include?(component['format'].to_s.upcase) || component['text'].to_s.include?('{{')
    when 'BUTTONS' then Array(component['buttons']).any? { |button| button.to_h['url'].to_s.include?('{{') }
    else false
    end
  end
  private_class_method :asks_more?

  # Modelo da lista sincronizada da caixa com o nome e o idioma configurados (qualquer status).
  def self.synced_template(inbox, configured)
    name, language = configured.to_h.values_at('name', 'language').map(&:to_s)
    return if name.blank? || language.blank?

    Array(inbox&.channel.try(:message_templates)).find { |item| item['name'] == name && item['language'].to_s.casecmp?(language) }
  end

  # O mesmo, só se está APROVADO na Meta.
  def self.approved_template(inbox, configured)
    found = synced_template(inbox, configured)
    found if found.to_h['status'].to_s.casecmp?('approved')
  end

  # kind: o tipo do aviso (`Crm::MeetingNotice::KINDS`); sem ele, o modelo v2 não é consultado.
  def initialize(inbox:, contact:, conversation: nil, template: nil, kind: nil)
    @inbox = inbox
    @contact = contact
    @preferred = conversation
    @template = template.to_h
    @kind = kind&.to_s
  end

  def decide
    return skip('no_inbox') if inbox.blank?
    return skip('no_contact') if contact.blank?

    case Crm::AgentBookingProfile.notice_channel_kind(inbox)
    when 'whatsapp' then official
    when 'waha' then waha
    when 'api' then api
    else skip('unsupported_inbox')
    end
  end

  private

  attr_reader :inbox, :contact, :template, :kind

  def official
    return session if conversation && Crm::FollowUps::MessagingWindow.new(conversation).can_send_session_message?

    ready = ready_template
    return native(ready[:template], campos: ready[:campos], botoes: ready[:botoes]) if ready

    approved = self.class.approved_template(inbox, template)
    problem = template_problem(approved)
    return hybrid_text || skip(problem) if problem

    native(approved)
  end

  def native(found, **filling)
    return skip('no_phone') if conversation.nil? && contact.phone_number.blank?

    Decision.new(mode: :native_template, conversation: conversation, template: found, **filling)
  end

  # O modelo v2 do tipo do aviso, aprovado como UTILITY, com o item da lista da caixa; senão nil (vale a regra de hoje).
  def ready_template
    finalidade = Whatsapp::Templates::Finalidades::Agendamento::POR_TIPO[kind]
    return if finalidade.nil?

    result = Whatsapp::Templates::Garantir.call(inbox: inbox, finalidade: finalidade, criar: false)
    return unless result[:status] == :pronto && result[:categoria] == Whatsapp::Templates::Finalidades::CATEGORIA

    found = listed_template(result[:nome], result[:idioma])
    { template: found, campos: result[:campos], botoes: result[:botoes] } if found
  end

  # Lida do banco, como no `Garantir`: a lista do objeto da caixa pode estar velha.
  def listed_template(name, language)
    channel = inbox.channel
    Whatsapp::Templates::ChannelList.entries(channel.class.where(id: channel.id).pick(:message_templates))
                                    .find { |item| item['name'] == name && item['language'].to_s.casecmp?(language) }
  end

  # Texto pelo WhatsApp Híbrido quando ele está pronto para este contato (ver o cabeçalho); senão nil.
  def hybrid_text
    return unless hybrid_ready?

    Decision.new(mode: :session, conversation: conversation, via: HYBRID_WEB)
  end

  def hybrid_ready?
    return false if conversation.nil? || !WhatsappHybrid::Config.available_for?(inbox)

    router = WhatsappHybrid::Router.new(conversation)
    router.web_reply_available? && router.connection.origin_enabled?(HYBRID_ORIGIN)
  end

  def template_problem(approved)
    return 'template_required' if approved.blank?
    return 'template_without_link' unless self.class.native_body(approved).include?(LINK_PLACEHOLDER)

    'template_unsupported' unless self.class.fillable_template?(approved)
  end

  def waha
    return skip('no_phone') if conversation.nil? && contact.phone_number.blank?

    session
  end

  def api
    return session if conversation && Crm::FollowUps::MessagingWindow.new(conversation).can_send_session_message?

    api_template = api_template_record
    return skip('template_required') if api_template.blank?

    Decision.new(mode: :api_template, conversation: conversation, template: api_template)
  end

  def session
    Decision.new(mode: :session, conversation: conversation)
  end

  def skip(reason)
    Decision.new(reason: reason)
  end

  def conversation
    return @conversation if defined?(@conversation)

    @conversation = if @preferred.present? && @preferred.inbox_id == inbox.id && @preferred.contact_id == contact.id
                      @preferred
                    else
                      contact.conversations.where(inbox_id: inbox.id).order(last_activity_at: :desc, id: :desc).first
                    end
  end

  def api_template_record
    id = template['id']
    return if id.blank?

    inbox.account.whatsapp_api_message_templates.active.for_inbox(inbox.id).find_by(id: id)
  end
end
