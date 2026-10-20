# #1920: casos recentes do próprio funil em que a IA de etapa errou ou ficou em dúvida sobre UMA etapa, para a IA que
# escreve a frase achar a fronteira que a frase atual deixa aberta. Os sinais saem do que já está gravado, nunca do texto:
# - levou_e_pessoa_tirou: a IA moveu o card para esta etapa e uma pessoa o tirou dela em até CORRECAO;
# - pessoa_trouxe: uma pessoa pôs o card nesta etapa e, em até CORRECAO antes, a IA tinha escolhido outra;
# - sugeriu_e_pessoa_recusou: a IA sugeriu esta etapa e uma pessoa recusou a sugestão;
# - ficou_em_duvida: a IA pensou nesta etapa sem confiança para mover sozinha e ninguém confirmou.
# Um caso por card, os mais fortes primeiro, e o trecho da conversa até a decisão (Crm::Ai::TrechoDaConversa).
class Crm::Ai::EvidenciaDaEtapa
  JANELA = 60.days
  MAX_CASOS = 6
  MAX_MOTIVO = 300
  # Depois disso, tirar o card da etapa é o caminho normal do negócio, não correção da IA.
  CORRECAO = 24.hours

  def initialize(stage:)
    @stage = stage
    @account_id = stage.account_id
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
    Crm::AiStageSuggestion.where(account_id: @account_id, to_stage_id: @stage.id, created_at: JANELA.ago..)
                          .includes(:card).order(created_at: :desc)
  end

  def movimentos_de_pessoa
    Crm::Activity.where(account_id: @account_id, event_type: 'move', actor_type: 'user', created_at: JANELA.ago..)
  end

  def levou_e_pessoa_tirou
    sugestoes_da_etapa.where(status: :auto_applied).limit(MAX_CASOS * 2).filter_map do |sugestao|
      tirou = movimentos_de_pessoa.where(card_id: sugestao.card_id, created_at: sugestao.created_at..(sugestao.created_at + CORRECAO))
                                  .where('payload @> ?', { from_stage_id: @stage.id }.to_json).order(:created_at).first
      next if tirou.blank?

      caso('levou_e_pessoa_tirou', sugestao, ate: tirou.created_at, pessoa: nome_da_etapa(tirou.payload['to_stage_id']))
    end
  end

  def pessoa_trouxe
    movimentos_de_pessoa.where('payload @> ?', { to_stage_id: @stage.id }.to_json).includes(:card)
                        .order(created_at: :desc).limit(MAX_CASOS * 2).filter_map do |movimento|
      janela = (movimento.created_at - CORRECAO)..movimento.created_at
      antes = Crm::AiStageSuggestion.where(account_id: @account_id, card_id: movimento.card_id, created_at: janela)
                                    .order(created_at: :desc).first
      next if antes.blank? || antes.to_stage_id == @stage.id

      caso('pessoa_trouxe', antes, ate: movimento.created_at, pessoa: @stage.name, card: movimento.card)
    end
  end

  def sugestoes(sinal, status)
    sugestoes_da_etapa.where(status: status).limit(MAX_CASOS).map { |sugestao| caso(sinal, sugestao, ate: sugestao.updated_at) }
  end

  def ficou_em_duvida
    sugestoes_da_etapa.where(status: %i[pending expired], confidence: ...Crm::Ai::Config::AUTO_MOVE_THRESHOLD).limit(MAX_CASOS)
                      .map { |sugestao| caso('ficou_em_duvida', sugestao, ate: sugestao.created_at) }
  end

  def caso(sinal, sugestao, ate:, pessoa: nil, card: sugestao.card)
    { card: card, ate: ate, signal: sinal, ai_chose: nome_da_etapa(sugestao.to_stage_id), ai_confidence: sugestao.confidence.to_f.round(2),
      ai_reasoning: sugestao.reasoning.to_s.truncate(MAX_MOTIVO).presence, person_chose: pessoa }
  end

  def nome_da_etapa(id)
    @nomes ||= Crm::PipelineStage.where(account_id: @account_id).pluck(:id, :name).to_h
    @nomes[id.to_i]
  end
end
