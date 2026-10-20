# #1920: a evidência só lê cards que ensinam e o raio-x só cards que provam (Crm::Ai::EscolhaDePessoa). Cria o card do
# lado pedido; quando o id cai do outro lado, esse card fica vago (sem conversa nem movimento) e o próximo é o do teste.
module CrmEscolhaDePessoaHelpers
  def create_crm_card_do_lado(account:, lado:, **atributos)
    quer_par = lado == :ensina
    vago = account.crm_cards.create!(**atributos.except(:conversation_id), title: 'Vago')
    return vago.tap { |card| card.update!(**atributos) } if vago.id.even? == quer_par

    account.crm_cards.create!(**atributos)
  end
end

RSpec.configure do |config|
  config.include CrmEscolhaDePessoaHelpers
end
