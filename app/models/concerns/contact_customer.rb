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

  TYPES_BEFORE_CUSTOMER = %w[visitor lead].freeze

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

  # Revisão: Multifunnel
  # O Desfazer de "Trazer minha lista" (#2896) devolve ao tipo de antes quem a lista marcou como cliente: visitante ou
  # lead, e não sempre lead como o release_customer!. Só o Desfazer chama (Relacionamentos::Trazer::CampoQueVolta).
  # Sob a trava e com o contato relido, só volta quem continua cliente e passa no bloco. É o bloco que confere se a
  # marca ainda é a da lista: a mesma customer_since que ela gravou e nenhum card ganho depois dela (o ganho chama
  # become_customer!, que não mexe em quem já é cliente; sem conferir, quem comprou de verdade voltaria a lead).
  # Com `to: 'visitor'`, quem tem telefone ou e-mail termina lead: ao gravar, Contacts::SyncAttributes promove o
  # visitante que tem por onde ser contatado. A lista só acha pelo telefone ou pelo e-mail quem a conta já tinha.
  def revert_customer!(to:)
    with_lock do
      next false unless customer? && TYPES_BEFORE_CUSTOMER.include?(to.to_s) && yield

      assign_attributes(contact_type: to, customer_since: nil)
      save!(validate: false)
      true
    end
  end
end
