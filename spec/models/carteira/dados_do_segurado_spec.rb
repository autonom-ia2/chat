require 'rails_helper'

# E8.1 (#3043): os dados do segurado que a cotação da renovação pede, na apólice da carteira. Dados fictícios.
RSpec.describe Carteira::DadosDoSegurado do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:do_segurado) { { segurado_nascimento: '1985-03-15', segurado_sexo: 'F', cep: '12345678', placa: 'EXM0A00', bonus_classe: 5 } }

  def apolice(**campos)
    create(:carteira_apolice, account: account, contact: contact, **campos)
  end

  before { travel_to(Time.zone.local(2026, 11, 17, 12)) }

  it 'aceita os cinco na forma da coluna, e cada um pode ficar nulo' do
    expect(apolice(**do_segurado)).to have_attributes(do_segurado)
    expect(apolice.attributes.slice(*described_class::COLUNAS.map(&:to_s)).values).to all(be_nil)
  end

  it 'recusa o que está fora da forma, sem repetir o valor na mensagem' do
    fora_da_forma = {
      segurado_nascimento: ['15/03/1985', '1985-02-30', '2026-11-18', '1985-3-15'], segurado_sexo: %w[f X Feminino],
      cep: %w[1234567 123456789 12345-678], placa: %w[EXM0A0 1234567 EXM-0A00 exm0a00], bonus_classe: [11, -1]
    }

    fora_da_forma.each do |coluna, valores|
      valores.each do |valor|
        seguro = build(:carteira_apolice, account: account, contact: contact)
        seguro.assign_attributes(coluna => valor)

        expect(seguro).not_to be_valid, "#{coluna} #{valor}"
        expect(seguro.errors.details[coluna]).to be_present, "#{coluna} #{valor}"
        expect(seguro.errors.full_messages.join).not_to include(valor.to_s)
      end
    end
  end

  it 'o banco também recusa sexo, CEP e bônus fora da forma (CHECK), e aceita o que o model aceita' do
    # Cada tentativa num savepoint: o erro do banco aborta a transação do exemplo. update_all de propósito: é o caminho
    # que pula a validação do model.
    linha = Carteira::Apolice.where(id: apolice.id)
    gravar = lambda do |campos|
      Carteira::Apolice.transaction(requires_new: true) { linha.update_all(campos) } # rubocop:disable Rails/SkipsModelValidations
    end
    fora = {
      'carteira_apolices_sexo' => [{ segurado_sexo: 'X' }, { segurado_sexo: 'f' }],
      'carteira_apolices_cep' => [{ cep: '1234567a' }, { cep: '1234567' }, { cep: '12345-678' }],
      'carteira_apolices_bonus' => [{ bonus_classe: 11 }, { bonus_classe: -1 }]
    }

    fora.each do |check, tentativas|
      pelo_check = ->(erro) { expect([erro.cause.class.name, erro.cause.message.include?(check)]).to eq(['PG::CheckViolation', true]) }

      tentativas.each { |campos| expect { gravar.call(campos) }.to raise_error(ActiveRecord::StatementInvalid, &pelo_check) }
    end
    expect { gravar.call(segurado_sexo: 'M', cep: '12345678', bonus_classe: 0) }
      .to change { linha.pick(:segurado_sexo, :cep, :bonus_classe) }.to(['M', '12345678', 0])
  end

  it 'não aparece no inspect, no JSON padrão do model nem nos parâmetros filtrados' do
    seguro = apolice(**do_segurado)

    expect(seguro.inspect).not_to include('1985-03-15', '12345678', 'EXM0A00')
    expect(seguro.as_json.keys).not_to include(*described_class::COLUNAS.map(&:to_s))
    expect(seguro.to_json).not_to include('1985-03-15', '12345678', 'EXM0A00')
    expect(Carteira::Apolice.filter_attributes).to include(*described_class::COLUNAS)
  end

  it 'o nascimento é cifrado quando a instalação tem as chaves' do
    expect(Carteira::Apolice.encrypted_attributes.to_a.include?(:segurado_nascimento)).to eq(Chatwoot.encryption_configured?)
  end
end
