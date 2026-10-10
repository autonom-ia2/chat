# Lead vira cliente (#1144): o contact_type `customer` já existia e nada o promovia.
#
# - Ganho num funil que conta como venda promove o contato do card (Crm::Card, ao gravar o status won).
# - O painel do contato marca e desfaz à mão (Contacts::CustomersController), para quem não usa o ganho.
# - customer_since guarda a primeira vez: ganhar de novo não muda a data. Desfazer volta o contato para lead.
# - Mescla de contatos fica com o cliente e a data mais antiga (ContactMergeAction#inherited_customer).
# - Gravam com lock e sem as validações do contato, como a recusa (ContactOptOut): dado antigo fora do formato não
#   impede o registro.
module ContactCustomer
  extend ActiveSupport::Concern

  def become_customer!
    with_lock do
      next false if customer?

      assign_attributes(contact_type: :customer, customer_since: customer_since || Time.current)
      save!(validate: false)
      true
    end
  end

  def release_customer!
    with_lock do
      next false unless customer?

      assign_attributes(contact_type: :lead, customer_since: nil)
      save!(validate: false)
      true
    end
  end
end
