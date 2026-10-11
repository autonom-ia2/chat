# Os resolvedores do catálogo se somam (#1331, PRD §6): Contato, Conta e Atendente na base; Público, Negócio e
# Horário por cima. `keys` é o que o contexto consegue preencher (para criar um modelo a partir dele e para conferir a
# cobertura); `value(key)` é o texto pronto, ou nil para cair no padrão ou deixar a pessoa de fora com "falta {{N}}".
#
#   resolver = TemplateFields::Resolver.for_meeting(meeting, invite: invite)
#   resolver.values_for(TemplateFields::MeetingResolver::NOTICE_KEYS) # => ['Ana', '14/10 às 15:00', 'https://…/b/AB3K9QXZ']
#
# Só leitura. Os valores vão literais para a Meta (nunca pelo Liquid, #1021).
class TemplateFields::Resolver
  def initialize(*resolvers)
    @resolvers = resolvers.compact
  end

  # Contato, conta e a linha da planilha do Público (campanha).
  def self.for_audience(contact:, columns:, values:, types: {}, account: contact.account)
    new(TemplateFields::ContactResolver.new(contact), TemplateFields::AccountResolver.new(account),
        TemplateFields::AudienceResolver.new(columns: columns, values: values, types: types))
  end

  # Um card já resolvido (num job) ou lido pelo escopo do CRM (`DealResolver.visible_card`). attendant: quem envia.
  def self.for_card(card, attendant: nil)
    new(card.contact && TemplateFields::ContactResolver.new(card.contact), TemplateFields::AccountResolver.new(card.account),
        TemplateFields::DealResolver.new(card), attendant && TemplateFields::AttendantResolver.new(attendant))
  end

  # A reunião do agendamento: o contato do convite, a conta, o horário e o card da reunião.
  def self.for_meeting(meeting, invite: nil)
    contact = invite&.contact || meeting.card&.contact
    new(contact && TemplateFields::ContactResolver.new(contact), TemplateFields::AccountResolver.new(meeting.account),
        TemplateFields::MeetingResolver.new(meeting, invite: invite), meeting.card && TemplateFields::DealResolver.new(meeting.card))
  end

  def keys
    @resolvers.flat_map(&:keys).uniq
  end

  def value(key)
    key = key.to_s
    @resolvers.find { |resolver| resolver.keys.include?(key) }&.value(key)
  end

  def values_for(keys)
    keys.map { |key| value(key) }
  end
end
