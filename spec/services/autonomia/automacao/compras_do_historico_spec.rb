require 'rails_helper'

# #3098: no topo do histórico, quantas pessoas a automação alcançou nos 30 dias e quantas compraram até 7 dias depois
# da primeira vez que ela agiu com cada uma (conversa, card ou contato).
RSpec.describe Autonomia::Automacao::ComprasDoHistorico, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:account_user) { account.account_users.find_by(user: admin) }
  let(:automacao) { create(:autonomia_automacao, account: account) }
  let(:versao) { create(:autonomia_automacao_versao, automacao: automacao) }
  let(:inbox) { create(:inbox, account: account) }
  let(:sale) { create_crm_pipeline(account: account, user: admin) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  def pessoa(nome)
    create(:contact, account: account, name: nome)
  end

  def execucao(alvo, quando:)
    travel_to(quando) { create(:autonomia_automacao_execucao, versao: versao, alvo: alvo, chave_gatilho: "#{alvo.class.name}-#{alvo.id}") }
  end

  def card(contato, status: :open, valor: 0)
    pipeline, stage = sale
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: contato.name, contact: contato, status: status, value_cents: valor)
  end

  def compra(contato, quando:, valor:)
    card(contato, status: :won, valor: valor).tap { |ganho| ganho.update_columns(closed_at: quando) } # rubocop:disable Rails/SkipsModelValidations
  end

  def resumo
    described_class.new(automacao: automacao, user: admin, account_user: account_user).resumo
  end

  it 'conta as pessoas pela conversa, pelo card e pelo contato, e quem comprou até 7 dias depois' do
    ana = pessoa('Ana')
    bia = pessoa('Bia')
    caio = pessoa('Caio')
    execucao(create(:conversation, account: account, inbox: inbox, contact: ana), quando: 10.days.ago)
    execucao(ana, quando: 5.days.ago)
    execucao(card(bia), quando: 10.days.ago)
    execucao(caio, quando: 10.days.ago)
    execucao(pessoa('Velha'), quando: 40.days.ago)
    compra(ana, quando: 7.days.ago, valor: 40_000)
    compra(bia, quando: 1.day.ago, valor: 90_000)

    expect(resumo).to eq(dias: 30, janela: 7, passaram: 3, compraram: 1, valor: [{ currency: 'BRL', cents: 40_000 }])
  end

  it 'esconde o valor de quem não vê valor de venda' do
    ana = pessoa('Ana')
    execucao(ana, quando: 3.days.ago)
    compra(ana, quando: 1.day.ago, valor: 40_000)
    allow(Crm::ValorDeVenda).to receive(:ve?).and_return(false)

    expect(resumo).to include(passaram: 1, compraram: 1, valor: nil)
  end
end
