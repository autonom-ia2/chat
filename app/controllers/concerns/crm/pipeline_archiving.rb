# Arquivar, restaurar e a prévia do arquivamento do funil (#2095), no Api::V1::Accounts::Crm::PipelinesController. A
# regra do último funil ativo e do único principal (Parte A) vale no DELETE como no PATCH: o Crm::Pipelines::Archiver a
# confere sob a mesma trava de arquivar da conta (Crm::Pipelines::TravaDeArquivar), e a recusa sai pela mesma resposta
# (render_archive_blocked).
#
# Contagens: arquivar, restaurar e a prévia contam todos os cards do funil (`@pipeline.cards`, sem o escopo de quem
# pede), porque só chega a elas quem gerencia o funil (PipelinePolicy#destroy?, #restore? e #archive_preview?) e decide
# por todos os cards dele. A lista de funis arquivados, que qualquer um com o CRM vê, conta só os cards visíveis
# (archived_pipeline_counts).
module Crm::PipelineArchiving
  extend ActiveSupport::Concern

  RESTORE_NOT_ARCHIVED = 'crm.pipeline_restore_not_archived'.freeze
  ARCHIVE_ALREADY_ARCHIVED = 'crm.pipeline_archive_already_archived'.freeze

  # Nome próprio: um segundo before_action :fetch_pipeline com outro `only` substituiria o do controller (show, update).
  included do
    before_action :fetch_pipeline_to_archive, only: [:destroy, :restore, :archive_preview]
  end

  # Arquivar. Parâmetros opcionais, todos de outro funil ativo que a pessoa vê, na mesma transação:
  # - `move_to_stage_id`: os cards abertos vão para essa etapa. Sem ele, ficam no funil e voltam quando ele for
  #   restaurado.
  # - `stop_follow_ups`: sem `move_to_stage_id`, os retornos marcados dos cards que ficam param ("Guardar junto").
  #   Sem ele, ficam como estão, como antes do #2095.
  # - `inboxes_to_pipeline_id`: as caixas ligadas passam a criar card nesse funil. Sem ele, ficam ligadas a este.
  # - `new_default_pipeline_id`: esse funil vira o principal antes da regra do único principal.
  def destroy
    # Funil já arquivado: só serve para levar os abertos que ficaram presos nele (move_to_stage_id). Sem isso (segundo
    # clique, outra aba), não há o que fazer: 422, em vez de repetir caixas, principal ou "Guardar junto".
    return render_unprocessable(ARCHIVE_ALREADY_ARCHIVED) if @pipeline.archived? && params[:move_to_stage_id].blank?

    @archiver = build_archiver
    assign_archive_result(@archiver.perform)
    render :show
  rescue ::Crm::Pipelines::Archiver::InvalidTarget => e
    render json: { error: e.message, moved_count: archive_moved_before_failure }, status: :unprocessable_entity
  rescue ::Crm::Pipelines::Archiver::Blocked => e
    @archive_blocked = e.motivo
    render_archive_blocked
  end

  # Restaurar o funil arquivado: ele volta ao seletor do Kanban com os cards abertos que ficaram nele.
  def restore
    return render_unprocessable(RESTORE_NOT_ARCHIVED) unless @pipeline.archived?

    @pipeline.active!
    @open_cards_count = @pipeline.cards.open.count
    render :show
  end

  # O que a tela mostra antes de arquivar: quantos cards abertos ficam, quais caixas criam card neste funil e, se os
  # cards ficarem no funil, quantos retornos param e quantas reuniões continuam marcadas.
  def archive_preview
    render json: {
      payload: { open_cards_count: @pipeline.cards.open.count, inboxes: linked_inboxes }
        .merge(::Crm::Pipelines::RetornosDosGuardados.new(@pipeline).contagem)
    }
  end

  private

  def fetch_pipeline_to_archive
    fetch_pipeline
  end

  def build_archiver
    ::Crm::Pipelines::Archiver.new(
      pipeline: @pipeline, actor: Current.user, target_stage: archive_target_stage,
      inboxes_target: other_active_pipeline(params[:inboxes_to_pipeline_id], ::Crm::Pipelines::Archiver::INVALID_INBOXES_TARGET),
      new_default: other_active_pipeline(params[:new_default_pipeline_id], ::Crm::Pipelines::Archiver::INVALID_DEFAULT),
      stop_follow_ups: ActiveModel::Type::Boolean.new.cast(params[:stop_follow_ups]) == true
    )
  end

  # Os nomes do resumo (#2145) só dos clientes cujo card movido a pessoa vê no CRM: quem gerencia funis com acesso
  # restrito (funções personalizadas, caixa ou "só as suas") não recebe nome de cliente que não enxerga. O total
  # (`@clients_with_two_open_count`) continua de todos. Administrador vê todos.
  def visible_clients_with_two_open(clientes)
    return [] if clientes.empty?

    visiveis = ::Crm::Cards::VisibleScopeQuery.new(
      scope: Current.account.crm_cards.where(id: clientes.pluck(:card_id)), account: Current.account,
      user: Current.user, account_user: Current.account_user
    ).perform.pluck(:id).to_set
    clientes.select { |cliente| visiveis.include?(cliente[:card_id]) }.first(20)
  end

  # Recusa depois de lotes já confirmados (#2145): quantos cards já foram levados ao destino, para a tela dizer.
  def archive_moved_before_failure
    @archiver&.moved_before_failure.to_i
  end

  def assign_archive_result(result)
    @moved_cards_count = result.moved.size
    @stopped_follow_ups_count = result.stopped_follow_ups
    @moved_inboxes = result.moved_inboxes
    @inboxes_target_pipeline_id = result.inboxes_target_pipeline_id
    clientes = result.clientes_com_dois_abertos
    @clients_with_two_open_count = clientes&.size
    @clients_with_two_open = clientes && visible_clients_with_two_open(clientes)
    @open_cards_count = @pipeline.cards.open.count
  end

  # A etapa para onde vão os cards abertos ao arquivar: de outro funil ativo que a pessoa enxerga. Id que não serve é
  # recusado, nunca ignorado: arquivar sem mover não pode acontecer por engano.
  def archive_target_stage
    stage_id = params[:move_to_stage_id].presence
    return if stage_id.nil?

    stage = Current.account.crm_pipeline_stages.where(pipeline_id: other_active_pipelines.select(:id)).find_by(id: stage_id)
    raise ::Crm::Pipelines::Archiver::InvalidTarget, ::Crm::Pipelines::Archiver::INVALID_TARGET if stage.nil?

    stage
  end

  # O funil do parâmetro, entre os outros funis ativos que a pessoa enxerga; id que não serve é recusado com `code`. Lido
  # como params[...] no destroy para o Guia da Plataforma reconhecer o parâmetro.
  def other_active_pipeline(pipeline_id, code)
    return if pipeline_id.blank?

    other_active_pipelines.find_by(id: pipeline_id) || raise(::Crm::Pipelines::Archiver::InvalidTarget, code)
  end

  def other_active_pipelines
    policy_scope(::Crm::Pipeline).active.where.not(id: @pipeline.id)
  end

  # Funis arquivados (index com `status=archived`): quantos cards abertos voltam ao quadro com cada um, quantos cards
  # cada um tem ao todo e as caixas que criam card nele. As contagens são só dos cards que a pessoa vê; as caixas, só
  # para quem gerencia o funil (quem só vê o CRM não precisa dos nomes das caixas para ler a lista).
  def archived_pipeline_counts(pipelines)
    cards = policy_scope(::Crm::Card).where(pipeline_id: pipelines.select(:id))
    @open_cards_counts = cards.open.group(:pipeline_id).count
    @cards_counts = cards.group(:pipeline_id).count
    @auto_create_inboxes = auto_create_inboxes(pipelines.select { |pipeline| policy(pipeline).update? }.map(&:id))
  end

  def auto_create_inboxes(pipeline_ids)
    Current.account.crm_pipeline_inboxes.where(pipeline_id: pipeline_ids, auto_create_card: true)
           .where.not(inbox_id: nil).includes(:inbox).order(:id)
           .group_by(&:pipeline_id)
           .transform_values { |links| links.map { |link| { id: link.inbox_id, name: link.inbox&.name } } }
  end

  # As caixas ligadas ao funil; `auto_create_card` diz se a caixa cria card nele sozinha. `other_pipelines`: os outros
  # funis ativos em que a mesma caixa também cria card (Crm::Conversations::CardSyncer só usa funil ativo, então, com
  # este arquivado e as caixas deixadas aqui, o cliente novo vira card no primeiro deles; sem nenhum, em nenhum).
  def linked_inboxes
    links = @pipeline.pipeline_inboxes.includes(:inbox).where.not(inbox_id: nil).order(:id).to_a
    others = other_auto_create_pipelines(links.map(&:inbox_id))
    links.map do |link|
      { id: link.inbox_id, name: link.inbox&.name, auto_create_card: link.auto_create_card, other_pipelines: others.fetch(link.inbox_id, []) }
    end
  end

  def other_auto_create_pipelines(inbox_ids)
    Current.account.crm_pipeline_inboxes.joins(:pipeline).merge(::Crm::Pipeline.active)
           .where(inbox_id: inbox_ids, auto_create_card: true).where.not(pipeline_id: @pipeline.id)
           .order('crm_pipelines.position ASC, crm_pipeline_inboxes.id ASC')
           .pluck(:inbox_id, 'crm_pipelines.id', 'crm_pipelines.name')
           .group_by(&:first).transform_values { |rows| rows.map { |_, id, name| { id: id, name: name } } }
  end
end
