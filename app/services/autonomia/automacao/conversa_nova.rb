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
  # ou contato: a conversa já existe, e a conta do recorrente, G7, não tem com quem falar), e quem salva
  # (`account_user`; nil no catálogo) pode começar conversa nela.
  ALVOS = [::Autonomia::Automacao::Gatilhos::CARD, ::Autonomia::Automacao::Gatilhos::CONTATO].freeze

  # `ramos`: o tipo do registro em que cada "em outro registro" da receita roda (G18). G49: o ramo no card ou no contato
  # que um passo criou (o card do João, sem conversa) abre a conversa por esta caixa, mesmo num gatilho de conversa.
  RAMOS = %w[Crm::Card Contact].freeze

  def problemas_ao_salvar(conta, gatilho, account_user, ramos: [])
    id = gatilho.to_h.dig('conversa_nova', 'caixa_id')
    return [] if id.nil?

    sem_conversa = ALVOS.include?(::Autonomia::Automacao::Gatilhos.alvo(gatilho['tipo'])) || ramos.intersect?(RAMOS)
    return [frase(:conversa_nova_sem_alvo)] unless sem_conversa

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
    return 'contato_sem_telefone' if PELO_TELEFONE.include?(caixa.channel_type) && contato.phone_number.blank?

    'contato_nao_recebe' if ::Contact.opted_out.exists?(id: contato.id)
  end

  def abrir(caixa, contato)
    contact_inbox = ::ContactInbox.find_by(contact_id: contato.id, inbox_id: caixa.id) ||
                    ::ContactInboxBuilder.new(contact: contato, inbox: caixa, source_id: nil).perform
    ::ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform
  end

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
