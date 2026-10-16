# O que as IAs fizeram, lido do banco: por mensagem (decisões de assunto, avaliações de etapa, custo, latência) e no fim
# (cards, etapa, foco, quem atende, retorno marcado, campos). Só leitura.
class Stress::Retrato
  IA_DE_ASSUNTO = %w[assunto assunto_revisao].freeze
  IA_DE_MOVIMENTACAO = %w[avaliacao_card].freeze

  def self.marcas(account)
    { decisao: Crm::SubjectDecision.where(account_id: account.id).maximum(:id).to_i,
      sugestao: Crm::AiStageSuggestion.where(account_id: account.id).maximum(:id).to_i,
      uso: Crm::AiUsageEvent.where(account_id: account.id).maximum(:id).to_i }
  end

  def self.custo(escopo)
    escopo.group(:feature).sum(:cost_estimate).transform_values(&:to_f)
  end

  def initialize(conversa)
    @conversa = conversa
    @mundo = conversa.mundo
    @account = @mundo.account
    @conversation = conversa.conversation
  end

  def turno(mensagens:, desde:, latencia:)
    { mensagens: mensagens.map(&:content),
      assunto: decisoes(desde[:decisao]),
      movimentacao: sugestoes(desde[:sugestao]),
      avaliacoes: Stress::Espiao.ler!.map { |a| a.merge(card: rotulo(Crm::Card.find_by(id: a[:card_id]))) },
      latencia_ia_s: latencia.transform_values { |s| s.round(1) },
      foco: rotulo(Crm::Assunto.funil_atual(@conversation.reload)),
      atendente: atendimento }.merge(uso(desde[:uso]))
  end

  # Custo, chamadas e latência do modelo que o próprio sistema gravou (Crm::AiUsageEvent) desde a marca.
  def uso(desde)
    usos = Crm::AiUsageEvent.where(account_id: @account.id).where('id > ?', desde)
    { custo_por_feature: self.class.custo(usos), chamadas: usos.group(:feature).count,
      latencia_modelo_ms: usos.group(:feature).sum(:latency_ms) }
  end

  def final
    cards = @account.crm_cards.order(:id).to_a
    { cards: cards.map { |card| card_resumo(card) },
      foco: rotulo(Crm::Assunto.funil_atual(@conversation.reload)),
      atendente: atendimento,
      contato_campos: @conversation.contact.reload.custom_attributes,
      custo_por_feature: self.class.custo(Crm::AiUsageEvent.where(account_id: @account.id)) }
  end

  def ref_de(card)
    @conversa.refs.key(card) || @conversa.refs.find { |_ref, c| c.id == card.id }&.first
  end

  private

  def decisoes(desde)
    Crm::SubjectDecision.where(account_id: @account.id).where('id > ?', desde).order(:id).map do |d|
      { estado: d.state, acao: d.action, por: d.decided_by, certeza: d.confidence&.round(2),
        funil: d.pipeline ? @mundo.chave_do_funil(d.pipeline) : nil, card: d.card ? rotulo(d.card) : nil,
        titulo: d.title, motivo: d.reason, tocados: (d.touched_card_ids if d.has_attribute?(:touched_card_ids)) }
    end
  end

  def sugestoes(desde)
    Crm::AiStageSuggestion.where(account_id: @account.id).where('id > ?', desde).order(:id).map do |s|
      { card: rotulo(Crm::Card.find(s.card_id)), de: @mundo.chave_da_etapa(Crm::PipelineStage.find(s.from_stage_id)),
        para: @mundo.chave_da_etapa(Crm::PipelineStage.find(s.to_stage_id)), estado: s.status, certeza: s.confidence.to_f.round(2),
        motivo: s.reasoning }
    end
  end

  def rotulo(card)
    return nil if card.nil?

    { ref: ref_de(card) || "novo_#{card.id}", id: card.id, funil: @mundo.chave_do_funil(card.pipeline), titulo: card.title }
  end

  def card_resumo(card)
    card.reload
    rotulo(card).merge(etapa: @mundo.chave_da_etapa(card.stage), status: card.status, valor_cents: card.value_cents,
                       nomeado: Crm::Subjects::Naming.named?(card),
                       campos: card.custom_attributes, retornos: Crm::FollowUp.where(card_id: card.id).count,
                       ultima_avaliacao: card.metadata.to_h.dig('ai', 'last_evaluated_at'))
  end

  def atendimento
    conversa = @conversation.reload
    marca = Crm::Entrega::Marca.dados(conversa)
    return { estado: 'atribuido', pessoa: pessoa(conversa.assignee) } if conversa.assignee_id.present?
    return { estado: marca['modo'], falha: marca['falha'] } if marca

    { estado: 'ninguem' }
  end

  def pessoa(user)
    @mundo.pessoas.key(user) || user&.id
  end
end
