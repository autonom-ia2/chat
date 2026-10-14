require 'rails_helper'

# Contrato do bloco de segmento (tema 8, #1429). Hoje o conteúdo é nil; estes exemplos continuam valendo quando a
# Segmentação preencher o texto. "Nenhuma frase pronta de cliente" é regra de conteúdo, escrita no próprio arquivo.
RSpec.describe Autonomia::Segmentos::Bloco do
  let(:account) { create(:account) }

  it 'returns nil or a String' do
    expect(described_class.for(account)).to be_nil.or(be_a(String))
  end

  it 'is stable between calls for the same account' do
    primeira = described_class.for(account)

    expect(described_class.for(account)).to eq(primeira)
  end

  it 'is stable when the account is read again from the database' do
    expect(described_class.for(Account.find(account.id))).to eq(described_class.for(account))
  end

  # Trava do contrato: um único argumento obrigatório (a conta). Argumento opcional pode entrar sem quebrar quem chama.
  it 'depends only on the account, never on a conversation' do
    obrigatorios = described_class.method(:for).parameters.count { |tipo, _| %i[req keyreq].include?(tipo) }

    expect(obrigatorios).to eq(1)
  end

  it 'gives the same text for an account with conversations' do
    antes = described_class.for(account)
    create(:conversation, account: account)

    expect(described_class.for(account.reload)).to eq(antes)
  end
end
