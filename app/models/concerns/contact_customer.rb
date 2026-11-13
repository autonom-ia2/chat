# Lead vira cliente (#1144): o contact_type `customer` já existia e nada o promovia.
#
# - Ganho num funil que conta como venda promove o contato do card (Crm::Card, ao gravar o status won).
# - O painel do contato marca e desfaz à mão (Contacts::CustomersController), para quem não usa o ganho.
# - customer_since guarda a primeira vez: ganhar de novo não muda a data. Desfazer volta o contato para lead.
# - Quem promove sabendo desde quando (a carteira de seguros, #2897: o começo da vigência da apólice) passa `since:`. A
#   data mais antiga vence, também em quem já é cliente; a mais nova não muda nada. Data no futuro vira agora, e a data
#   sem hora vira o começo daquele dia no fuso da conta. Só conta como promoção (`true`) quem não era cliente.
# - Mescla de contatos fica com o cliente e a data mais antiga (ContactMergeAction#inherited_customer).
# - Gravam com lock e sem as validações do contato, como a recusa (ContactOptOut): dado antigo fora do formato não
#   impede o registro.
module ContactCustomer
  extend ActiveSupport::Concern

  # Revisão: Multifunnel
  def become_customer!(since: nil)
    with_lock do
      desde = [customer_since, moment_of(since)].compact.min
      next false if customer? && desde == customer_since

      promoted = !customer?
      assign_attributes(contact_type: :customer, customer_since: desde || Time.current)
      save!(validate: false)
      promoted
    end
  end

  # A data sem hora é o começo daquele dia no fuso da conta; nada fica no futuro.
  def moment_of(since)
    return if since.nil?

    moment = since.is_a?(Date) ? since.in_time_zone(Crm::Timezone::Resolver.new(account: account).name_or_default) : since
    [moment, Time.current].min
  end
  private :moment_of

  def release_customer!
    with_lock do
      next false unless customer?

      assign_attributes(contact_type: :lead, customer_since: nil)
      save!(validate: false)
      true
    end
  end
end
