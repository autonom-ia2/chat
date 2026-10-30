# IA entende a conversa F3 — a pessoa aceitou a sugestão de fechar (Crm::Ai::SuggestionApplier): o mesmo fechamento da
# IA (etapa de fim, motivo, lembrete de retorno do "adiou"), com ela como autora. O "era teste" (Crm::Ai::NaoENegocio)
# arquiva, como uma pessoa arquiva. Fechado assim não conta em Crm::Ai::FecharCard.fechados_pela_ia.
#
# Tudo é relido sob a trava do card, antes de fechar: a sugestão ainda pendente no banco (outro aceite pode ter chegado
# antes); o card aberto e no funil em que a sugestão nasceu; o resultado ainda válido nesse funil ("resolvido" num funil
# de venda viraria Ganho, que a IA nunca marca); e nenhuma mensagem do cliente depois da leitura que gerou a sugestão
# (`lido_em` no metadata). Falhou alguma, nada muda e a sugestão expira (a resposta da API é 422).
class Crm::Ai::FecharCard::Aceite < Crm::Ai::FecharCard
  def initialize(sugestao, ator)
    @sugestao = sugestao
    @ator = ator
    super(card: sugestao.card, decisao: sugestao.fechar.to_h.merge(pedido_de_retorno: sugestao.metadata.to_h['pedido_de_retorno']),
          lido_em: self.class.lido_em_gravado(sugestao))
  end

  # true quando o card fechou.
  def perform
    fechado = arquivar? ? arquivar! : @card.with_lock { aceitar? && fechar! }
    return false unless fechado

    self.class.agendar_retorno(@card, @decisao, @decisao[:pedido_de_retorno])
    Crm::Cards::Broadcaster.broadcast(@card, arquivar? ? Events::Types::CRM_CARD_ARCHIVED : Events::Types::CRM_CARD_UPDATED)
    true
  end

  private

  attr_reader :ator, :sugestao

  def arquivar? = resultado == ARQUIVADO && motivo == Crm::Ai::NaoENegocio::MOTIVO_TESTE

  def aceitavel?
    @card.open? && mesmo_funil? && (arquivar? || decisao_valida?) && !mensagem_nova?
  end

  def mesmo_funil? = sugestao.from_stage.pipeline_id == @card.pipeline_id

  def expirar!
    sugestao.update!(status: :expired)
    false
  end

  # Sob a trava do card. A sugestão aceita antes do fechamento: o Crm::Cards::Closer expira as que ainda estiverem pendentes.
  def aceitar?
    return false unless sugestao.reload.pending?
    return expirar! unless aceitavel?

    sugestao.update!(status: :accepted)
  end

  # Como uma pessoa arquiva (Crm::Cards::Archiver), que trava lembretes e card nessa ordem e relê o card antes da
  # guarda. A sugestão aceita já saiu de pendente.
  def arquivar!
    Crm::Cards::Archiver.new(card: @card, actor: ator, payload: payload).perform { aceitar? }
  end

  # Fechado por uma pessoa: a sugestão que ela aceitou e o motivo, para a linha do tempo (sem `by: 'ai'`).
  def payload
    { sugestao_da_ia: sugestao.id, motivo: (motivo unless resultado == 'resolvido') }.compact
  end
end
