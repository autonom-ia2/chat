# #1920: casos recentes em que uma pessoa mudou um card de funil, entrando ou saindo deste. É o sinal de que a escolha
# de funil (a IA de assunto lê o "quando usar") não bateu com o que a pessoa decidiu. Um caso por card, o trecho da
# conversa até a decisão (Crm::Ai::TrechoDaConversa) e o nome do outro funil. Só escolha direta de pessoa
# (Crm::Ai::EscolhaDePessoa) e só cards que quem pediu pode ver.
class Crm::Ai::EvidenciaDoFunil
  JANELA = 60.days
  MAX_CASOS = 6

  # cards: os cards que quem pediu pode ver (Crm::CardPolicy::Scope); sem ele, os da conta.
  def initialize(pipeline:, cards: nil)
    @pipeline = pipeline
    @cards = cards || Crm::Card.where(account_id: pipeline.account_id)
  end

  def casos
    vistos = Set.new
    movimentos.each_with_object([]) do |movimento, casos|
      break casos if casos.size >= MAX_CASOS
      next unless vistos.add?(movimento.card_id)

      mensagens = Crm::Ai::TrechoDaConversa.de(movimento.card, ate: movimento.created_at)
      casos << caso(movimento).merge(messages: mensagens) if mensagens.any?
    end
  end

  private

  def movimentos
    escopo = Crm::Ai::EscolhaDePessoa.movimentos(@pipeline.account_id, desde: JANELA.ago).where(card_id: @cards.select(:id))
    escopo.where('payload @> ? OR payload @> ?', { from_pipeline_id: @pipeline.id }.to_json, { to_pipeline_id: @pipeline.id }.to_json)
          .where("payload->>'from_pipeline_id' IS DISTINCT FROM payload->>'to_pipeline_id'")
          .includes(:card).order(created_at: :desc).limit(MAX_CASOS * 3)
  end

  def caso(movimento)
    saiu = movimento.payload['from_pipeline_id'] == @pipeline.id
    outro = movimento.payload[saiu ? 'to_pipeline_id' : 'from_pipeline_id']
    { signal: saiu ? 'pessoa_tirou_deste_funil' : 'pessoa_trouxe_para_este_funil', other_pipeline: nome_do_funil(outro) }.compact
  end

  def nome_do_funil(id)
    @nomes ||= Crm::Pipeline.where(account_id: @pipeline.account_id).pluck(:id, :name).to_h
    @nomes[id.to_i]
  end
end
