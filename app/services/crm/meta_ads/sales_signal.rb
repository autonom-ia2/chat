# "Avisar a Meta quando vender?" (#1047, CA-1.8): uma pergunta só no lugar de Editar funil › Mais ajustes.
#
# Ligado: em todo funil ativo da conta, liga o envio à Meta com o evento de venda (Purchase, com valor) e usa
# o Pixel escolhido na conexão. As outras escolhas do funil (perda, mudança de etapa, dataset) ficam como
# estavam: quem quiser ajustar vai em "avançado". Desligado: desliga o envio em todos os funis ativos.
class Crm::MetaAds::SalesSignal
  def initialize(account, connection)
    @account = account
    @connection = connection
  end

  def enabled?
    pipelines.any? { |pipeline| pipeline.metadata.to_h.dig('meta_sync', 'enabled') == true }
  end

  def update!(enabled)
    Crm::Pipeline.transaction do
      pipelines.each { |pipeline| apply(pipeline, enabled) }
    end
    enabled?
  end

  def payload
    { enabled: enabled?, pipelines: pipelines.size }
  end

  private

  def pipelines
    @pipelines ||= Crm::Pipeline.active.where(account_id: @account.id).order(:position).to_a
  end

  def apply(pipeline, enabled)
    metadata = pipeline.metadata.to_h.deep_dup
    meta_sync = metadata['meta_sync'].to_h
    meta_sync['enabled'] = enabled
    if enabled
      # Venda sempre ligada; perda e mudança de etapa ficam como o funil já tinha (desligadas por padrão).
      meta_sync['events'] = { 'lost' => false, 'moved' => false }.merge(meta_sync['events'].to_h, 'won' => true)
      meta_sync['pixel_id'] = @connection.pixel_id if @connection&.pixel_id.present?
    end
    metadata['meta_sync'] = meta_sync
    pipeline.update!(metadata: metadata)
  end
end
