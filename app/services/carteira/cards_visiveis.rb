# Os cards do CRM que quem pede enxerga no quadro (E5, #2898): a mesma régua do Kanban (Crm::CardPolicy e o escopo
# dela: caixa, "Só as suas", acesso por funil e, no EE, a chave `crm_view`). A carteira é de quem vê contatos, e o card
# de renovação mora num funil que essa pessoa pode não abrir: o que a carteira conta de um card (o id, o funil, a etapa,
# quem cuida) passa por aqui.
#
# quem: o contexto de quem pede, como o Pundit o recebe ({ user:, account:, account_user: }). Sem ele, com o CRM
# desligado ou sem acesso ao CRM, nenhum card.
class Carteira::CardsVisiveis
  def initialize(quem)
    @quem = quem
  end

  def call
    return Crm::Card.none unless @quem.present? && Crm::Config.enabled? && Pundit.policy!(@quem, Crm::Card).index?

    Pundit.policy_scope!(@quem, Crm::Card)
  end
end
