require 'rails_helper'

# #1140 — o servidor ordena os nomes como a tela (localeCompare): sem diferença de acento nem de maiúsculas, com
# desempate por id. Antes, "Fábio" vinha antes de "Érica" e nomes iguais ficavam na ordem do banco.
RSpec.describe Crm::OrdemDeNome do
  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  # Criados fora da ordem esperada, para a ordem do banco não passar por acerto.
  let!(:fabio) { create_crm_agent(account: account, name: 'Fábio').first }
  let!(:ana_minuscula) { create_crm_agent(account: account, name: 'ana').first }
  let!(:erica) { create_crm_agent(account: account, name: 'Érica').first }
  let!(:ana) { create_crm_agent(account: account, name: 'Ana').first }
  let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp', members: [fabio, erica, ana_minuscula, ana]) }
  let(:ordem_esperada) { [ana_minuscula.id, ana.id, erica.id, fabio.id] }

  # Pega: acento ou maiúscula mudando a ordem ("Fábio" antes de "Érica", "ana" depois de "Fábio").
  it 'ordena sem acento e sem maiúsculas, com desempate por id' do
    pessoas = [fabio, erica, ana, ana_minuscula].map { |user| [user.available_name, user.id] }

    expect(pessoas.sort_by { |nome, id| described_class.chave(nome, id) }.map(&:last)).to eq(ordem_esperada)
  end

  # Pega: a lista de quem recebe (motor de entrega) sair numa ordem diferente da tela.
  it 'Crm::Entrega::QuemCuida.na_caixa usa a mesma ordem' do
    expect(Crm::Entrega::QuemCuida.na_caixa(inbox: inbox).map(&:id)).to eq(ordem_esperada)
  end

  # Pega: as pessoas da caixa no Retrato sem desempate por id ou com acento fora de ordem.
  it 'Crm::Caixas::Retrato usa a mesma ordem' do
    caixa = Crm::Caixas::Retrato.new(account: account, inboxes: [inbox]).caixas.first

    expect(caixa[:people].pluck(:id)).to eq(ordem_esperada)
  end
end
