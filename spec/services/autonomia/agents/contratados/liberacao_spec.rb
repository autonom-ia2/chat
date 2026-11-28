require 'rails_helper'

# #3270 — a liberação do agente contratado, por conta e por modelo, no jsonb interno da conta (como o nicho).
RSpec.describe Autonomia::Agents::Contratados::Liberacao do
  let(:account) { create(:account, internal_attributes: { 'unrelated' => 'preserved' }) }
  let(:chave) { 'seguro_viagem_universal' }

  it 'grava só as chaves do catálogo, sem tocar nas outras de internal_attributes' do
    described_class.atribuir(account, ['', chave, 'outro_modelo'])
    account.save!

    expect(account.reload.internal_attributes).to include('unrelated' => 'preserved', described_class::CHAVE => [chave])
    expect(described_class.liberado?(account, chave)).to be(true)
  end

  it 'lista vazia desliga' do
    described_class.atribuir(account, [chave])
    described_class.atribuir(account, [''])
    account.save!

    expect(described_class.modelos(account.reload)).to eq([])
    expect(described_class.liberado?(account, chave)).to be(false)
  end

  it 'na leitura, chave gravada fora do catálogo não vale' do
    account.update!(internal_attributes: { described_class::CHAVE => %w[outro_modelo] })

    expect(described_class.modelos(account)).to eq([])
  end

  it 'conta sem nada gravado: nenhum liberado' do
    expect(described_class.modelos(account)).to eq([])
    expect(described_class.liberado?(account, chave)).to be(false)
  end

  it 'o atributo da conta lê e grava pelo mesmo lugar (o campo do super admin)' do
    account.update!(contratados_liberados: ['', chave])

    expect(account.reload.contratados_liberados).to eq([chave])
  end
end
