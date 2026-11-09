# G43 (#2700, ex. 19 do #2414): o cliente trocou de número. No WhatsApp e no SMS a conversa fica presa ao número com
# que nasceu (`ContactInbox.source_id`); trocar o telefone do contato não muda a conversa. Sem isto, o passo "mensagem"
# mandava no número antigo, que acabou de falhar.
#
# - `trocou?`: o número da conversa morreu e o telefone do contato é outro. Vale nas caixas que acham o contato pelo
#   telefone (as da conversa nova, ConversaNova::PELO_TELEFONE). No WhatsApp o número vem sem o "+", e o nono dígito do
#   Brasil (e as variações da Argentina e do México) conta como o mesmo número: são os candidatos que o recebimento já
#   usa (Whatsapp::PhoneNumberNormalizationService). Contato sem telefone não trocou.
# - `numero_morto?`: a última mensagem da empresa nessa conversa falhou, e o cliente não escreveu depois. Telefone
#   diferente sozinho não basta: o contato com dois números (o merge de contatos guarda um só, a edição à mão, a
#   importação) continua escrevendo do número da conversa, e a resposta tem de voltar para ele.
# - `conversa`: a do número novo na mesma caixa. Reaproveita a aberta mais recente; sem ela, abre como a conversa nova
#   (o número no formato do canal, o mesmo do ContactInboxBuilder, + ConversationBuilder). `existente` só procura.
# - `de_outro_contato?`: o número novo já é de outro contato nesta caixa. O passo pula e não mexe no outro contato (o
#   ContactInboxBuilder renomearia o número dele).
#
# O número da conversa no formato de identificador do WhatsApp (`@lid`, `@c.us`) não é telefone: não compara.
#
# Quem decide abrir, e desfaz o que não saiu, é o passo "mensagem" (PassoDeMensagem). Os passos seguintes acham essa
# conversa pelo registro dele (Contexto#conversa).
module Autonomia::Automacao::NumeroNovo
  DIGITOS = ('0'..'9')

  module_function

  def trocou?(conversa)
    return false unless conversa && ::Autonomia::Automacao::ConversaNova::PELO_TELEFONE.include?(conversa.inbox.channel_type)

    telefone = digitos(conversa.contact&.phone_number)
    numero = numero_da_conversa(conversa)
    return false if telefone.empty? || numero.empty?

    !mesmo_numero?(conversa.inbox, telefone, numero) && numero_morto?(conversa)
  end

  def numero_morto?(conversa)
    ultima = conversa.messages.where(message_type: :outgoing, private: false).reorder(created_at: :desc, id: :desc).first
    return false unless ultima&.failed?

    !conversa.messages.where(message_type: :incoming).exists?(['created_at > ?', ultima.created_at])
  end

  # Os algarismos do número com que a conversa nasceu; vazio quando ele é um identificador do WhatsApp (`@lid`, `@c.us`).
  def numero_da_conversa(conversa)
    origem = conversa.contact_inbox&.source_id.to_s
    origem.include?('@') ? '' : digitos(origem)
  end

  def conversa(antiga)
    contact_inbox = do_numero_novo(antiga) ||
                    ::ContactInbox.create!(contact: antiga.contact, inbox: antiga.inbox, source_id: fonte(antiga))
    aberta(contact_inbox) ||
      ::ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform
  end

  def existente(antiga)
    contact_inbox = do_numero_novo(antiga)
    aberta(contact_inbox) if contact_inbox && contact_inbox.contact_id == antiga.contact_id
  end

  def de_outro_contato?(antiga)
    dono = do_numero_novo(antiga)&.contact_id
    dono.present? && dono != antiga.contact_id
  end

  def do_numero_novo(antiga) = antiga.inbox.contact_inboxes.find_by(source_id: fonte(antiga))

  def aberta(contact_inbox) = contact_inbox.conversations.where.not(status: :resolved).order(last_activity_at: :desc, id: :desc).first

  # O telefone novo no formato do canal, como o ContactInboxBuilder o gera.
  def fonte(antiga)
    telefone = antiga.contact.phone_number
    case antiga.inbox.channel_type
    when 'Channel::Whatsapp' then telefone.delete('+')
    when 'Channel::TwilioSms' then antiga.inbox.channel.medium == 'whatsapp' ? "whatsapp:#{telefone}" : telefone
    else telefone
    end
  end

  def mesmo_numero?(caixa, telefone, numero)
    candidatos = ::Whatsapp::PhoneNumberNormalizationService.new(caixa)
    candidatos.phone_number_candidates(telefone).include?(numero) || candidatos.phone_number_candidates(numero).include?(telefone)
  end

  # Só os algarismos: o WhatsApp guarda "5511…", o SMS "+5511…" e o Twilio "whatsapp:+5511…".
  def digitos(valor) = valor.to_s.each_char.select { |caractere| DIGITOS.cover?(caractere) }.join
end
