# "Avisar a Meta sobre o seu funil" (#1047, CA-1.8): o passo 4 da conexão guiada.
#
# Lê os funis de venda ativos ligados a um WhatsApp oficial da conta (os números que recebem os cliques dos anúncios),
# mostra o que falta em cada um e grava, por aqui, o mesmo que Editar funil grava:
# - em cada etapa, `metadata['funnel_stage_type']` ("Como a Meta entende esta etapa");
# - no funil, `metadata['meta_sync']`: envio ligado, venda e mudança de etapa ligadas.
# A perda e o dataset continuam como o funil já tinha. O Pixel da conexão só entra no funil que não tem um.
class Crm::MetaAds::Funnels
  STAGE_TYPES = %w[lead qualified opportunity negotiation].freeze
  NO_TYPE = 'none'.freeze

  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  def initialize(account, connection)
    @account = account
    @connection = connection
  end

  def payload
    {
      funnels: pipelines.map { |pipeline| funnel_payload(pipeline) },
      unlinked_numbers: unlinked_inboxes.map { |inbox| { inbox_id: inbox.id, name: inbox.name } },
      ai_available: Crm::Ai::Config.enabled? && Crm::Ai::CredentialResolver.new(account: @account).configured?
    }
  end

  # Venda avisada em ao menos um funil ligado ao WhatsApp oficial: o passo 4 conta como feito.
  def sales_enabled?
    pipelines.any? { |pipeline| sync(pipeline)['enabled'] == true && sync(pipeline).dig('events', 'won') == true }
  end

  def find!(pipeline_id)
    pipelines.find { |pipeline| pipeline.id == pipeline_id.to_i } || raise(Error, 'funnel_not_found')
  end

  # stage_types: { stage_id => 'lead' | ... | 'none' }. Etapas fora do mapa ficam como estão.
  def apply!(pipeline, stage_types)
    types = normalize(pipeline, stage_types)
    Crm::Pipeline.transaction do
      pipeline.stages.each { |stage| write_stage_type(stage, types[stage.id]) if types.key?(stage.id) }
      write_sync(pipeline, enable_sync(sync(pipeline)))
    end
  end

  # Para de avisar a Meta neste funil. As escolhas das etapas e dos eventos ficam guardadas para religar.
  def disable!(pipeline)
    write_sync(pipeline, sync(pipeline).merge('enabled' => false))
  end

  private

  def meta_inboxes
    @meta_inboxes ||= @account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:id).to_a
  end

  def pipelines
    @pipelines ||= Crm::Pipeline.active.where(account_id: @account.id, counts_as_sale: true)
                                .joins(:pipeline_inboxes).where(crm_pipeline_inboxes: { inbox_id: meta_inboxes.map(&:id) })
                                .distinct.order(:position).includes(:stages, :inboxes).to_a
  end

  def unlinked_inboxes
    linked = Crm::PipelineInbox.joins(:pipeline).where(crm_pipelines: { account_id: @account.id, status: :active })
                               .pluck(:inbox_id)
    meta_inboxes.reject { |inbox| linked.include?(inbox.id) }
  end

  def funnel_payload(pipeline)
    stages = pipeline.stages.sort_by(&:position)
    {
      id: pipeline.id,
      name: pipeline.name,
      numbers: pipeline.inboxes.select { |inbox| meta_inboxes.include?(inbox) }.map { |inbox| { inbox_id: inbox.id, name: inbox.name } },
      enabled: sync(pipeline)['enabled'] == true,
      events: sync(pipeline)['events'].to_h.slice('won', 'lost', 'moved'),
      stages: stages.map { |stage| stage_payload(stage) },
      missing: missing(pipeline, stages)
    }
  end

  def stage_payload(stage)
    {
      id: stage.id, name: stage.name, description: Crm::Ai::Config.stage_ai_criteria(stage),
      funnel_stage_type: stage.metadata.to_h['funnel_stage_type'].presence,
      result: result_stage?(stage)
    }
  end

  def missing(pipeline, stages)
    config = sync(pipeline)
    codes = []
    codes << 'sending_off' unless config['enabled'] == true
    codes << 'sales_off' unless config.dig('events', 'won') == true
    codes << 'moves_off' unless config.dig('events', 'moved') == true
    codes << 'stages' if stages.reject { |stage| result_stage?(stage) }.none? { |stage| stage.metadata.to_h['funnel_stage_type'].present? }
    codes
  end

  # Etapa de resultado (ganho/perda) vira Purchase/OrderCanceled pelo fechamento do card, não por tipo.
  def result_stage?(stage)
    stage.is_won_stage || stage.is_lost_stage
  end

  def normalize(pipeline, stage_types)
    stage_ids = pipeline.stages.map(&:id)
    stage_types.to_h.each_with_object({}) do |(id, type), result|
      raise Error, 'invalid_stage' unless stage_ids.include?(id.to_i)
      raise Error, 'invalid_stage_type' unless type == NO_TYPE || STAGE_TYPES.include?(type)

      result[id.to_i] = type
    end
  end

  def write_stage_type(stage, type)
    metadata = stage.metadata.to_h.deep_dup
    if type == NO_TYPE
      metadata.delete('funnel_stage_type')
    else
      metadata['funnel_stage_type'] = type
    end
    stage.update!(metadata: metadata)
  end

  def enable_sync(config)
    events = { 'lost' => false }.merge(config['events'].to_h, 'won' => true, 'moved' => true)
    result = config.merge('enabled' => true, 'events' => events)
    result['pixel_id'] = @connection.pixel_id if config['pixel_id'].blank? && @connection&.pixel_id.present?
    result
  end

  def sync(pipeline)
    pipeline.metadata.to_h['meta_sync'].to_h
  end

  def write_sync(pipeline, config)
    pipeline.update!(metadata: pipeline.metadata.to_h.merge('meta_sync' => config))
  end
end
