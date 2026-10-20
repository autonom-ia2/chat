# #1920: "raio-x" das frases das etapas antes de salvar. Roda a IA de etapa de verdade (o mesmo classificador, modelo e
# esforço da avaliação de card) nos cards em que uma PESSOA escolheu a etapa há pouco, uma vez com as frases salvas e
# outra com as frases da tela, e conta quantas vezes cada uma chega à etapa que a pessoa escolheu.
#
# Não muda nada: não move card, não grava sugestão, campo nem metadado. O classificador só lê e devolve; quem aplica é o
# Crm::Ai::Evaluator, que não roda aqui. Cada caso é visto como estava na hora da decisão (Crm::Ai::ContextBuilder com
# `ate`): o card na etapa de onde a pessoa o tirou, a conversa só até aquele instante e nada do que foi gravado depois.
# Só lê cards que provam e que quem pediu pode ver (Crm::Ai::EscolhaDePessoa): nunca um card que já foi evidência do
# "Melhorar com IA". As etapas da tela casam com as salvas pelo id. Com o mesmo texto nas duas versões, roda uma vez só.
#
# Custo: duas chamadas por card (uma quando nada mudou), cada uma registrada pelo ResponsesClient (feature
# raio_x_etapa). Antes de cada chamada confere se o gasto somado mais a maior chamada até ali cabe em TETO_USD; o caso
# que não cabe inteiro sai do placar. Para no teto de cards (MAX_CARDS) ou de custo, e diz se parou no teto de custo.
class Crm::Ai::RaioXDasFrases
  JANELA = 30.days
  MAX_CARDS = 12
  TETO_USD = 0.10
  FEATURE = 'raio_x_etapa'.freeze
  # Um raio-x por funil a cada INTERVALO (nenhum segundo do mesmo funil em fila) e no máximo MAX_POR_HORA por conta.
  INTERVALO = 10.minutes
  MAX_POR_HORA = 6
  VAGA = 'crm:ai:raio_x:'.freeze
  SEM_ATRIBUTOS = { contact: [], conversation: [], card: [] }.freeze
  # O que o classificador lê de uma etapa (StageClassifier#stage_payload): id, nome e metadata['ai_criteria'].
  Etapa = Struct.new(:id, :name, :metadata)

  def self.vaga?(pipeline)
    return false unless Redis::Alfred.set("#{VAGA}funil:#{pipeline.id}", '1', nx: true, ex: INTERVALO.to_i)

    chave = "#{VAGA}conta:#{pipeline.account_id}:#{Time.current.utc.strftime('%Y%m%d%H')}"
    usados = Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, 1.hour.to_i) if usados == 1
    usados <= MAX_POR_HORA
  end

  # cards: os cards que quem pediu pode ver (Crm::CardPolicy::Scope); sem ele, os da conta.
  def initialize(pipeline:, stages:, cards: nil)
    @pipeline = pipeline
    @stages = stages.map { |stage| stage.to_h.stringify_keys }
    @cards = cards || Crm::Card.where(account_id: pipeline.account_id)
  end

  def perform
    salvas = @pipeline.stages.order(:position, :id).index_by(&:id)
    return { error: 'stages_changed' } unless mesmas_etapas?(salvas)
    return { error: 'credentials_missing' } unless credencial

    @atuais = salvas.values.map { |etapa| Etapa.new(etapa.id, etapa.name, etapa.metadata) }
    @novas = @stages.map { |tela| etapa_da_tela(salvas.fetch(tela['id'].to_i), tela) }
    resultado
  end

  private

  # A tela tem que trazer exatamente as etapas salvas, cada uma pelo seu id (a ordem pode ter mudado).
  def mesmas_etapas?(salvas)
    ids = @stages.map { |tela| tela['id'].to_i }
    ids.size == salvas.size && ids.uniq.size == ids.size && ids.all? { |id| salvas.key?(id) }
  end

  def resultado
    @custo = 0.0
    @maior_chamada = 0.0
    casos = []
    referencias.each do |movimento|
      caso = avaliar(movimento)
      break if caso.nil?

      casos << caso
    end
    resumo(casos)
  end

  def resumo(casos)
    { total: casos.size, acertos_atual: casos.count { |caso| caso[:atual] == caso[:certa] },
      acertos_nova: casos.count { |caso| caso[:nova] == caso[:certa] }, custo_usd: @custo.round(4),
      parou_no_teto: @parou_no_teto == true, casos: casos.map { |caso| nomes(caso) } }
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
    movimentos = Crm::Ai::EscolhaDePessoa.movimentos(@pipeline.account_id, desde: JANELA.ago).where(card_id: @cards.select(:id))
    Crm::Ai::EscolhaDePessoa.provam(movimentos)
                            .where('payload @> ?', { from_pipeline_id: @pipeline.id, to_pipeline_id: @pipeline.id }.to_json)
                            .includes(:card).order(created_at: :desc).limit(MAX_CARDS * 10).to_a
                            .uniq(&:card_id)
                            .select { |movimento| ainda_na_escolha?(movimento) }
                            .first(MAX_CARDS)
  end

  def ainda_na_escolha?(movimento)
    card = movimento.card
    card.present? && card.pipeline_id == @pipeline.id && card.stage_id == movimento.payload['to_stage_id'] &&
      @atuais.any? { |etapa| etapa.id == movimento.payload['from_stage_id'] }
  end

  # nil quando o caso não cabe inteiro no teto de custo: um placar com metade do par não compara nada.
  def avaliar(movimento)
    contexto = contexto_da_decisao(movimento)
    atual = classificar(movimento.card, @atuais, contexto)
    return if atual.nil?

    nova = mudou? ? classificar(movimento.card, @novas, contexto) : atual
    return if nova.nil?

    { card_id: movimento.card_id, certa: movimento.payload['to_stage_id'], atual: atual, nova: nova }
  end

  def contexto_da_decisao(movimento)
    origem = @atuais.find { |etapa| etapa.id == movimento.payload['from_stage_id'] }
    Crm::Ai::ContextBuilder.new(card: movimento.card, ate: movimento.created_at).perform.merge(current_stage: { id: origem.id, name: origem.name })
  end

  def classificar(card, etapas, contexto)
    return unless cabe_mais_uma?

    resposta = Crm::Ai::StageClassifier.new(
      card: card, client: cliente, stages: etapas, context: contexto, model: Crm::Ai::Config::MODEL_CLASSIFY,
      reasoning_effort: Crm::Ai::Config::CLASSIFY_REASONING_EFFORT, attribute_schema: SEM_ATRIBUTOS
    ).perform
    registrar_custo(resposta)
    resposta[:suggested_stage_id].to_i
  end

  # A próxima chamada é estimada pela mais cara até aqui; a primeira sempre roda.
  def cabe_mais_uma?
    return true if @custo + @maior_chamada <= TETO_USD

    @parou_no_teto = true
    false
  end

  def registrar_custo(resposta)
    custo = Crm::Ai::UsageRecorder.cost_for(resposta[:model_used], Crm::Ai::UsageRecorder.extract_tokens(resposta[:usage]))
    @custo += custo
    @maior_chamada = [@maior_chamada, custo].max
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
