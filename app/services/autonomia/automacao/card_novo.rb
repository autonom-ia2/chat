# O card que uma automação cria numa etapa (#2414 F1.4 e G4), num lugar só: o "mover" das Regras (CardNaEtapa) e o
# passo "criar card" da Automação livre (PassoDeCard) criam por aqui.
#
# - Trava a conversa (ou o contato, quando não há conversa) e confere de novo dentro da trava, pelo bloco de quem
#   chama: duas automações juntas não criam dois cards. O bloco responde "já tem card" na regra de cada um.
# - Com conversa, o card nasce dela, como o "criar card" (#1142); sem conversa, só do contato, com o nome dele.
# - O card criado "entrou na etapa": as automações de entrada dela rodam, como depois de mover.
class Autonomia::Automacao::CardNovo
  include Events::Types

  # automacao: quem criou (`{ origem:, id: }`, Crm::Cards::Creator), para a IA do funil respeitar a etapa (#2428).
  def initialize(stage:, conversation: nil, contact: nil, actor: nil, automacao: nil)
    @stage = stage
    @conversation = conversation
    @contact = conversation&.contact || contact
    @actor = actor
    @automacao = automacao
  end

  # O card criado, ou nil quando o bloco disse que já tem.
  def criar
    card = nil
    (@conversation || @contact).with_lock do
      next if yield

      card = Crm::Cards::Creator.new(account: @stage.account, user: @actor, conversation: @conversation, params: params,
                                     automacao: @automacao).perform
    end
    return if card.blank?

    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_CREATED)
    Crm::StageAutomations::Runner.new(card: card, actor: @actor, from_stage_id: nil, to_stage_id: card.stage_id).perform
    card
  end

  private

  def params
    base = { pipeline_id: @stage.pipeline_id, stage_id: @stage.id }
    return base if @conversation

    base.merge(contact_id: @contact.id, title: @contact.name.presence || @contact.phone_number.presence || "##{@contact.id}")
  end
end
