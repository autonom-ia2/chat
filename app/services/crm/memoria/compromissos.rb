# A TAREFA DE RETOMAR O ATENDIMENTO (#1601, W2/W3). Quando a IA (ou um robô) passa a conversa para uma pessoa, ou a
# Entrega segura a conversa porque ninguém pode receber agora, alguém da equipe fica devendo uma resposta ao cliente.
# Essa dívida vira UMA tarefa por conversa, em `crm_follow_ups` (tipo task, `metadata.memoria`), sem tabela nova:
#
#   Crm::Memoria::Compromissos.abrir_retomada!(conversation:, origem:, passagem: nil)
#   Crm::Memoria::Compromissos.depois_da_mensagem!(origem)   # W3, só no evento ao vivo
#   Crm::Memoria::Compromissos.acompanhar_dono!(conversation)
#   Crm::Memoria::Compromissos.conversa_resolvida!(conversation)
#
# Decisões do Rodrigo (16/10/2026):
# - D3: sem prazo e sem escala. A tarefa nasce com `due_at` = agora (a data de quando nasceu) e o DueProcessor não a
#   processa: ela não vence, não avisa e não escala sozinha. Fica aberta até a resposta real.
# - D2: nenhum aviso automático ao cliente. Sem sininho novo.
#
# Uma por conversa: o índice único parcial idx_crm_followups_memoria_retomar_aberta. A passagem real reaproveita a
# tarefa da conversa segurada (preenche a passagem e o dono). Reatribuição pessoa -> pessoa não cria tarefa: o dono
# da que existe acompanha quem está com a conversa (acompanhar_dono!).
#
# Dono (recipient_mode users): quem está com a conversa; sem ninguém, quem cuida dela (Crm::Entrega::QuemCuida);
# lista vazia, os administradores da caixa e, sem eles, os da conta (a mesma ordem do AvisoSemNinguem). Nunca vazio.
#
# Fecha SÓ com resposta real ao cliente (Crm::MensagemOrigem#resposta_da_pessoa?): pessoa pelo painel ou pelo celular,
# pública, que não falhou e não é encaminhamento. Nota privada, follow-up automático, robô declarado e a nossa IA não
# fecham. A resposta que depois vira `failed` reabre a tarefa que ela fechou.
module Crm::Memoria::Compromissos
  TIPO = 'retomar_atendimento'.freeze
  ABERTAS = %w[pending overdue].freeze
  # Passagens que criam a tarefa: de IA ou robô para pessoa. O convite não: a IA segue com a conversa.
  DE_IA = ['Autonomia::Agents::Agent', 'AgentBot'].freeze
  ESPERA_DA_ENTREGA = 10.seconds
  SQL_DA_MEMORIA = "(crm_follow_ups.metadata #>> '{memoria,tipo}') = ?".freeze

  module_function

  def abertas(conversation)
    Crm::FollowUp.where(account_id: conversation.account_id, conversation_id: conversation.id, status: ABERTAS)
                 .where(SQL_DA_MEMORIA, TIPO)
  end

  def da_conversa(conversation)
    Crm::FollowUp.where(account_id: conversation.account_id, conversation_id: conversation.id).where(SQL_DA_MEMORIA, TIPO)
  end

  # A passagem cria a tarefa? De IA ou robô para pessoa, fora o convite.
  def cria_tarefa?(passagem)
    passagem.para_type == 'User' && DE_IA.include?(passagem.de_type) && passagem.motivo != Crm::Passagens::CONVITE
  end

  # `origem`: 'passagem' ou 'segurada'. Trava a conversa (a mesma ordem da Entrega e das Passagens). Idempotente: a
  # tarefa aberta da conversa é reaproveitada; a corrida com outro processo esbarra no índice único e relê.
  def abrir_retomada!(conversation:, origem:, passagem: nil)
    return unless Crm::Memoria.ativa?(conversation)
    # O contato apagado (a conversa sai depois, em segundo plano) não deve mais nada a ninguém.
    return unless Contact.exists?(id: conversation.contact_id, account_id: conversation.account_id)

    Crm::FollowUp.transaction(requires_new: true) do
      Conversation.where(id: conversation.id).lock.pick(:id)
      conversation.reload
      aberta = abertas(conversation).first
      next reaproveitar!(aberta, conversation, passagem) if aberta

      desde = desde_de(conversation, passagem)
      next if ja_respondida?(conversation, desde: desde)

      criar!(conversation, origem, passagem, desde)
    end
  rescue ActiveRecord::RecordNotUnique
    abertas(conversation).first
  end

  # A Entrega segurou a conversa: a tarefa nasce depois do commit da Entrega (o job relê a marca; se a Entrega desfez,
  # nada nasce). A conciliação cobre o que faltar.
  def depois_de_segurar(conversation)
    return unless Crm::Memoria.ativa?(conversation)

    Crm::Memoria::ConversaJob.set(wait: ESPERA_DA_ENTREGA).perform_later(conversation.id, 'segurada')
  end

  # W3: a mensagem gravada (ao vivo) fecha ou reabre a tarefa.
  def depois_da_mensagem!(origem)
    return fechar!(origem) if origem.resposta_da_pessoa?

    reabrir!(origem)
  end

  # A tarefa acompanha quem está com a conversa (ASSIGNEE_CHANGED). Sem ninguém: volta à fila (quem cuida).
  def acompanhar_dono!(conversation)
    tarefa = abertas(conversation).first
    return if tarefa.nil?

    tarefa.update!(dono_atributos(conversation).merge(metadata: memoria(tarefa, 'sem_dono_agora' => sem_pessoa?(conversation))))
  end

  # Conversa resolvida com a tarefa aberta: fica marcada "confirmar" (alguém confere se houve resposta), sem fechar.
  def conversa_resolvida!(conversation)
    abertas(conversation).find_each { |tarefa| tarefa.update!(metadata: memoria(tarefa, 'confirmar' => true)) }
  end

  # Desde quando a conversa deve a resposta: a passagem, ou o início da espera da Entrega.
  def desde_de(conversation, passagem)
    passagem&.em || Crm::Entrega::Marca.desde(conversation) || Time.current
  end

  def criar!(conversation, origem, passagem, desde)
    ids = donos(conversation, passagem)
    return Rails.logger.error("[crm][memoria] tarefa_sem_dono conversa=#{conversation.id}") if ids.empty?

    memoria = { 'tipo' => TIPO, 'origem' => origem, 'passagem_id' => passagem&.id, 'passagem_ids' => [passagem&.id].compact,
                'desde' => desde.iso8601, 'sem_dono_agora' => sem_pessoa?(conversation), 'confirmar' => false }
    Crm::FollowUp.create!(da_conversa_atributos(conversation).merge(
                            follow_up_type: :task, automation_mode: :reminder_only, due_at: Time.current, metadata: { 'memoria' => memoria },
                            recipient_mode: :users, recipient_user_ids: ids, assignee_id: ids.first
                          ))
  end

  def da_conversa_atributos(conversation)
    conta = conversation.account
    { account_id: conta.id, conversation_id: conversation.id, contact_id: conversation.contact_id, inbox_id: conversation.inbox_id,
      card_id: Crm::Assunto.funil_atual(conversation)&.id, title: I18n.with_locale(conta.locale) { I18n.t('crm.memoria.retomar.titulo') },
      timezone: Crm::Timezone::Resolver.new(account: conta).name_or_default }
  end

  # A passagem mais nova leva a tarefa (preenche a passagem e o dono). Uma passagem mais velha que a última registrada
  # (a conciliação chegando tarde) não muda nada: só entra na lista.
  def reaproveitar!(tarefa, conversation, passagem)
    return reaproveitar_sem_passagem!(tarefa, conversation) if passagem.nil?

    memoria_atual = tarefa.metadata.to_h['memoria'].to_h
    vistas = Array(memoria_atual['passagem_ids'])
    return tarefa if vistas.include?(passagem.id)

    extras = { 'passagem_ids' => vistas + [passagem.id] }
    return tarefa.tap { |linha| linha.update!(metadata: memoria(linha, extras)) } if memoria_atual['passagem_id'].to_i > passagem.id

    passar_tarefa!(tarefa, conversation, passagem, extras)
  end

  def passar_tarefa!(tarefa, conversation, passagem, extras)
    extras = extras.merge('passagem_id' => passagem.id, 'sem_dono_agora' => sem_pessoa?(conversation))
    tarefa.update!(dono_atributos(conversation, passagem).merge(metadata: memoria(tarefa, extras)))
    tarefa
  end

  def reaproveitar_sem_passagem!(tarefa, conversation)
    tarefa.update!(dono_atributos(conversation).merge(metadata: memoria(tarefa, 'sem_dono_agora' => sem_pessoa?(conversation))))
    tarefa
  end

  # Fecha a tarefa cuja dívida começou antes desta resposta (`desde`: a passagem ou o início da espera). Comparar com o
  # `desde`, e não com a criação da tarefa, fecha também a que nasceu depois da resposta (job ou conciliação atrasados).
  def fechar!(origem)
    respondida_em = origem_criada_em(origem)
    abertas(origem.conversation).find_each do |tarefa|
      desde = Time.zone.parse(tarefa.metadata.dig('memoria', 'desde').to_s) || tarefa.created_at
      next if respondida_em < desde

      tarefa.update!(status: :done, completed_at: Time.current,
                     metadata: memoria(tarefa, 'cumprida_por_message_id' => origem.message_id))
    end
  end

  # A resposta que fechou a tarefa falhou no envio: a tarefa volta a ficar aberta (se a conversa não abriu outra).
  def reabrir!(origem)
    return if origem.foi_ao_cliente?

    Crm::FollowUp.where(account_id: origem.account_id, conversation_id: origem.conversation_id, status: :done)
                 .where(SQL_DA_MEMORIA, TIPO)
                 .where("(crm_follow_ups.metadata #>> '{memoria,cumprida_por_message_id}') = ?", origem.message_id.to_s)
                 .find_each { |tarefa| tarefa.update!(status: :pending, completed_at: nil) }
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # A mensagem é mais nova que a tarefa: o horário da mensagem (a origem é gravada depois, pelo job).
  def origem_criada_em(origem)
    Message.where(id: origem.message_id).pick(:created_at) || origem.created_at
  end

  # Alguém da equipe já respondeu ao cliente depois da passagem: a dívida não existe mais (a conciliação chega tarde).
  def ja_respondida?(conversation, desde:)
    return false if desde.nil?

    Crm::MensagemOrigem.where(account_id: conversation.account_id, conversation_id: conversation.id,
                              autor_tipo: Crm::MensagemOrigem::PESSOAS, foi_ao_cliente: true, encaminhada: false)
                       .exists?(message_id: Message.where(conversation_id: conversation.id, created_at: desde..).select(:id))
  end

  def dono_atributos(conversation, passagem = nil)
    ids = donos(conversation, passagem)
    { recipient_mode: :users, recipient_user_ids: ids, assignee_id: ids.first }
  end

  # Quem recebeu a passagem (a pessoa), quem está com a conversa, quem cuida dela, ou os administradores.
  def donos(conversation, passagem = nil)
    candidatos = [(passagem.para_id if passagem&.para_type == 'User'), conversation.assignee_id].compact
    pessoa = candidatos.find { |id| pessoa_da_conta?(conversation, id) }
    return [pessoa] if pessoa

    card = Crm::Assunto.funil_atual(conversation)
    Crm::Entrega::QuemCuida.new(conversation: conversation, card: card).pessoas.map(&:id).presence || administradores(conversation)
  end

  def sem_pessoa?(conversation)
    conversation.assignee_id.blank?
  end

  def pessoa_da_conta?(conversation, user_id)
    AccountUser.exists?(account_id: conversation.account_id, user_id: user_id)
  end

  def administradores(conversation)
    admins = AccountUser.where(account_id: conversation.account_id).administrator.select(:user_id)
    da_caixa = conversation.inbox.members.where(id: admins).order(:id).pluck(:id)
    da_caixa.presence || User.where(id: admins).order(:id).pluck(:id).presence ||
      AccountUser.where(account_id: conversation.account_id).order(:user_id).limit(1).pluck(:user_id)
  end

  def memoria(tarefa, extras)
    metadata = tarefa.metadata.to_h.deep_dup
    metadata.merge('memoria' => metadata['memoria'].to_h.merge(extras))
  end
end
