# IA entende a conversa F3 — a pessoa aceitou a sugestão de fechar (Crm::Ai::SuggestionApplier): o mesmo fechamento da
# IA (etapa de fim, motivo, lembrete de retorno do "adiou"), com ela como autora e sem as guardas da IA (quem decide é
# ela). O "era teste" (Crm::Ai::NaoENegocio) arquiva, como uma pessoa arquiva. Fechado assim não conta em
# Crm::Ai::FecharCard.fechados_pela_ia. Com o card já fechado, ou a sugestão já respondida, nada muda e ela expira.
class Crm::Ai::FecharCard::Aceite < Crm::Ai::FecharCard
  def initialize(sugestao, ator)
    @sugestao = sugestao
    @ator = ator
    super(card: sugestao.card, decisao: sugestao.fechar.to_h.merge(pedido_de_retorno: sugestao.metadata.to_h['pedido_de_retorno']),
          lido_em: nil)
  end

  # true quando o card fechou.
  def perform
    fechado = aceitavel? && @card.with_lock { @card.open? && sugestao.reload.pending? && fechar_ou_arquivar! }
    return expirar! unless fechado

    self.class.agendar_retorno(@card, @decisao, @decisao[:pedido_de_retorno])
    Crm::Cards::Broadcaster.broadcast(@card, arquivar? ? Events::Types::CRM_CARD_ARCHIVED : Events::Types::CRM_CARD_UPDATED)
    true
  end

  private

  attr_reader :ator, :sugestao

  def arquivar? = resultado == ARQUIVADO && motivo == Crm::Ai::NaoENegocio::MOTIVO_TESTE

  def aceitavel? = arquivar? || decisao_valida?

  def expirar!
    sugestao.update!(status: :expired) if sugestao.pending?
    false
  end

  def fechar_ou_arquivar!
    arquivar? ? arquivar! : fechar!
    sugestao.update!(status: :accepted)
    true
  end

  # Como uma pessoa arquiva (Api::V1::Accounts::Crm::CardsController#destroy).
  def arquivar!
    @card.update!(status: :archived, last_activity_at: Time.current)
    @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).where.not(id: sugestao.id)
         .find_each { |pendente| pendente.update!(status: :expired) }
    Crm::ActivityLogger.new(card: @card, actor: ator, event_type: 'archive', payload: payload).perform
  end

  # Fechado por uma pessoa: a sugestão que ela aceitou e o motivo, para a linha do tempo (sem `by: 'ai'`).
  def payload
    { sugestao_da_ia: sugestao.id, motivo: (motivo unless resultado == 'resolvido') }.compact
  end
end
