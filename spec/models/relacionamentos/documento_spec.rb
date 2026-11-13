require 'rails_helper'

# Épico #1240, decisão R1: o que o banco e o model garantem do CPF e do CNPJ guardados. Guardar, achar e ler, com a cifra
# ligada e desligada, estão em spec/services/relacionamentos/documentos_spec.rb. Os números são inventados (sequências).
RSpec.describe Relacionamentos::Documento do
  let(:account) { create(:account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo') }
  let(:oficina) { create(:company, account: account, name: 'Oficina Exemplo') }
  let(:cpf) { '12345678909' }
  let(:cnpj) { '11222333000181' }

  def documento(**campos)
    described_class.new(account: account, tipo: 'cpf', valor: cpf, **campos)
  end

  # Grava sem a validação do model, num savepoint: o erro do banco aborta a transação do exemplo.
  def gravar_direto(**campos)
    described_class.transaction(requires_new: true) { documento(**campos).save!(validate: false) }
  end

  it 'guarda um CPF e um CNPJ por dono; o segundo do mesmo tipo é recusado pelo índice único do banco' do
    documento(contact: marina).save!
    documento(contact: marina, tipo: 'cnpj', valor: cnpj).save!
    documento(company: oficina, tipo: 'cnpj', valor: cnpj).save!

    expect { gravar_direto(contact: marina, valor: '98765432100') }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { gravar_direto(company: oficina, tipo: 'cnpj', valor: '98765432000198') }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(described_class.where(account_id: account.id).count).to eq(3)
  end

  it 'aceita o mesmo número em dois cadastros da mesma conta' do
    repetida = create(:contact, account: account, name: 'Marina E.')

    expect([documento(contact: marina).save, documento(contact: repetida).save]).to eq([true, true])
  end

  it 'o banco recusa documento sem dono, com dois donos, de tipo fora da lista e CPF em empresa' do
    fora = {
      'relacionamentos_documentos_dono' => [{ tipo: 'cnpj', valor: cnpj }, { contact: marina, company: oficina }],
      'relacionamentos_documentos_tipo' => [{ contact: marina, tipo: 'rg' }],
      'relacionamentos_documentos_cpf_so_de_pessoa' => [{ company: oficina }]
    }

    fora.each do |check, tentativas|
      pelo_check = ->(erro) { expect([erro.cause.class.name, erro.cause.message.include?(check)]).to eq(['PG::CheckViolation', true]) }

      tentativas.each { |campos| expect { gravar_direto(**campos) }.to raise_error(ActiveRecord::StatementInvalid, &pelo_check) }
    end
  end

  it 'o model recusa antes do banco: número que não confere, tipo trocado, forma com pontuação, dono demais ou de menos' do
    invalidos = [{ contact: marina, valor: '12345678908' }, { contact: marina, tipo: 'cnpj' }, { contact: marina, valor: '123.456.789-09' },
                 { contact: marina, tipo: 'rg' }, { contact: marina, company: oficina }, {}]

    expect(invalidos.map { |campos| documento(**campos).valid? }).to all(be(false))
    expect([documento(contact: marina), documento(company: oficina, tipo: 'cnpj', valor: cnpj)]).to all(be_valid)
  end

  it 'a empresa só tem CNPJ; a pessoa pode ter CPF e CNPJ (o MEI é pessoa com CNPJ)' do
    cpf_em_empresa = documento(company: oficina)

    expect([cpf_em_empresa.valid?, cpf_em_empresa.errors.attribute_names]).to eq([false, [:tipo]])
    expect([documento(contact: marina), documento(contact: marina, tipo: 'cnpj', valor: cnpj)]).to all(be_valid)
  end

  it 'recusa a pessoa e a empresa de outra conta: o banco só confere que elas existem' do
    outra = create(:account)
    da_pessoa_de_fora = documento(contact: create(:contact, account: outra))
    da_empresa_de_fora = documento(company: create(:company, account: outra), tipo: 'cnpj', valor: cnpj)

    expect([da_pessoa_de_fora, da_empresa_de_fora].map(&:valid?)).to eq([false, false])
    expect(da_pessoa_de_fora.errors.attribute_names + da_empresa_de_fora.errors.attribute_names).to eq(%i[contact company])
  end

  it 'diz quem é o dono e mostra o número pontuado e mascarado' do
    da_pessoa = documento(contact: marina)
    da_empresa = documento(company: oficina, tipo: 'cnpj', valor: cnpj)

    expect([da_pessoa.dono, da_empresa.dono]).to eq([marina, oficina])
    expect([da_pessoa.formatado, da_pessoa.mascarado]).to eq(['123.456.789-09', '***.***.***-09'])
    expect([da_empresa.formatado, da_empresa.mascarado]).to eq(['11.222.333/0001-81', '**.***.***/****-81'])
  end

  it 'apagar a pessoa ou a empresa apaga o documento, mesmo por caminho sem callback' do
    da_pessoa = documento(contact: marina).tap(&:save!)
    da_empresa = documento(company: oficina, tipo: 'cnpj', valor: cnpj).tap(&:save!)

    Contact.where(id: marina.id).delete_all
    oficina.destroy!

    expect(described_class.where(id: [da_pessoa.id, da_empresa.id])).to be_empty
  end

  it 'as chaves para a pessoa e para a empresa são em cascata, e a da conta não' do
    acoes = ActiveRecord::Base.connection.select_rows(<<~SQL.squish).to_h
      SELECT c.confrelid::regclass::text, c.confdeltype::text
      FROM pg_constraint c
      WHERE c.contype = 'f' AND c.conrelid = 'relacionamentos_documentos'::regclass
    SQL

    expect(acoes).to eq('accounts' => 'a', 'contacts' => 'c', 'companies' => 'c')
  end
end
