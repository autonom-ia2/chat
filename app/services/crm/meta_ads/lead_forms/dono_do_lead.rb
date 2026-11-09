# G30 (#2702): quem fica com o card do lead do formulário. É o dono que a Atribuição do funil daria (a regra da etapa
# vence a do funil, Crm::Ai::Config.handoff_settings), escolhido entre quem cuida do funil nas caixas ligadas a ele
# (Crm::Entrega::QuemCuida, a mesma fila do motor de entrega, que já respeita o acesso por funil).
#
# O card do lead não tem conversa: não há atendimento ao vivo a segurar nem convite a mandar. Por isso:
# - só entra na fila quem abre o card (função com `crm_view`);
# - a pessoa fixa da regra recebe, se estiver entre quem cuida; senão, vale a fila (como na Crm::Entrega);
# - na fila, quem tem menos cards abertos no funil; empate, quem recebeu card nele há mais tempo; depois, o menor id;
# - "preferir quem está online" escolhe entre os online quando há algum; ninguém online não segura o lead;
# - agente de IA na regra não é dono de card: vale a fila de pessoas.
# Funil sem Atribuição ligada, ou sem ninguém que cuide dele: sem dono, como antes do G30.
class Crm::MetaAds::LeadForms::DonoDoLead
  NUNCA_RECEBEU = Time.zone.at(0)

  def self.para(pipeline:, stage:) = new(pipeline: pipeline, stage: stage).pessoa

  def initialize(pipeline:, stage:)
    @pipeline = pipeline
    @stage = stage
  end

  def pessoa
    regra = Crm::Ai::Config.handoff_settings(@stage, @pipeline)
    return unless regra[:enabled]

    fila = quem_cuida
    return if fila.empty?

    fixa(regra, fila) || com_menos_cards(regra[:prefer_online] ? online_ou_todos(fila) : fila)
  end

  private

  # Só quem abre o card (parecer da Funções): função sem `crm_view` não abre (CardPolicy#index? do EE), e o lead com
  # um dono que não o abre ficaria preso. Mesma conferência do Autonomia::Prospecting::CrmCardOwner#sees_crm?.
  def quem_cuida
    cuidam = @pipeline.inboxes.flat_map { |inbox| Crm::Entrega::QuemCuida.na_caixa(inbox: inbox, pipeline_id: @pipeline.id) }.uniq(&:id)
    vinculos = AccountUser.where(account_id: @pipeline.account_id, user_id: cuidam.map(&:id)).includes(:user).index_by(&:user_id)
    cuidam.select { |pessoa| vinculos[pessoa.id] && ve_o_crm?(vinculos[pessoa.id]) }
  end

  def ve_o_crm?(account_user)
    Pundit.policy!({ user: account_user.user, account: @pipeline.account, account_user: account_user }, Crm::Card).index?
  end

  def fixa(regra, fila)
    return unless regra[:pool_type] == 'user'

    fila.find { |pessoa| pessoa.id == regra[:pool_id].to_i }
  end

  def online_ou_todos(fila)
    online = Crm::Entrega::Presenca.online_ids!(@pipeline.account_id)
    fila.select { |pessoa| online.include?(pessoa.id) }.presence || fila
  rescue Crm::Ai::HandoffMemberSelector::PresencaIndisponivel
    fila
  end

  def com_menos_cards(fila)
    cards = @pipeline.cards.where(owner_id: fila.map(&:id))
    abertos = cards.where(closed_at: nil).group(:owner_id).count
    ultimo = cards.group(:owner_id).maximum(:created_at)
    fila.min_by { |pessoa| [abertos[pessoa.id] || 0, ultimo[pessoa.id] || NUNCA_RECEBEU, pessoa.id] }
  end
end
