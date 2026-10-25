# Exclusão do usuário (#2135): solta o que as tabelas do fork guardam da pessoa, para o DELETE de `users` não esbarrar
# numa chave estrangeira sem `on_delete`. Roda no `before_destroy` do User (config/initializers/autonomia_exclusao_do_usuario.rb),
# dentro da transação do destroy, então vale para todo caminho que apaga a pessoa: o DeleteObjectJob (agente removido da
# última conta, Platform API) e o Super Admin. Roda depois dos dependentes do upstream (conversas, mensagens), na mesma
# ordem de travas do Agents::DestroyJob (conversas, depois cards), que pode estar rodando ao mesmo tempo.
#
# Regras (decisão do Rodrigo no #2135, 25/10):
# - Reunião futura passa para o primeiro administrador da conta, como o agendamento faz com quem sai da conta
#   (Crm::BookingV2::MeetingHandover: o lembrete do agente vai junto e o card ganha a atividade). Sem administrador,
#   fica sem autor, como a passada.
# - ANULAR: a linha é do negócio e fica; só o vínculo com a pessoa sai. Reunião passada sem autor mostra "Pessoa
#   removida"; campanha e modelo do WhatsApp ficam sem autor (nenhuma tela mostra o autor deles). É o que as chaves do
#   fork com `on_delete: :nullify` já fazem com "quem criou", e o que o Agents::DestroyJob faz com o card de quem sai
#   da conta (#2095). O card fica sem dono mesmo com a flag `crm_arquivados` desligada: a chave obriga, e o Rodrigo
#   confirmou.
# - PASSAR: o que outras pessoas usam e só tem a pessoa como dona vai para o primeiro administrador da conta: a visão
#   salva compartilhada e o lembrete ou a série sem card, contato nem empresa que avisa outra pessoa ou um time. Sem
#   administrador, sai.
# - APAGAR: o que só servia à pessoa: a visão salva privada, o link de agendamento individual (o convite que apontava
#   para ele fica, com a chave anulada pelo banco) e o lembrete ou a série avulsos que só avisavam ela.
# O histórico de quem fez o quê no card (crm_activities, Enterprise::AuditLog) não tem chave para users e não é tocado.
#
# `update_all`/`update_columns` de propósito: as validações recusariam gravar a linha de quem saiu
# (Crm::Card#validate_owner_account), e nenhum desses modelos tem callback que importe na saída. O que tem anexo sai com
# `destroy!`. Cada coluna precisa de filtros que, juntos, cubram todas as linhas dela (o spec só confere a coluna).
class Autonomia::ExclusaoDoUsuario
  LOTE = 5_000
  MODOS = Crm::FollowUpRecipients::RECIPIENT_MODES

  # Cards saem do dono em `soltar_cards`, que também refaz os contadores.
  CARDS = ['Crm::Card', :owner_id, :todas].freeze
  # Antes de anular o resto: o lembrete do agente vai junto com a reunião.
  REUNIOES_FUTURAS = ['Crm::Meeting', :created_by_id, :futuras].freeze

  # [modelo, coluna, filtro]
  ANULAR = [
    ['Crm::Meeting', :created_by_id, :todas],
    ['WhatsappApiCampaign', :created_by_id, :todas],
    ['WhatsappApiMessageTemplate', :created_by_id, :todas],
    ['WhatsappApiMessageTemplate', :updated_by_id, :todas],
    ['Crm::FollowUp', :assignee_id, :todas],
    ['Crm::FollowUp', :created_by_id, :com_outro_dono],
    ['Crm::FollowUpSeries', :created_by_id, :com_outro_dono],
    ['Crm::CardConversation', :linked_by_id, :todas],
    ['Crm::MeetingGuest', :user_id, :todas],
    ['Crm::Pipeline', :created_by_id, :todas],
    ['Crm::PipelineInbox', :created_by_id, :todas],
    ['Crm::StageAutomation', :created_by_id, :todas],
    ['Autonomia::Agents::Agent', :created_by_id, :todas],
    ['Autonomia::Agents::BuildThread', :created_by_id, :todas]
  ].freeze

  # [modelo, coluna, filtro]. Depois do ANULAR: o lembrete que era da pessoa já perdeu o responsável.
  PASSAR = [
    ['Crm::SavedView', :user_id, :compartilhadas],
    ['Crm::FollowUp', :created_by_id, :avulsos_que_avisam_outros],
    ['Crm::FollowUpSeries', :created_by_id, :avulsos_que_avisam_outros]
  ].freeze

  # [modelo, coluna, filtro]. O lembrete vem antes da série: a chave do lembrete para a série anula sozinha.
  APAGAR = [
    ['Crm::SavedView', :user_id, :privadas],
    ['Crm::AgentBookingLink', :agent_id, :todas],
    ['Crm::FollowUp', :created_by_id, :avulsos_so_dela],
    ['Crm::FollowUpSeries', :created_by_id, :avulsos_so_dela]
  ].freeze

  # Chaves para users sem `on_delete` que saem por associação do próprio User (has_many ... dependent: :destroy).
  SAEM_COM_O_USUARIO = { 'user_sessions' => 'User has_many :user_sessions, dependent: :destroy' }.freeze

  def self.colunas_tratadas
    ([CARDS, REUNIOES_FUTURAS] + ANULAR + PASSAR + APAGAR).map { |modelo, coluna| [modelo.constantize.table_name, coluna.to_s] }.uniq
  end

  def initialize(user)
    @user = user
    @administradores = {}
  end

  def soltar
    soltar_cards
    passar_reunioes_futuras
    ANULAR.each { |modelo, coluna, filtro| anular(linhas(modelo, coluna, filtro), coluna) }
    PASSAR.each { |modelo, coluna, filtro| passar(linhas(modelo, coluna, filtro), coluna) }
    APAGAR.each { |modelo, coluna, filtro| apagar(linhas(modelo, coluna, filtro)) }
  end

  private

  attr_reader :user

  # Como o Agents::DestroyJob#release_crm_cards: mudar o dono muda quem vê o card ("Só as suas"), então os contadores e a
  # visibilidade das conversas de cada conta são refeitos, depois do commit (antes dele o job leria o dono antigo).
  def soltar_cards
    cards = Crm::Card.unscoped.where(owner_id: user.id)
    conversas_por_conta = conversas_dos_cards(cards)
    # rubocop:disable Rails/SkipsModelValidations
    cards.in_batches(of: LOTE).update_all(owner_id: nil, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    return if conversas_por_conta.empty?

    ActiveRecord.after_all_transactions_commit do
      conversas_por_conta.each { |conta, conversas| Crm::Access::CountInvalidation.card_changed!(conta, conversas) }
    end
  end

  def conversas_dos_cards(cards)
    diretas = cards.pluck(:account_id, :conversation_id)
    vinculadas = Crm::CardConversation.unscoped.where(card_id: cards.select(:id)).pluck(:account_id, :conversation_id)
    (diretas + vinculadas).group_by(&:first).transform_values { |pares| pares.filter_map(&:last).uniq }
  end

  # Com a trava de agente do agendamento (a mesma do Booker e do OrphanReassigner) de quem sai e de quem recebe: nenhuma
  # reserva nova entra para a pessoa até o DELETE, e um OrphanReassignJob em paralelo não passa a mesma reunião.
  # Sem conferir a agenda de quem recebe: o OrphanReassigner, ocupado o administrador, deixa a reunião com quem saiu;
  # aqui quem saiu deixa de existir.
  def passar_reunioes_futuras
    reunioes = linhas(*REUNIOES_FUTURAS)
    travados = [user.id, *administradores_de(reunioes)]
    Crm::BookingV2::HostSchedule.lock!(travados)
    # Reserva que entrou antes da trava, numa conta que a lista ainda não tinha: o administrador dela trava agora.
    Crm::BookingV2::HostSchedule.lock!(administradores_de(reunioes) - travados)

    reunioes.includes(:card, :reminder).find_each do |reuniao|
      administrador = primeiro_administrador(reuniao.account_id)
      passar_reuniao(reuniao, administrador) if administrador
    end
  end

  def administradores_de(reunioes)
    reunioes.distinct.pluck(:account_id).filter_map { |conta| primeiro_administrador(conta)&.id }
  end

  def passar_reuniao(reuniao, administrador)
    ActiveRecord::Base.transaction(requires_new: true) do
      Crm::BookingV2::MeetingHandover.new(meeting: reuniao, from_user_id: user.id, to_user: administrador,
                                          reason: 'user_deleted').perform
    end
  rescue ActiveRecord::RecordInvalid
    # Reunião com dado antigo que não passa mais na validação: o responsável e o lembrete dele mudam mesmo assim, sem a
    # atividade (o savepoint desfez o que o MeetingHandover tinha feito).
    # rubocop:disable Rails/SkipsModelValidations
    reuniao.update_columns(created_by_id: administrador.id, updated_at: Time.current)
    Crm::FollowUp.unscoped.where(id: reuniao.reminder_id, assignee_id: user.id, status: Crm::FollowUp.statuses[:pending])
                 .update_all(assignee_id: administrador.id, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    Rails.logger.warn("[ExclusaoDoUsuario] usuario=#{user.id} reunião #{reuniao.id} passada sem validação")
  end

  # Quem sai também deixa a lista de quem recebe o aviso: senão o lembrete não se grava mais (a pessoa não é da conta).
  def passar(relacao, coluna)
    relacao.find_each do |linha|
      administrador = primeiro_administrador(linha.account_id)
      next linha.destroy! if administrador.blank?

      mudancas = { coluna => administrador.id, :updated_at => Time.current }
      mudancas[:recipient_user_ids] = linha.recipient_user_ids - [user.id] if linha.has_attribute?(:recipient_user_ids)
      linha.update_columns(mudancas) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # O mesmo critério do Crm::BookingV2::OrphanReassigner: administrador humano mais antigo da conta, fora quem sai.
  def primeiro_administrador(account_id)
    @administradores.fetch(account_id) do
      @administradores[account_id] = AccountUser.human.administrator.where(account_id: account_id).where.not(user_id: user.id)
                                                .order(:id).first&.user
    end
  end

  def anular(relacao, coluna)
    relacao.in_batches(of: LOTE).update_all(coluna => nil) # rubocop:disable Rails/SkipsModelValidations
  end

  def apagar(relacao)
    return relacao.find_each(&:destroy!) if relacao.klass.reflect_on_all_attachments.any?

    relacao.in_batches(of: LOTE).delete_all
  end

  def linhas(modelo, coluna, filtro)
    send(filtro, modelo.constantize.unscoped.where(coluna => user.id))
  end

  def todas(relacao) = relacao

  def futuras(relacao) = relacao.upcoming

  def privadas(relacao) = relacao.where(visibility: Crm::SavedView.visibilities[:private_view])

  def compartilhadas(relacao) = relacao.where.not(visibility: Crm::SavedView.visibilities[:private_view])

  def com_outro_dono(relacao) = relacao.where('card_id IS NOT NULL OR contact_id IS NOT NULL OR company_id IS NOT NULL')

  def sem_outro_dono(relacao) = relacao.where(card_id: nil, contact_id: nil, company_id: nil)

  # Avulso que avisa outra pessoa: um time, pessoas escolhidas além de quem sai ou (só o lembrete) um responsável que não
  # é quem sai (o dela o ANULAR já zerou).
  def avulsos_que_avisam_outros(relacao)
    avulsos = sem_outro_dono(relacao)
    outras_pessoas = avulsos.where(recipient_mode: MODOS[:users])
                            .where('EXISTS (SELECT 1 FROM unnest(recipient_user_ids) AS escolhida WHERE escolhida <> ?)', user.id)
    para_outros = avulsos.where(recipient_mode: MODOS[:team]).or(outras_pessoas)
    relacao.klass.column_names.include?('assignee_id') ? para_outros.or(avulsos.where.not(assignee_id: nil)) : para_outros
  end

  def avulsos_so_dela(relacao)
    sem_outro_dono(relacao).where.not(id: avulsos_que_avisam_outros(relacao).select(:id))
  end
end
