# cliente.* e empresa_cliente.* de um contato (#1331).
#
# Primeiro nome: UMA regra para todo modelo, a do agendamento (`Crm::BookingV2::InviteText.first_name`): a primeira
# palavra do nome, e nada quando o nome é só um telefone (contato do WhatsApp sem nome). Sem valor, a variável cai no
# padrão ou a pessoa fica de fora com "falta {{N}}" — nunca recebe "Oi, +55 11 9…".
#
# Cliente desde: o contrato do #1322 (`contact_type = customer` + `customer_since`); contato que não é cliente não tem.
class TemplateFields::ContactResolver
  include TemplateFields::FieldReader

  READERS = {
    'cliente.nome' => :name, 'cliente.primeiro_nome' => :first_name, 'cliente.telefone' => :phone,
    'cliente.email' => :email, 'cliente.cliente_desde' => :customer_since,
    'empresa_cliente.nome' => :company_name, 'empresa_cliente.cnpj' => :company_cnpj
  }.freeze
  BRAZIL = 'BR'.freeze

  def self.first_name(contact)
    Crm::BookingV2::InviteText.first_name(contact).presence
  end

  def initialize(contact)
    @contact = contact
  end

  private

  attr_reader :contact

  def name
    contact.name
  end

  def first_name
    self.class.first_name(contact)
  end

  # Celular do Brasil como a pessoa lê, "(11) 98765-4321"; de outro país, no formato internacional.
  def phone
    number = contact.phone_number.to_s
    parsed = TelephoneNumber.parse(number) if number.present?
    return number unless parsed&.valid?

    parsed.country&.country_id == BRAZIL ? parsed.national_number(formatted: true) : parsed.international_number(formatted: true)
  end

  def email
    contact.email
  end

  def customer_since
    return unless contact.customer? && contact.customer_since

    TemplateFields::Format.date(contact.customer_since, TemplateFields::Format.account_zone(contact.account))
  end

  def company
    contact.try(:company)
  end

  def company_name
    company&.name.presence || contact.additional_attributes.to_h['company_name']
  end

  def company_cnpj
    company ? company.additional_attributes.to_h['cnpj'] : nil
  end
end
