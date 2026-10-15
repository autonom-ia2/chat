# #1638: o card que a IA criou ou nomeou em cima do aviso "mensagem não suportada", numa decisão reaberta pelo WhatsApp
# Híbrido. O assunto do texto real vai para ele, nunca para um segundo card: no mesmo funil ganha o nome novo; em outro
# funil, vai para a 1ª etapa dele (Crm::Cards::Mover, com o CardGuard) e ganha o nome. Quem chama está no lock da conversa.
#
# Card em que uma pessoa mexeu depois da IA (nome, etapa ou dono) é dela: não é tocado, e nada novo nasce no lugar.
#
# Decidido no #1638: a IA move como sistema (sem pessoa), como as automações de etapa e o card que ela já cria em
# qualquer funil; o CardGuard sem pessoa não barra. O card movido não roda as automações da 1ª etapa (o card que a IA
# cria também não). Com a caixa em Sugerir, a troca de funil não vira sugestão: o card fica e só o log registra.
# Aceito: mexida de pessoa nos milissegundos entre aplicar e gravar a decisão anterior não é vista (a referência é o
# horário da decisão).
class Crm::Subjects::CardDoAviso
  ACOES_DA_IA = %w[create rename].freeze
  # O que uma pessoa faz no card e fica na linha do tempo dele: nome e dono (update), etapa e funil (move).
  MEXIDAS = %w[update move].freeze

  def self.de(account:, anterior:)
    return unless anterior.present? && ACOES_DA_IA.include?(anterior['action'])

    card = account.crm_cards.find_by(id: anterior['card_id'])
    new(card, anterior) if card&.open?
  end

  attr_reader :card

  def initialize(card, anterior)
    @card = card
    @anterior = anterior
  end

  def recarregar
    @card.reload
    self
  end

  def pessoa_mexeu?
    @card.title != @anterior['title'] ||
      Crm::Activity.exists?(card_id: @card.id, actor_type: 'user', event_type: MEXIDAS, created_at: @anterior['updated_at']..)
  end

  # A IA (sem pessoa) pode levar o card a este funil? A mesma regra do /move e das automações.
  def pode_ir_para?(pipeline)
    @card.pipeline_id == pipeline.id ||
      Crm::Access::CardGuard.new(user: nil, account: @card.account).move_allowed?(@card, pipeline.id)
  end

  def mesmo_assunto?(pipeline, titulo)
    @card.pipeline_id == pipeline.id && @card.title == titulo
  end

  def mover_para(pipeline)
    return if @card.pipeline_id == pipeline.id

    etapa = pipeline.stages.order(:position, :id).first
    Crm::Cards::Mover.new(card: @card, actor: nil, target_stage: etapa,
                          automation_context: { source: 'crm_subjects', skip_automations: true }).perform
  end
end
