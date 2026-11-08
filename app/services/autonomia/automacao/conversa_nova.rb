# A conversa de quem não tem conversa (#2680, lote 3 da auditoria do #2414). O card do lead do formulário nasce sem
# conversa nem dono, e o contato do gatilho `contato.data` não tem conversa: sem ela, a mensagem, a espera, a IA e a
# agente pulavam com `sem_conversa`. A receita escolhe, no gatilho, a caixa por onde abrir (`conversa_nova.caixa_id`).
#
# - `existente`: a conversa do contato nessa caixa, a mais recente que não foi resolvida. É ela que os passos usam
#   depois que o passo "mensagem" a abriu (Contexto#conversa), sem guardar nada na execução.
# - `abrir`: o passo "mensagem" abre a conversa pela porta da frente, como o "Nova conversa" do painel
#   (ContactInboxBuilder + ConversationBuilder). A caixa que trava numa conversa só devolve a dela. Quem ligou precisa
#   estar na caixa (ou ser administrador) e poder começar conversa, conferido ao salvar e a cada abertura (Acesso).
#   A janela, o modelo aprovado e o opt-out são os do passo "mensagem": conversa nova no número oficial só sai com modelo.
#
# - `numero_trocado?` (#2700): no WhatsApp e no SMS a conversa fica presa ao número com que nasceu (o `source_id` do
#   ContactInbox). Depois de o telefone do contato mudar, o passo "mensagem" vai à conversa do número novo na mesma
#   caixa (`do_numero`, senão `abrir`), e não à do número antigo.
#
# Só as caixas em que a plataforma começa conversa pelo telefone do contato (ou pela API).
module Autonomia::Automacao::ConversaNova
  CANAIS = %w[Channel::Whatsapp Channel::TwilioSms Channel::Sms Channel::Api].freeze
  # Os canais que acham o contato pelo telefone; a caixa de API não pede.
  PELO_TELEFONE = %w[Channel::Whatsapp Channel::TwilioSms Channel::Sms].freeze

  module_function

  def caixa_id(receita) = receita.to_h.dig('gatilho', 'conversa_nova', 'caixa_id')

  def caixa(conta, caixa_id) = caixa_id && conta.inboxes.find_by(id: caixa_id, channel_type: CANAIS)

  # A caixa da receita da execução, ou nil (sem a escolha, ou a caixa foi apagada).
  def da_execucao(execucao) = caixa(execucao.account, caixa_id(execucao.versao&.receita))

  # Ao salvar: a caixa é da conta e de um canal que começa conversa, o gatilho tem alvo que pode não ter conversa (card
  # ou contato), e quem salva (`account_user`; nil no catálogo) pode começar conversa nela.
  def problemas_ao_salvar(conta, gatilho, account_user)
    id = gatilho.to_h.dig('conversa_nova', 'caixa_id')
    return [] if id.nil?
    return [frase(:conversa_nova_sem_alvo)] if ::Autonomia::Automacao::Gatilhos.alvo(gatilho['tipo']) == 'Conversation'

    escolhida = caixa(conta, id)
    return [frase(:conversa_nova_caixa_invalida, id: id)] if escolhida.nil?
    return [] if account_user.nil? || ::Autonomia::Automacao::Acesso.comeca_conversa?(account_user, escolhida)

    [frase(:conversa_nova_sem_acesso, id: id)]
  end

  def existente(caixa, contato)
    return if caixa.nil? || contato.nil?

    ::Conversation.where(account_id: caixa.account_id, inbox_id: caixa.id, contact_id: contato.id)
                  .where.not(status: :resolved).order(last_activity_at: :desc, id: :desc).first
  end

  # Por que a conversa não abriria para este contato, ou nil. O passo pula com o motivo.
  def motivo_do_contato(caixa, contato)
    return 'contato_sem_telefone' if pelo_telefone?(caixa) && contato.phone_number.blank?
    return 'numero_de_outro_contato' if numero_de_outro?(caixa, contato)

    'contato_nao_recebe' if ::Contact.opted_out.exists?(id: contato.id)
  end

  # Nos canais do telefone, o ContactInbox é o do número atual (o builder acha ou cria pelo telefone); na API, o que já
  # houver na caixa.
  def abrir(caixa, contato)
    contact_inbox = (::ContactInbox.find_by(contact_id: contato.id, inbox_id: caixa.id) unless pelo_telefone?(caixa)) ||
                    ::ContactInboxBuilder.new(contact: contato, inbox: caixa, source_id: nil).perform
    ::ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform
  end

  # O número da conversa não é mais o telefone do contato. Compara só os dígitos: o WhatsApp guarda sem o "+", o Twilio
  # com "whatsapp:".
  def numero_trocado?(conversa)
    telefone = conversa.contact&.phone_number
    return false if telefone.blank? || !pelo_telefone?(conversa.inbox)

    digitos(conversa.contact_inbox&.source_id) != digitos(telefone)
  end

  # A conversa não resolvida do número atual do contato na caixa, a mais recente; nil se não houver.
  def do_numero(caixa, contato)
    numero = digitos(contato.phone_number)
    ids = ::ContactInbox.where(contact_id: contato.id, inbox_id: caixa.id).filter_map { |item| item.id if digitos(item.source_id) == numero }
    ::Conversation.where(account_id: caixa.account_id, contact_inbox_id: ids).where.not(status: :resolved)
                  .order(last_activity_at: :desc, id: :desc).first
  end

  def pelo_telefone?(caixa) = PELO_TELEFONE.include?(caixa.channel_type)

  # O número já é de outro contato nesta caixa: o ContactInboxBuilder tiraria o número dele (renomeia o source_id do
  # outro) para dar a este. A automação não mexe no contato de outra pessoa; o passo pula. Os formatos do builder:
  # o WhatsApp sem o "+", o SMS com ele, o Twilio também com "whatsapp:".
  def numero_de_outro?(caixa, contato)
    return false unless pelo_telefone?(caixa)

    telefone = contato.phone_number
    formatos = [telefone, telefone.delete('+'), "whatsapp:#{telefone}"]
    ::ContactInbox.where(inbox_id: caixa.id, source_id: formatos).where.not(contact_id: contato.id).exists?
  end

  def digitos(texto) = texto.to_s.delete('^0-9')

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
