# #1920: "raio-x" das frases das etapas antes de salvar. Roda a IA de etapa de verdade (o mesmo classificador, modelo e
# esforço da avaliação de card) nos cards em que uma PESSOA escolheu a etapa há pouco, uma vez com as frases salvas e
# outra com as frases da tela, e conta quantas vezes cada uma chega à etapa que a pessoa escolheu.
#
# Não muda nada: não move card, não grava sugestão, campo nem metadado. O classificador só lê e devolve; quem aplica é o
# Crm::Ai::Evaluator, que não roda aqui. Cada caso é visto como estava na hora da decisão: o card na etapa de onde a
# pessoa o tirou e a conversa só até aquele instante. Com o mesmo texto nas duas versões, roda uma vez só.
#
# Custo: duas chamadas por card (uma quando nada mudou), cada uma registrada pelo ResponsesClient (feature
# raio_x_etapa). Para no teto de cards (MAX_CARDS) ou de custo (TETO_USD), o que vier primeiro, e diz se parou no teto.
class Crm::Ai::RaioXDasFrases
  JANELA = 30.days
  MAX_CARDS = 12
  TETO_USD = 0.10
  FEATURE = 'raio_x_etapa'.freeze
  SEM_ATRIBUTOS = { contact: [], conversation: [], card: [] }.freeze
  # O que o classificador lê de uma etapa (StageClassifier#stage_payload): id, nome e metadata['ai_criteria'].
  Etapa = Struct.new(:id, :name, :metadata)

  def initialize(pipeline:, stages:)
    @pipeline = pipeline
    @stages = stages.map { |stage| stage.to_h.stringify_keys }
  end

  def perform
    salvas = @pipeline.stages.order(:position, :id).to_a
    return { error: 'stages_changed' } unless salvas.size == @stages.size
    return { error: 'credentials_missing' } unless credencial

    @atuais = salvas.map { |etapa| Etapa.new(etapa.id, etapa.name, etapa.metadata) }
    @novas = salvas.each_with_index.map { |etapa, index| etapa_da_tela(etapa, @stages[index]) }
    resultado
  end

  private

  def resultado
    @custo = 0.0
    casos = []
    referencias.each do |movimento|
      break if @custo >= TETO_USD

      casos << avaliar(movimento)
    end
    resumo(casos)
  end

  def resumo(casos)
    { total: casos.size, acertos_atual: casos.count { |caso| caso[:atual] == caso[:certa] },
      acertos_nova: casos.count { |caso| caso[:nova] == caso[:certa] }, custo_usd: @custo.round(4),
      parou_no_teto: casos.size < referencias.size, casos: casos.map { |caso| nomes(caso) } }
  end

  def nomes(caso)
    nome = ->(id) { @novas.find { |etapa| etapa.id == id }&.name }
    { card_id: caso[:card_id], certa: nome.call(caso[:certa]), atual: nome.call(caso[:atual]), nova: nome.call(caso[:nova]) }
  end

  def etapa_da_tela(etapa, tela)
    criterio = tela['description'].to_s.strip
    Etapa.new(etapa.id, tela['name'].to_s.strip.presence || etapa.name, (etapa.metadata || {}).merge('ai_criteria' => criterio))
  end

  # O último movimento feito por uma pessoa dentro deste funil, em cada card que continua na etapa que ela escolheu.
  def referencias
    @referencias ||= Crm::Activity.where(account_id: @pipeline.account_id, event_type: 'move', actor_type: 'user', created_at: JANELA.ago..)
                                  .where('payload @> ?', { from_pipeline_id: @pipeline.id, to_pipeline_id: @pipeline.id }.to_json)
                                  .includes(:card).order(created_at: :desc).limit(MAX_CARDS * 10).to_a
                                  .uniq(&:card_id)
                                  .select { |movimento| ainda_na_escolha?(movimento) }
                                  .first(MAX_CARDS)
  end

  def ainda_na_escolha?(movimento)
    card = movimento.card
    card.present? && card.pipeline_id == @pipeline.id && card.stage_id == movimento.payload['to_stage_id'] &&
      @pipeline.stages.exists?(id: movimento.payload['from_stage_id'])
  end

  def avaliar(movimento)
    contexto = contexto_da_decisao(movimento)
    atual = classificar(movimento.card, @atuais, contexto)
    nova = mudou? ? classificar(movimento.card, @novas, contexto) : atual
    { card_id: movimento.card_id, certa: movimento.payload['to_stage_id'], atual: atual, nova: nova }
  end

  def contexto_da_decisao(movimento)
    origem = @atuais.find { |etapa| etapa.id == movimento.payload['from_stage_id'] }
    Crm::Ai::ContextBuilder.new(card: movimento.card, ate: movimento.created_at).perform.merge(current_stage: { id: origem.id, name: origem.name })
  end

  def classificar(card, etapas, contexto)
    resposta = Crm::Ai::StageClassifier.new(
      card: card, client: cliente, stages: etapas, context: contexto, model: Crm::Ai::Config::MODEL_CLASSIFY,
      reasoning_effort: Crm::Ai::Config::CLASSIFY_REASONING_EFFORT, attribute_schema: SEM_ATRIBUTOS
    ).perform
    @custo += Crm::Ai::UsageRecorder.cost_for(resposta[:model_used], Crm::Ai::UsageRecorder.extract_tokens(resposta[:usage]))
    resposta[:suggested_stage_id].to_i
  end

  def mudou?
    @atuais.map { |etapa| [etapa.name, Crm::Ai::Config.stage_ai_criteria(etapa)] } !=
      @novas.map { |etapa| [etapa.name, Crm::Ai::Config.stage_ai_criteria(etapa)] }
  end

  def credencial
    @credencial ||= Crm::Ai::CredentialResolver.new(account: @pipeline.account).resolve
  end

  def cliente
    @cliente ||= Crm::Ai::ResponsesClient.new(credential: credencial, feature: FEATURE, account: @pipeline.account, pipeline: @pipeline)
  end
end
