# Exclusão do usuário (#2135): solta o que as tabelas do fork guardam da pessoa, para o DELETE de `users` não esbarrar
# numa chave estrangeira sem `on_delete`. Roda no `before_destroy` do User (config/initializers/autonomia_exclusao_do_usuario.rb),
# dentro da transação do destroy, então vale para todo caminho que apaga a pessoa: o DeleteObjectJob (agente removido da
# última conta, Platform API) e o Super Admin. Dois passos:
# - `pode_sair?` roda primeiro (prepend): se alguma linha espera decisão, nada é feito;
# - `soltar` roda depois dos dependentes do upstream (conversas, mensagens), na mesma ordem de travas do
#   Agents::DestroyJob (conversas, depois cards), que pode estar rodando ao mesmo tempo.
#
# A regra de cada tabela segue o que o fork já decidiu:
# - ANULAR: a linha é do negócio e fica; só o vínculo com a pessoa sai. É o que as chaves do fork com
#   `on_delete: :nullify` já fazem com "quem criou" (versões de instrução, perfis de pontuação, kits de marca, tokens) e o
#   que o Agents::DestroyJob faz com o card de quem sai da conta (#2095). O histórico de quem fez o quê no card
#   (crm_activities, Enterprise::AuditLog) não tem chave para users e não é tocado.
# - APAGAR: o que só servia à pessoa: a visão salva privada dela e o link de agendamento individual (o OrphanReassigner
#   já desliga esse link quando ela sai da conta; o convite que apontava para ele fica, com a chave anulada pelo banco).
#   `destroy_all`, para a imagem de prévia do link ir para o purge.
# - PENDENTES: o autor é obrigatório (NOT NULL) ou a linha ficaria sem dono nenhum. Esperam decisão do Rodrigo no #2135;
#   enquanto isso a exclusão para com erro claro, nada é alterado, e o log diz quais tabelas barraram.
#
# `update_all` de propósito: as validações recusariam gravar a linha de quem saiu (Crm::Card#validate_owner_account), e
# nenhum dos modelos anulados tem callback que importe na saída.
class Autonomia::ExclusaoDoUsuario
  LOTE = 5_000
  # Tipo do erro em user.errors quando a pessoa não pode sair (o DeleteObjectJob o reconhece).
  ERRO = :exclusao_pendente

  # O card sai do dono em `soltar_cards`, que também refaz os contadores.
  CARDS = ['Crm::Card', :owner_id].freeze

  # [modelo, coluna, filtro]. Lembrete e série só perdem o criador quando têm outro dono (card, contato ou empresa): sem
  # ele, o lembrete fica sem dono (a trava crm_follow_ups_has_owner recusa a linha, e a série geraria lembretes que ela
  # recusa). Esses ficam em PENDENTES.
  ANULAR = [
    ['Crm::FollowUp', :assignee_id, :todas],
    ['Crm::FollowUp', :created_by_id, :com_outro_dono],
    ['Crm::FollowUpSeries', :created_by_id, :com_outro_dono],
    ['Crm::CardConversation', :linked_by_id, :todas],
    ['Crm::MeetingGuest', :user_id, :todas],
    ['Crm::Pipeline', :created_by_id, :todas],
    ['Crm::PipelineInbox', :created_by_id, :todas],
    ['Crm::StageAutomation', :created_by_id, :todas],
    ['Autonomia::Agents::Agent', :created_by_id, :todas],
    ['Autonomia::Agents::BuildThread', :created_by_id, :todas],
    ['WhatsappApiMessageTemplate', :updated_by_id, :todas]
  ].freeze

  APAGAR = [
    ['Crm::SavedView', :user_id, :privadas],
    ['Crm::AgentBookingLink', :agent_id, :todas]
  ].freeze

  PENDENTES = [
    ['Crm::Meeting', :created_by_id, :todas],
    ['WhatsappApiCampaign', :created_by_id, :todas],
    ['WhatsappApiMessageTemplate', :created_by_id, :todas],
    ['Crm::SavedView', :user_id, :compartilhadas],
    ['Crm::FollowUp', :created_by_id, :sem_outro_dono],
    ['Crm::FollowUpSeries', :created_by_id, :sem_outro_dono]
  ].freeze

  # Chaves para users sem `on_delete` que saem por associação do próprio User (has_many ... dependent: :destroy).
  SAEM_COM_O_USUARIO = { 'user_sessions' => 'User has_many :user_sessions, dependent: :destroy' }.freeze

  def self.colunas_tratadas
    ([CARDS] + ANULAR + APAGAR + PENDENTES).map { |modelo, coluna| [modelo.constantize.table_name, coluna.to_s] }.uniq
  end

  def initialize(user)
    @user = user
  end

  # true quando a pessoa pode sair; false (com o motivo em user.errors) quando alguma linha ainda depende de decisão.
  def pode_sair?
    bloqueios = pendentes
    bloqueios.empty? || recusar(bloqueios)
  end

  def soltar
    soltar_cards
    ANULAR.each { |modelo, coluna, filtro| anular(linhas(modelo, coluna, filtro), coluna) }
    APAGAR.each { |modelo, coluna, filtro| linhas(modelo, coluna, filtro).find_each(&:destroy!) }
  end

  private

  attr_reader :user

  def pendentes
    PENDENTES.filter_map { |modelo, coluna, filtro| modelo.constantize.table_name if linhas(modelo, coluna, filtro).exists? }.uniq
  end

  def recusar(tabelas)
    # Só ids e nomes de tabela: nada da linha nem da pessoa.
    Rails.logger.warn("[ExclusaoDoUsuario] usuario=#{user.id} não saiu: #{tabelas.join(', ')} esperam decisão (#2135)")
    user.errors.add(:base, ERRO, message: I18n.t('autonomia.exclusao_do_usuario.pendente', tabelas: tabelas.join(', ')))
    false
  end

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

  def anular(relacao, coluna)
    relacao.in_batches(of: LOTE).update_all(coluna => nil) # rubocop:disable Rails/SkipsModelValidations
  end

  def linhas(modelo, coluna, filtro)
    classe = modelo.constantize
    send(filtro, classe.unscoped.where(coluna => user.id))
  end

  def todas(relacao) = relacao

  def privadas(relacao) = relacao.where(visibility: Crm::SavedView.visibilities[:private_view])

  def compartilhadas(relacao) = relacao.where.not(visibility: Crm::SavedView.visibilities[:private_view])

  def com_outro_dono(relacao) = relacao.where('card_id IS NOT NULL OR contact_id IS NOT NULL OR company_id IS NOT NULL')

  def sem_outro_dono(relacao) = relacao.where(card_id: nil, contact_id: nil, company_id: nil)
end
