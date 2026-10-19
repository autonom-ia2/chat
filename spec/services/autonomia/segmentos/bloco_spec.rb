require 'rails_helper'

# Contrato do bloco de segmento (tema 8, #1429). O conteúdo (#1802, lote 6) vale só com o interruptor ligado e conta
# de seguros. "Nenhuma frase pronta de cliente" é regra de conteúdo, escrita no próprio arquivo.
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

  context 'with the switch on (#1802, lote 6)' do
    let(:nicho) { Autonomia::Agents::Nicho }

    around { |example| with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') { example.run } }

    def conta(nicho_escolhido, perfil = nil)
      create(:account, internal_attributes: { nicho::NICHO_KEY => nicho_escolhido, nicho::PERFIL_KEY => perfil }.compact)
    end

    it 'gives each insurance type its own text, stable between calls and database reads' do
      textos = nicho::PERFIS.map do |perfil|
        account = conta('seguros', perfil)
        texto = described_class.for(account)

        expect(texto).to be_a(String).and(be_present)
        expect(described_class.for(Account.find(account.id))).to eq(texto)
        texto
      end

      expect(textos.uniq.size).to eq(nicho::PERFIS.size)
    end

    it 'keeps the brokerage text about intermediation, never as the insurer' do
      expect(described_class.for(conta('seguros', 'corretora'))).to include('corretora de seguros', 'não é a seguradora')
    end

    it 'calls the health plan user a beneficiary' do
      expect(described_class.for(conta('seguros', 'saude_beneficios'))).to include('beneficiário, não segurado')
    end

    it 'keeps the general account without a block' do
      expect(described_class.for(conta('geral'))).to be_nil
    end

    it 'stays short, so the cached prefix stays small' do
      nicho::PERFIS.each do |perfil|
        expect(described_class.for(conta('seguros', perfil)).size).to be < 1500
      end
    end
  end

  it 'gives no block to an insurance account with the switch off' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
      nicho = Autonomia::Agents::Nicho
      account = create(:account, internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => 'corretora' })

      expect(described_class.for(account)).to be_nil
    end
  end
end
