# negocio.* (#1331): o card do CRM, só leitura.
#
# Acesso por funil (#1148, contrato do #1322): com uma pessoa, o card só é lido pelo escopo do CRM
# (`policy_scope(::Crm::Card)`, que aplica `Crm::Access::CardScope`) — `visible_card`. Num job não há pessoa: quem
# chama passa o card que já resolveu. O responsável é o dono do card (`owner_id`); escolher dono continua sendo de
# `CardGuard`, fora daqui.
class TemplateFields::DealResolver
  include TemplateFields::FieldReader

  READERS = {
    'negocio.titulo' => :title, 'negocio.funil' => :pipeline, 'negocio.etapa' => :stage,
    'negocio.valor' => :amount, 'negocio.responsavel' => :owner
  }.freeze

  # O card que a pessoa vê nesta conta, ou nil.
  def self.visible_card(account:, user:, card_id:)
    account_user = AccountUser.find_by(account_id: account.id, user_id: user.id)
    context = { user: user, account: account, account_user: account_user }
    Pundit.policy_scope!(context, ::Crm::Card).find_by(id: card_id)
  end

  def initialize(card)
    @card = card
  end

  private

  attr_reader :card

  def title
    card.title
  end

  def pipeline
    card.pipeline&.name
  end

  def stage
    card.stage&.name
  end

  # Card sem valor (0, o padrão) não tem valor: "R$ 0,00" numa mensagem ao cliente seria engano.
  def amount
    card.value_cents.to_i.positive? ? TemplateFields::Format.money_cents(card.value_cents, card.currency) : nil
  end

  def owner
    card.owner&.available_name
  end
end
