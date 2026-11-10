# #1920: casos recentes do próprio funil em que a IA de etapa errou ou ficou em dúvida sobre UMA etapa, para a IA que
# escreve a frase achar a fronteira que a frase atual deixa aberta. Os sinais saem do que já está gravado, nunca do texto:
# - levou_e_pessoa_tirou: a IA moveu o card para esta etapa e uma pessoa o tirou dela em até CORRECAO;
# - pessoa_trouxe: uma pessoa pôs o card nesta etapa e, em até CORRECAO antes, a IA tinha escolhido outra;
# - sugeriu_e_pessoa_recusou: a IA sugeriu esta etapa e uma pessoa recusou a sugestão;
# - ficou_em_duvida: a IA pensou nesta etapa sem confiança para mover sozinha e ninguém confirmou.
# Nos dois primeiros, o movimento da pessoa só conta como correção (#correcao?) quando ela levou o card para trás da
# etapa da IA, devolveu o card à etapa de onde a IA o tirou, ou mexeu sem nenhuma mensagem nova depois da decisão da IA.
# Avançar o card depois de um fato novo (o cliente fechou) é o fluxo normal do negócio, não erro da IA.
# Um caso por card, os mais fortes primeiro, só de cards que ensinam e que quem pediu pode ver (Crm::Ai::EscolhaDePessoa),
# e o trecho da conversa até a decisão (Crm::Ai::TrechoDaConversa).
class Crm::Ai::EvidenciaDaEtapa
  JANELA = 60.days
  MAX_CASOS = 6
  MAX_MOTIVO = 300
  # Depois disso, tirar o card da etapa é o caminho normal do negócio, não correção da IA.
  CORRECAO = 24.hours

  # cards: os cards que quem pediu pode ver (Crm::CardPolicy::Scope); sem ele, os da conta.
  def initialize(stage:, cards: nil)
    @stage = stage
    @account_id = stage.account_id
    @cards = cards || Crm::Card.where(account_id: @account_id)
  end

  def casos
    vistos = Set.new
    candidatos.each_with_object([]) do |candidato, casos|
      break casos if casos.size >= MAX_CASOS
      next unless vistos.add?(candidato[:card].id)

      mensagens = Crm::Ai::TrechoDaConversa.de(candidato[:card], ate: candidato[:ate])
      casos << candidato.except(:card, :ate).merge(messages: mensagens).compact if mensagens.any?
    end
  end

  private

  def candidatos
    levou_e_pessoa_tirou + pessoa_trouxe + sugestoes('sugeriu_e_pessoa_recusou', :dismissed) + ficou_em_duvida
  end

  def sugestoes_da_etapa
    sugestoes_que_ensinam.where(to_stage_id: @stage.id).includes(:card).order(created_at: :desc)
  end

  def sugestoes_que_ensinam
    escopo = Crm::AiStageSuggestion.where(account_id: @account_id, created_at: JANELA.ago.., card_id: @cards.select(:id))
    Crm::Ai::EscolhaDePessoa.ensinam(escopo)
  end

  def movimentos_de_pessoa
    Crm::Ai::EscolhaDePessoa.ensinam(Crm::Ai::EscolhaDePessoa.movimentos(@account_id, desde: JANELA.ago).where(card_id: @cards.select(:id)))
  end

  def levou_e_pessoa_tirou
    sugestoes_da_etapa.where(status: :auto_applied).limit(MAX_CASOS * 2).filter_map do |sugestao|
      tirou = movimentos_de_pessoa.where(card_id: sugestao.card_id, created_at: sugestao.created_at..(sugestao.created_at + CORRECAO))
                                  .where('payload @> ?', { from_stage_id: @stage.id }.to_json).order(:created_at).first
      next if tirou.blank? || !correcao?(sugestao, tirou)

      caso('levou_e_pessoa_tirou', sugestao, ate: tirou.created_at, pessoa: etapa(tirou.payload['to_stage_id'])&.name)
    end
  end

  def pessoa_trouxe
    movimentos_de_pessoa.where('payload @> ?', { to_stage_id: @stage.id }.to_json).includes(:card)
                        .order(created_at: :desc).limit(MAX_CASOS * 2).filter_map do |movimento|
      antes = ultima_sugestao_antes(movimento)
      next if antes.blank? || antes.to_stage_id == @stage.id || !correcao?(antes, movimento)

      caso('pessoa_trouxe', antes, ate: movimento.created_at, pessoa: @stage.name, card: movimento.card)
    end
  end

  def ultima_sugestao_antes(movimento)
    janela = (movimento.created_at - CORRECAO)..movimento.created_at
    sugestoes_que_ensinam.where(card_id: movimento.card_id, created_at: janela).order(created_at: :desc).first
  end

  # A pessoa corrigiu a IA (não só seguiu o fluxo): voltou o card para trás da etapa da IA ou para a etapa de onde a IA o
  # tirou, ou mexeu sem nenhuma mensagem nova desde a decisão da IA. Etapa de outro funil é troca de funil, não de etapa.
  def correcao?(sugestao, movimento)
    da_pessoa = etapa(movimento.payload['to_stage_id'])
    da_ia = etapa(sugestao.to_stage_id)
    return false if da_pessoa.blank? || da_ia.blank? || da_pessoa.pipeline_id != @stage.pipeline_id

    da_pessoa.position < da_ia.position || da_pessoa.id == sugestao.from_stage_id ||
      !mensagem_nova?(sugestao.card, sugestao.created_at, movimento.created_at)
  end

  def mensagem_nova?(card, desde, ate)
    conversas = [card.conversation_id, *card.card_conversations.pluck(:conversation_id)].compact
    Message.where(account_id: @account_id, conversation_id: conversas, private: false, created_at: desde..ate)
           .where.not(message_type: :activity).exists?
  end

  def sugestoes(sinal, status)
    sugestoes_da_etapa.where(status: status).limit(MAX_CASOS).map { |sugestao| caso(sinal, sugestao, ate: sugestao.updated_at) }
  end

  def ficou_em_duvida
    sugestoes_da_etapa.where(status: %i[pending expired], confidence: ...Crm::Ai::Config::AUTO_MOVE_THRESHOLD).limit(MAX_CASOS)
                      .map { |sugestao| caso('ficou_em_duvida', sugestao, ate: sugestao.created_at) }
  end

  def caso(sinal, sugestao, ate:, pessoa: nil, card: sugestao.card)
    { card: card, ate: ate, signal: sinal, ai_chose: etapa(sugestao.to_stage_id)&.name, ai_confidence: sugestao.confidence.to_f.round(2),
      ai_reasoning: sugestao.reasoning.to_s.truncate(MAX_MOTIVO).presence, person_chose: pessoa }
  end

  def etapa(id)
    @etapas ||= Crm::PipelineStage.where(account_id: @account_id).index_by(&:id)
    @etapas[id.to_i]
  end
end
