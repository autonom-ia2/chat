require 'rails_helper'

# G29 (#2702): a etiqueta com o nome de um dado no passo de etiquetas.
RSpec.describe Autonomia::Automacao::EtiquetasDoDado do
  let(:account) { create(:account) }
  let(:receita) { { 'por' => ['vip', { '$valor' => 'card.anuncio' }], 'tirar' => ['lead'] } }

  it 'converte só a etiqueta que veio de um dado e guarda o texto original', :aggregate_failures do
    pronto = described_class.preparar(receita, { 'por' => ['vip', 'Black Friday, 50% off'], 'tirar' => ['lead'] })

    expect(pronto.corpo).to eq({ 'por' => %w[vip black_friday_50_off], 'tirar' => ['lead'] })
    expect(pronto.originais).to eq({ 'black_friday_50_off' => 'Black Friday, 50% off' })
  end

  it 'pula quando o dado não vira etiqueta nenhuma' do
    expect(described_class.preparar(receita, { 'por' => ['vip', '%%'], 'tirar' => ['lead'] }).motivo).to eq('etiqueta_sem_nome_valido')
  end

  it 'cadastra a etiqueta com o texto original só para quem pode cadastrar etiqueta', :aggregate_failures do
    agente = create(:user, account: account, role: :agent)
    admin = create(:user, account: account, role: :administrator)
    originais = { 'black_friday_50_off' => 'Black Friday, 50% off' }

    described_class.cadastrar(originais, account: account, account_user: AccountUser.find_by(user: agente, account: account))
    expect(account.labels).to be_empty

    described_class.cadastrar(originais, account: account, account_user: AccountUser.find_by(user: admin, account: account))
    expect(account.labels.sole).to have_attributes(title: 'black_friday_50_off', description: 'Black Friday, 50% off')
  end

  it 'não mexe na etiqueta que a conta já tem' do
    account.labels.create!(title: 'black_friday_50_off', description: 'escrita pela dona')
    admin = create(:user, account: account, role: :administrator)

    described_class.cadastrar({ 'black_friday_50_off' => 'Black Friday, 50% off' },
                              account: account, account_user: AccountUser.find_by(user: admin, account: account))

    expect(account.labels.sole.description).to eq('escrita pela dona')
  end
end
