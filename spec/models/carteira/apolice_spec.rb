require 'rails_helper'

# E4 (#2897): o que o banco e o model garantem da carteira de seguros. `seguradora_chave` e `numero_chave` chegam prontas
# aqui; quem as calcula é quem grava, com Carteira::Chave.
RSpec.describe Carteira::Apolice do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:fim) { Date.new(2027, 11, 12) }
  let(:mesma) { { seguradora_chave: 'seguradoraexemplo', numero: 'EX-001234', numero_chave: 'EX001234', fim_vigencia: fim } }

  def apolice(conta: account, pessoa: contact, **campos)
    create(:carteira_apolice, account: conta, contact: pessoa, **campos)
  end

  describe 'a mesma apólice (seguradora, número e fim da vigência)' do
    before { apolice(**mesma) }

    it 'não entra duas vezes na mesma conta, pelo índice único do banco' do
      expect { apolice(**mesma) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'entra em outra conta' do
      outra = create(:account)

      expect(apolice(conta: outra, pessoa: create(:contact, account: outra), **mesma)).to be_persisted
    end

    it 'entra de novo com outro fim da vigência: a renovação que mantém o número' do
      expect(apolice(**mesma, fim_vigencia: fim + 1.year)).to be_persisted
    end
  end

  it 'a mesma apólice escrita de outro jeito (espaço, caixa, acento, pontuação) não entra de novo: a forma de comparação junta' do
    escrita = lambda do |seguradora, numero|
      { seguradora: seguradora, seguradora_chave: Carteira::Chave.seguradora(seguradora), numero: numero,
        numero_chave: Carteira::Chave.numero(numero), fim_vigencia: fim }
    end
    apolice(**escrita.call('Seguradora Exemplo S.A.', 'EX-001234'))

    expect { apolice(**escrita.call(' segúradora EXEMPLO sa ', 'ex 001.234')) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'seguro sem número não colide com outro sem número da mesma seguradora e vigência' do
    sem_numero = mesma.merge(numero: nil, numero_chave: nil)
    apolice(**sem_numero)

    expect(apolice(**sem_numero)).to be_persisted
  end

  it 'o banco recusa tipo e origem fora da lista, fim antes do início e valor negativo' do
    # Cada tentativa num savepoint: o erro do banco aborta a transação do exemplo. update_all de propósito: é o caminho
    # que pula a validação do model, que recusaria antes do banco.
    linha = described_class.where(id: apolice(fim_vigencia: fim).id)
    gravar = lambda do |campos|
      described_class.transaction(requires_new: true) { linha.update_all(campos) } # rubocop:disable Rails/SkipsModelValidations
    end
    fora = {
      'carteira_apolices_tipo' => { tipo: 'moto' },
      'carteira_apolices_origem' => { origem: 'email' },
      'carteira_apolices_vigencia' => { inicio_vigencia: fim + 1.day },
      'carteira_apolices_valor' => { valor_centavos: -1 },
      'carteira_apolices_numero' => { numero_chave: nil },
      'carteira_apolices_chaves' => { numero_chave: '' }
    }

    fora.each do |check, campos|
      pelo_check = ->(erro) { expect([erro.cause.class.name, erro.cause.message.include?(check)]).to eq(['PG::CheckViolation', true]) }

      expect { gravar.call(campos) }.to raise_error(ActiveRecord::StatementInvalid, &pelo_check)
    end
    expect { gravar.call(inicio_vigencia: fim, valor_centavos: 0) }.to change { linha.pick(:inicio_vigencia, :valor_centavos) }.to([fim, 0])
  end

  it 'o model recusa antes do banco o que os checks recusam, e o banco aceita cada tipo e origem que o model lista' do
    invalidas = [{ tipo: 'moto' }, { origem: 'email' }, { inicio_vigencia: fim + 1.day, fim_vigencia: fim }, { valor_centavos: -1 },
                 { seguradora_chave: nil }, { fim_vigencia: nil }, { numero_chave: nil }, { numero: nil }, { numero_chave: '' }]

    expect(invalidas.map { |campos| build(:carteira_apolice, account: account, contact: contact, **campos).valid? }).to all(be(false))
    described_class::TIPOS.each { |tipo| expect(apolice(tipo: tipo)).to be_persisted }
    described_class::ORIGENS.each { |origem| expect(apolice(origem: origem)).to be_persisted }
  end

  it 'recusa a pessoa e a empresa de outra conta: o banco só confere que elas existem' do
    outra = create(:account)
    da_pessoa_de_fora = build(:carteira_apolice, account: account, contact: create(:contact, account: outra))
    da_empresa_de_fora = build(:carteira_apolice, account: account, contact: contact, company: create(:company, account: outra))

    expect([da_pessoa_de_fora, da_empresa_de_fora].map(&:valid?)).to eq([false, false])
    expect(da_pessoa_de_fora.errors.attribute_names + da_empresa_de_fora.errors.attribute_names).to eq(%i[contact company])
    expect(build(:carteira_apolice, account: account, contact: contact, company: create(:company, account: account))).to be_valid
  end

  it 'a história só aceita os tipos de evento que alguém grava' do
    seguro = apolice
    tipos = Carteira::ApoliceEvento::TIPOS + ['inventado']
    validos = tipos.map { |tipo| seguro.eventos.build(tipo: tipo, quando: Time.current).valid? }

    expect(validos).to eq(Carteira::ApoliceEvento::TIPOS.map { true } + [false])
  end

  it 'apagar a apólice leva a história dela, pela chave em cascata' do
    seguro = apolice
    seguro.eventos.create!(tipo: 'chegou_planilha', quando: Time.current)

    seguro.delete

    expect(Carteira::ApoliceEvento.where(apolice_id: seguro.id)).to be_empty
  end

  it 'apagar a empresa deixa a apólice na pessoa, sem a empresa' do
    empresa = create(:company, account: account)
    seguro = apolice(company: empresa)

    empresa.destroy!

    expect(seguro.reload).to have_attributes(company_id: nil, contact_id: contact.id)
  end
end
