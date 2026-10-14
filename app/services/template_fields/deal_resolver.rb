# negocio.* (#1331): o card do CRM, só leitura.
#
# Recebe o card JÁ resolvido; não busca card nenhum. Acesso por funil (#1148, contrato do #1322): quem chama com uma
# pessoa lê o card pelo escopo do CRM (`policy_scope(::Crm::Card)`, que aplica `Crm::Access::CardScope`); num job, passa
# o card que o job já tem. O responsável é o dono do card (`owner_id`); escolher dono continua sendo de
# `CardGuard`, fora daqui.
class TemplateFields::DealResolver
  include TemplateFields::FieldReader

  READERS = {
    'negocio.titulo' => :title, 'negocio.funil' => :pipeline, 'negocio.etapa' => :stage,
    'negocio.valor' => :amount, 'negocio.responsavel' => :owner, 'negocio.prazo' => :deadline
  }.freeze

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

  # O prazo do card (`expected_close_at`; na Cobrança, "Vencimento"), como data no fuso da conta.
  def deadline
    TemplateFields::Format.date(card.expected_close_at, TemplateFields::Format.account_zone(card.account))
  end

  def owner
    card.owner&.available_name
  end
end
