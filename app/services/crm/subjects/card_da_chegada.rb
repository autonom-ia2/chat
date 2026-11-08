# C36 (#1711): o card que a caixa criou na chegada da conversa (CardSyncer, "assim que chega"), ainda sem nome, que a IA de
# assunto pode levar ao funil do pedido em vez de deixar para trás e criar outro. Ver Crm::Subjects::Applier#chegada_para.
#
# Só com a flag `crm_avaliar_toda_mensagem` e a caixa em Automática. O card precisa ser desta conversa, criado pelo
# sistema na chegada (metadata crm_auto_sync), estar aberto e sem nome, nunca ter mudado de etapa e não ter mexida de
# pessoa (nome ou dono). A IA move como sistema, com a mesma regra do /move e das automações (CardGuard sem pessoa), e
# sem rodar as automações da 1ª etapa, como no #1638 (Crm::Subjects::CardDoAviso).
class Crm::Subjects::CardDaChegada
  MEXIDAS_DE_PESSOA = %w[update move].freeze

  def self.de(conversation:, card:, mode:, pipeline:)
    return unless mode == 'auto' && card.present? && card.pipeline_id != pipeline.id
    return unless Crm::Conversations::CardEmFoco.ligada?(conversation.account)

    chegada = new(card, conversation)
    chegada if chegada.adotavel?(pipeline)
  end

  # #1910: o card da chegada no mesmo funil do pedido, que a IA de assunto pode levar à etapa escolhida. Só as guardas do
  # card intocado: sem troca de funil (o acesso e o dono já são daquele funil) e sem depender de `crm_avaliar_toda_mensagem`,
  # que é a flag da troca de funil; quem liga isto é `crm_assunto_na_etapa`. O modo da caixa quem confere é o Applier.
  def self.no_funil(conversation:, card:)
    chegada = new(card, conversation)
    chegada if chegada.intocado?
  end

  # O card da chegada ainda intocado, na Automática (o único modo em que ele é adotado): nem "nenhum assunto" (#1918 PR1)
  # nem "o mesmo assunto" (#1918 PR2) o tocam. Movido pela IA de etapa num "oi", ele deixaria de ser adotado pelo
  # primeiro pedido de outro funil, e um card vazio sobraria para trás.
  def self.intacta?(conversation:, card:, mode:)
    mode == 'auto' && card.present? && new(card, conversation).intocado?
  end

  attr_reader :card

  def initialize(card, conversation)
    @card = card
    @conversation = conversation
  end

  def recarregar
    @card.reload
    self
  end

  def adotavel?(pipeline)
    intocado? && pode_ir_para?(pipeline) && dono_pode?(pipeline)
  end

  # Aberto, desta conversa, criado pelo sistema na chegada, sem nome, nunca mudou de etapa e sem mexida de pessoa.
  def intocado?
    @card.open? && @card.conversation_id == @conversation.id && criado_na_chegada? &&
      !Crm::Subjects::Naming.named?(@card) && !mexido?
  end

  # etapa: a coluna escolhida pela IA de assunto (#1910); sem ela, a 1ª etapa. Sem as automações: quem chama roda as de
  # entrada da etapa escolhida (Crm::Subjects::Etapa.entrar).
  def mover_para(pipeline, etapa = nil)
    etapa ||= Crm::Subjects::Etapa.primeira(pipeline)
    Crm::Cards::Mover.new(card: @card, actor: nil, target_stage: etapa,
                          automation_context: { source: 'crm_subjects', skip_automations: true }).perform
  end

  private

  def criado_na_chegada?
    @card.metadata.to_h.dig(Crm::Conversations::CardSyncer::AUTO_SYNC_METADATA, 'source') ==
      Crm::Conversations::CardSyncer::OBSERVER_SOURCE
  end

  # Mudou de etapa (por qualquer um, inclusive a IA de movimentação) ou uma pessoa mexeu no nome ou no dono: o card já
  # é de um assunto daquele funil, ou é de alguém.
  def mexido?
    atividades = Crm::Activity.where(card_id: @card.id)
    atividades.exists?(event_type: 'move') || atividades.exists?(actor_type: 'user', event_type: MEXIDAS_DE_PESSOA)
  end

  def pode_ir_para?(pipeline)
    Crm::Access::CardGuard.new(user: nil, account: @card.account).move_allowed?(@card, pipeline.id)
  end

  # O dono do card (o atendente da conversa) precisa ter o funil novo naquela caixa, senão o card sumiria da tela dele
  # (#1148), a mesma regra de quem vira dono (CardGuard#owner_allowed?).
  def dono_pode?(pipeline)
    Crm::Access::CardGuard.new(user: nil, account: @card.account)
                          .owner_allowed?(@card.owner_id, inbox_id: @card.inbox_id, pipeline_id: pipeline.id)
  end
end
