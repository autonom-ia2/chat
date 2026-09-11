require 'rails_helper'

RSpec.describe Autonomia::Insurance::Connection do
  let(:account) { create(:account) }

  it 'refuses to store credentials when the encryption vault is not configured' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    connection = described_class.new(account: account, username: 'a@b.com', password: 'x')

    expect(connection).not_to be_valid
    expect(connection.errors[:base].join).to include('ACTIVE_RECORD_ENCRYPTION')
  end

  it 'stores credentials, masks the login and keeps one connection per account/provider' do
    enable_test_encryption!
    connection = described_class.create!(account: account, username: 'corretora@exemplo.com.br', password: 'x')

    expect(connection.username_hint).to eq('co*******@exemplo.com.br')
    expect(connection.public_payload.keys).not_to include(:password, :username)
    expect(connection.public_payload.to_json).not_to include('corretora@exemplo.com.br')
    expect { described_class.create!(account: account, username: 'o@b.com', password: 'y') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  # TERMO 5 DA ENTREGA 16 — o aviso de "conta em uso" não sai daqui para a tela.
  #
  # O portal manda "já existe uma sessão ativa" em TODO login (6 de 6 nos logins simultâneos de
  # 10/09/2026): é aviso de reuso da sessão compartilhada, não prova de que outra pessoa esteja na
  # conta. Publicá-lo fazia a tela de Conexões afirmar ao corretor algo que o dado não sustenta.
  # A chave pode continuar no `metadata` de uma linha antiga; o que não pode é voltar ao payload.
  it 'não publica o aviso de conta em uso, que o portal manda em todo login' do
    enable_test_encryption!
    connection = described_class.create!(account: account, username: 'a@b.com', password: 'x')
    connection.merge_metadata!('account_already_active' => { 'observed_at' => '2026-09-06T14:05:00Z' })

    expect(connection.public_payload).not_to have_key(:account_already_active)
    expect(connection.public_payload.to_json).not_to include('account_already_active')
  end

  it 'allows an empty (not_configured) record without the vault' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    expect(described_class.new(account: account)).to be_valid
  end
end
