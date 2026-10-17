# As linhas que só o CÓDIGO gera para o bloco B (#1601): rótulo e valor montados aqui, nunca texto do cliente, da
# equipe ou do modelo; origem sempre :sistema. Nomes de pessoa: o do cadastro do usuário.
#   estado.canal          o canal da caixa ("WhatsApp: o número do cliente é o desta conversa")
#   compromisso.retomar   a tarefa de retomar aberta: quem deve a resposta e desde quando
#   falta                 as chaves obrigatórias do pedido em foco ainda vazias
#   dono_previsto         quem receberia a conversa numa passagem agora (Crm::Memoria::DonoPrevisto), ou "ninguém"
class Crm::Memoria::Leitor::DoSistema
  WHATSAPP = 'WhatsApp: o número do cliente é o desta conversa; não peça o WhatsApp dele'.freeze
  CANAIS = { 'Channel::Email' => 'e-mail', 'Channel::WebWidget' => 'chat do site', 'Channel::Instagram' => 'Instagram',
             'Channel::FacebookPage' => 'Messenger', 'Channel::Telegram' => 'Telegram', 'Channel::Sms' => 'SMS',
             'Channel::TwilioSms' => 'SMS', 'Channel::Api' => 'integração (API)' }.freeze
  NINGUEM = 'ninguém (sem dono previsto)'.freeze

  def initialize(conversation:, card:, catalogo:)
    @conversation = conversation
    @card = card
    @catalogo = catalogo
    @fuso = Crm::Timezone::Resolver.new(account: conversation.account).name_or_default
  end

  def linhas
    [canal, compromisso, falta, dono_previsto].compact
  end

  private

  def canal
    linha('estado.canal', 'Canal', whatsapp? ? WHATSAPP : CANAIS.fetch(inbox.channel_type, 'outro canal'), nil)
  end

  def whatsapp?
    inbox.whatsapp? || inbox.twilio_whatsapp? || (inbox.api? && inbox.channel.try(:additional_attributes).to_h['provider'] == 'waha')
  end

  def compromisso
    tarefa = Crm::Memoria::Compromissos.abertas(@conversation).first
    return if tarefa.nil?

    desde = Time.zone.parse(tarefa.metadata.dig('memoria', 'desde').to_s) || tarefa.created_at
    donos = User.where(id: tarefa.recipient_user_ids).order(:id).pluck(:name).compact_blank.first(3).join(', ')
    texto = "A equipe deve uma resposta ao cliente desde #{desde.in_time_zone(@fuso).strftime('%d/%m/%Y %H:%M')}; " \
            "com: #{donos.presence || 'a equipe'}; pendente"
    linha('compromisso.retomar', 'Retomar atendimento', texto, desde)
  end

  def falta
    faltam = faltam_no_pedido
    return if faltam.empty?

    linha('falta', 'Falta no pedido', faltam.map { |chave| chave.rotulo.presence || chave.chave }.join(', '), nil)
  end

  def faltam_no_pedido
    return [] if @card.nil?

    preenchidas = Crm::MemoriaFato.vigentes.where(account_id: @card.account_id, card_id: @card.id).pluck(:chave) +
                  @card.custom_attributes.to_h.compact_blank.keys
    @catalogo.values.select { |chave| chave.obrigatoria? && chave.attribute_model == 'card_attribute' && preenchidas.exclude?(chave.chave) }
  end

  def dono_previsto
    pessoa = Crm::Memoria::DonoPrevisto.para(@conversation, card: @card)
    linha('dono_previsto', 'Quem receberia numa passagem agora', pessoa&.name.presence || NINGUEM, nil)
  end

  def linha(chave, rotulo, valor, quando)
    Crm::Memoria::Leitor::Linha.new(id: nil, chave: chave, rotulo: rotulo, valor: valor, origem: :sistema, em: quando || Time.current,
                                    message_id: nil, card_id: @card&.id, status: :vigente)
  end

  def inbox
    @conversation.inbox
  end
end
