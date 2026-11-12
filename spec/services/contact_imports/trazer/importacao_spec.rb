require 'rails_helper'

# #2896 — "Trazer minha lista" de ponta a ponta, com uma planilha de 200 linhas (dados inventados): 180 pessoas novas, 15
# que a conta já tinha e 5 linhas que precisam da pessoa. Da leitura ao que fica gravado, passando pelas respostas, pelos
# destinos das colunas, por um conserto, uma linha deixada de fora e duas leituras de novo no meio.
RSpec.describe 'Trazer minha lista: uma planilha de 200 linhas, da leitura à gravação', :aggregate_failures do # rubocop:disable RSpec/DescribeClass
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:desde) { Time.zone.parse('2024-03-10 12:00') }
  # Colunas depois de juntar o DDD: 0 Nome, 1 Celular, 2 E-mail, 3 Empresa, 4 Cidade, 5 Plano, 6 Segredo.
  # A pessoa N está na linha N + 1. Linhas com problema: 197 telefone, 198 e-mail, 199 sem nome, 200 sem contato e
  # 201 a mesma pessoa da linha 2 com outro nome.
  let(:planilha) do
    pessoas = (1..195).map do |numero|
      ["Pessoa #{numero} Albuquerino", '11', format('98765-%04d', numero), numero.odd? ? "pessoa#{numero}@exemplo.com.br" : '',
       (numero % 10).zero? ? 'Padaria Bom Dia' : '', (numero % 3).zero? ? 'Campinas' : '', numero.even? ? 'Ouro' : '', "segredo-#{numero}"]
    end
    problemas = [
      ['Tadeu Problema', '11', '9876-01', '', '', '', 'Prata', ''], ['Rita Problema', '', '', 'rita.exemplo.com.br', '', '', '', ''],
      ['', '11', '98765-9199', '', '', '', '', ''], ['Helena Problema', '', '', '', '', '', '', ''],
      ['Pessoa Um Outro', '11', '98765-0001', '', '', '', '', '']
    ]
    CSV.generate do |csv|
      csv << %w[Nome DDD Celular E-mail Empresa Cidade Plano Segredo]
      (pessoas + problemas).each { |linha| csv << linha }
    end
  end

  before do
    account.enable_features!('companies')
    # As 15 primeiras pessoas da planilha já são contatos da conta, com outro nome e alguns dados próprios.
    (1..15).each do |numero|
      create(:contact, account: account, name: "Antigo #{numero}", phone_number: format('+551198765%04d', numero), email: nil,
                       additional_attributes: numero <= 5 ? { 'city' => 'Sorocaba' } : {},
                       custom_attributes: numero <= 3 ? { 'plano' => 'Antigo' } : {})
    end
    account.contacts.find_by!(name: 'Antigo 1').update!(contact_type: :customer, customer_since: desde)
  end

  def ler_planilha(importacao)
    ContactImports::Validator.new(importacao).perform
    importacao.reload
  end

  def trocar(importacao, indice, destino)
    Relacionamentos::Trazer::TrocarDestino.new(importacao, indice: indice, destino: destino).call
  end

  def antigo(numero)
    account.contacts.find_by!(name: "Antigo #{numero}")
  end

  # Um exemplo só, de propósito: é a mesma planilha do começo ao fim.
  it 'traz 180 pessoas novas, completa 15 sem sobrescrever nada e deixa de fora o que a pessoa não resolveu' do # rubocop:disable RSpec/ExampleLength
    importacao = create_contact_import(account: account, user: user, content: planilha)
    importacao.update!(options: importacao.options.merge('trazer' => {}))
    ler_planilha(importacao)

    leitura = Relacionamentos::Trazer::Leitura.new(importacao).call
    expect(leitura[:resumo]).to eq(total: 200, novas: 180, completadas: 15, comProblema: 5, juntadas: 0, entram: 195, clientes: 0)
    expect(leitura[:colunas].pluck(:nome)).to eq(%w[Nome Celular E-mail Empresa Cidade Plano Segredo])
    expect(leitura[:problemas].pluck(:linha, :tipo))
      .to eq([[197, 'telefone'], [198, 'email'], [199, 'nome'], [200, 'sem_contato'], [201, 'duplicada']])
    expect(importacao.validation_summary).to include('ddd_juntado' => 197)

    # A conferência: todas são clientes, a cidade vai para a cidade, o segredo não é guardado, um telefone é
    # consertado e uma linha é deixada de fora.
    expect(Relacionamentos::Trazer::Responder.new(importacao, 'clientes' => 'sim_todas').call).to have_attributes(erro: nil, revalida: false)
    expect(trocar(importacao, 4, 'cidade')).to have_attributes(erro: nil, revalida: false)
    expect(trocar(importacao, 6, 'nao_guardar')).to have_attributes(erro: nil, revalida: false)
    expect(Relacionamentos::Trazer::MudarLinha.new(importacao, 197).consertar(valor: '(11) 98765-9197').problema)
      .to include(estado: 'guardado', corrigido: '+5511987659197')
    expect(Relacionamentos::Trazer::MudarLinha.new(importacao, 200).deixar_de_fora.problema).to include(estado: 'deixado')
    conferencia = importacao.reload.options['trazer']
    expect(conferencia).to eq('respostas' => { 'clientes' => 'sim_todas' }, 'destinos' => { '4' => 'cidade', '6' => 'nao_guardar' },
                              'deixadas' => [200])
    expect(ContactImports::Trazer::Consertos.new(importacao).ler.keys).to eq([197])

    # Trocar um alvo lê a planilha de novo, duas vezes: a empresa vira informação e volta a ser empresa.
    [%w[informacao informacao], %w[empresa empresa]].each do |destino, esperado|
      expect(trocar(importacao, 3, destino)).to have_attributes(erro: nil, revalida: true)
      ler_planilha(importacao)

      leitura = Relacionamentos::Trazer::Leitura.new(importacao).call
      expect(leitura[:colunas][3]).to include(destino: esperado)
      expect(leitura[:resumo]).to eq(total: 200, novas: 180, completadas: 15, comProblema: 5, juntadas: 0, entram: 196, clientes: 196)
      expect(leitura[:problemas].pluck(:linha, :estado))
        .to eq([[197, 'guardado'], [198, 'aberto'], [199, 'aberto'], [200, 'deixado'], [201, 'aberto']])
      expect(leitura[:problemas].first).to include(corrigido: '+5511987659197')
      expect(importacao.options['trazer']).to eq(conferencia)
    end

    expect(Relacionamentos::Trazer::Trazer.new(importacao).call).to have_attributes(erro: nil)
    expect(importacao.reload).to have_attributes(status: 'confirmed', valid_rows: 195, invalid_rows: 5)
    # O job, como a gravação, só roda com a importação por planilha ligada na instalação.
    with_modified_env('CAMPAIGN_IMPORT_ENABLED' => 'true') { ContactImports::Trazer::FecharConferenciaJob.perform_now(importacao) }
    expect(importacao.reload).to have_attributes(status: 'queued', total_rows: 200, valid_rows: 196, invalid_rows: 4)
    CampaignImports::Importer.new(importacao).perform
    importacao.reload

    expect(importacao).to be_completed
    expect(Relacionamentos::Trazer::Andamento.new(importacao).call)
      .to eq(porcentagem: 100, situacao: 'pronto', total: 196, novas: 181, completadas: 15)
    expect(account.contacts.count).to eq(196)
    expect(account.contacts.find_by!(name: 'Tadeu Problema'))
      .to have_attributes(phone_number: '+5511987659197', custom_attributes: { 'plano' => 'Prata' })
    # As linhas que ficaram com o problema aberto e a deixada de fora não entraram.
    expect(account.contacts.where(name: ['Rita Problema', 'Helena Problema', 'Pessoa Um Outro'])).to be_empty
    expect(account.contacts.where(phone_number: '+5511987659199')).to be_empty

    # Quem já existia é completado, nunca sobrescrito.
    expect((1..15).map { |numero| antigo(numero).email }).to eq((1..15).map { |numero| numero.odd? ? "pessoa#{numero}@exemplo.com.br" : nil })
    expect((1..15).map { |numero| antigo(numero).additional_attributes['city'] })
      .to eq((['Sorocaba'] * 5) + ['Campinas', nil, nil, 'Campinas', nil, nil, 'Campinas', nil, nil, 'Campinas'])
    expect((1..15).map { |numero| antigo(numero).custom_attributes['plano'] })
      .to eq((['Antigo'] * 3) + ['Ouro', nil, 'Ouro', nil, 'Ouro', nil, 'Ouro', nil, 'Ouro', nil, 'Ouro', nil])
    expect(account.contacts.where("name LIKE 'Pessoa%'").count).to eq(180)

    # "Sim, todas": todo mundo da lista vira cliente; quem já era fica com a data que tinha.
    expect(account.contacts.pluck(:contact_type).uniq).to eq(['customer'])
    expect(antigo(1).customer_since).to eq(desde)
    expect(antigo(2).customer_since).to be > desde

    # A cidade foi para a cidade; o segredo não virou campo nem valor; o plano virou a única informação.
    expect(account.contacts.find_by!(name: 'Pessoa 30 Albuquerino')).to have_attributes(
      phone_number: '+5511987650030', email: nil, custom_attributes: { 'plano' => 'Ouro' }, additional_attributes: include('city' => 'Campinas')
    )
    expect(account.custom_attribute_definitions.pluck(:attribute_key)).to eq(['plano'])
    expect(account.contacts.pluck(:custom_attributes).flat_map(&:keys).uniq).to eq(['plano'])
    expect(account.contacts.pluck(:custom_attributes).to_json).not_to include('segredo')
    expect(account.companies.find_by!(name: 'Padaria Bom Dia').contacts.count).to eq(19)
  end
end
