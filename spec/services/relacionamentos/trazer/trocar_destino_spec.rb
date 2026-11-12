require 'rails_helper'

# #2896 — a troca do destino de uma coluna na conferência de "Trazer minha lista": o que lê a planilha de novo, o que
# vale na hora, o que é recusado, e que a coluna que não é para guardar não deixa valor nas linhas.
RSpec.describe Relacionamentos::Trazer::TrocarDestino, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:planilha) do
    <<~CSV
      Nome;Celular;Fone 2;Cidade;Segredo
      Ana Albuquerino;11987650001;11987650091;Campinas;sigilo-um
      Bruno Brandolim;11987650002;11987650092;Santos;sigilo-dois
    CSV
  end

  def lida(texto = planilha)
    importacao = create_contact_import(account: account, user: user, content: texto)
    importacao.update!(options: importacao.options.merge('trazer' => {}))
    ler_de_novo(importacao)
  end

  def ler_de_novo(importacao)
    ContactImports::Validator.new(importacao).perform
    importacao.reload
  end

  def trocar(importacao, indice, destino)
    described_class.new(importacao, indice: indice, destino: destino).call
  end

  def valores_das_linhas(importacao)
    importacao.campaign_import_rows.order(:row_number).pluck(:extra_values)
  end

  it 'recusa, sem mudar nada, o pedido que não dá para atender' do
    importacao = lida

    expect(trocar(importacao, '9', 'telefone')).to have_attributes(erro: 'coluna_desconhecida')
    expect(trocar(importacao, '-1', 'telefone')).to have_attributes(erro: 'coluna_desconhecida')
    expect(trocar(importacao, 'abc', 'telefone')).to have_attributes(erro: 'coluna_desconhecida')
    expect(trocar(importacao, nil, 'telefone')).to have_attributes(erro: 'coluna_desconhecida')
    expect(trocar(importacao, '4', 'cidade')).to have_attributes(erro: 'destino_desconhecido')
    expect(trocar(importacao, '4', nil)).to have_attributes(erro: 'destino_desconhecido')
    expect(importacao.reload).to have_attributes(status: 'ready_to_confirm', options: include('trazer' => {}))
    expect(trocar(importacao, '2', 'telefone')).to have_attributes(erro: nil, revalida: true)
    expect(trocar(importacao, '4', 'nao_guardar')).to have_attributes(erro: 'leitura_nao_pronta')
    expect(valores_das_linhas(importacao)).to all(include('Segredo'))
  end

  it 'recusa tirar a última coluna de telefone ou e-mail' do
    importacao = lida("Nome;Celular;Cidade\nAna Albuquerino;11987650001;Campinas\n")

    %w[informacao nao_guardar nome empresa].each do |destino|
      expect(trocar(importacao, '1', destino)).to have_attributes(erro: 'sem_contato', revalida: nil), destino
    end
    expect(importacao.reload).to have_attributes(status: 'ready_to_confirm', options: include('trazer' => {}))
    expect(importacao.schema_resolution).not_to have_key('manual_mapping')
  end

  it 'lê o índice da coluna em base dez' do
    onze = "Nome;Celular;C2;C3;C4;C5;C6;C7;C8;C9;C10\nAna Albuquerino;11987650001;a;b;c;d;e;f;oitava;h;decima\n"
    importacao = lida(onze)

    expect(trocar(importacao, '010', 'nao_guardar')).to have_attributes(erro: nil, revalida: false)

    expect(importacao.reload.options.dig('trazer', 'destinos')).to eq('10' => 'nao_guardar')
    expect(valores_das_linhas(importacao).first).to include('C8' => 'oitava')
    expect(valores_das_linhas(importacao).first).not_to have_key('C10')
  end

  it 'vê, sob a trava, o estado que outro pedido acabou de gravar' do
    importacao = lida
    CampaignImport.find(importacao.id).update!(status: :validating)

    expect(importacao).to be_ready_to_confirm
    expect(trocar(importacao, '4', 'nao_guardar')).to have_attributes(erro: 'leitura_nao_pronta')
    expect(valores_das_linhas(importacao)).to all(include('Segredo'))
  end

  it 'não perde a escolha de outro pedido que chegou no meio' do
    importacao = lida
    outro_pedido = CampaignImport.find(importacao.id)

    trocar(outro_pedido, '3', 'nao_guardar')
    trocar(importacao, '4', 'nao_guardar')

    expect(importacao.reload.options.dig('trazer', 'destinos')).to eq('3' => 'nao_guardar', '4' => 'nao_guardar')
    expect(valores_das_linhas(importacao)).to eq([{ 'Fone 2' => '11987650091' }, { 'Fone 2' => '11987650092' }])
  end

  describe 'coluna que não é para guardar' do
    it 'apaga na hora a chave e o valor de todas as linhas, e só os dela' do
      importacao = lida
      outra = lida

      expect(trocar(importacao, '4', 'nao_guardar')).to have_attributes(erro: nil, revalida: false)

      expect(importacao.reload).to be_ready_to_confirm
      expect(valores_das_linhas(importacao)).to eq([{ 'Fone 2' => '11987650091', 'Cidade' => 'Campinas' },
                                                    { 'Fone 2' => '11987650092', 'Cidade' => 'Santos' }])
      expect(importacao.campaign_import_rows.map(&:attributes).to_json).not_to include('Segredo', 'sigilo-um', 'sigilo-dois')
      expect(valores_das_linhas(outra)).to all(include('Segredo'))
    end

    it 'não faz nada quando a coluna já não era para guardar' do
      importacao = lida
      trocar(importacao, '4', 'nao_guardar')

      expect(trocar(importacao, '4', 'nao_guardar')).to have_attributes(erro: nil, revalida: false)
      expect(importacao.reload).to be_ready_to_confirm
    end

    it 'lê de novo quando ela volta a ser informação, com as mesmas colunas, e o valor volta do arquivo' do
      importacao = lida
      trocar(importacao, '4', 'nao_guardar')

      expect(trocar(importacao, '4', 'informacao')).to have_attributes(erro: nil, revalida: true)

      expect(importacao.reload).to be_validating
      expect(importacao.options['trazer']).to eq('destinos' => {})
      expect(importacao.schema_resolution['manual_mapping']).to eq('name' => 0, 'phone' => 1, 'email' => nil, 'company' => nil)
      expect(valores_das_linhas(ler_de_novo(importacao))).to all(include('Segredo'))
    end
  end

  it 'aguenta duas trocas seguidas: a coluna que entra num alvo e, lida de novo, a que saiu dele e não é para guardar' do
    importacao = lida

    expect(trocar(importacao, '2', 'telefone')).to have_attributes(erro: nil, revalida: true)
    expect(importacao.reload.schema_resolution['manual_mapping']).to eq('name' => 0, 'phone' => 2, 'email' => nil, 'company' => nil)
    ler_de_novo(importacao)
    expect(valores_das_linhas(importacao).first).to eq('Celular' => '11987650001', 'Cidade' => 'Campinas', 'Segredo' => 'sigilo-um')

    expect(trocar(importacao, '1', 'nao_guardar')).to have_attributes(erro: nil, revalida: false)

    expect(importacao.reload.options.dig('trazer', 'destinos')).to eq('1' => 'nao_guardar')
    expect(valores_das_linhas(importacao)).to eq(
      [{ 'Cidade' => 'Campinas', 'Segredo' => 'sigilo-um' }, { 'Cidade' => 'Santos', 'Segredo' => 'sigilo-dois' }]
    )

    expect(trocar(importacao, '1', 'telefone')).to have_attributes(erro: nil, revalida: true)
    expect(importacao.reload.options.dig('trazer', 'destinos')).to eq({})
    expect(valores_das_linhas(ler_de_novo(importacao)).first).to eq('Fone 2' => '11987650091', 'Cidade' => 'Campinas', 'Segredo' => 'sigilo-um')
  end

  it 'mantém fora das linhas, em toda leitura nova, a coluna que não é para guardar' do
    importacao = lida
    trocar(importacao, '4', 'nao_guardar')

    trocar(importacao, '2', 'telefone')

    expect(valores_das_linhas(ler_de_novo(importacao)))
      .to eq([{ 'Celular' => '11987650001', 'Cidade' => 'Campinas' }, { 'Celular' => '11987650002', 'Cidade' => 'Santos' }])
  end
end
