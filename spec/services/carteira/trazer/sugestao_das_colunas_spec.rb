require 'rails_helper'

# E4 (#2897): qual coluna da planilha é cada destino do seguro. Quem decide é o modelo, com saída fechada; o modelo nunca
# é chamado de verdade nos specs: a resposta dele é a que o exemplo põe (WebMock). Dados fictícios.
RSpec.describe Carteira::Trazer::SugestaoDasColunas, :aggregate_failures do
  let(:account) { create(:account) }
  let(:sem_esperar) { TypesafeAi::Client.new(sleeper: ->(_segundos) {}) }
  # Colunas 0 a 2 são nome, celular e e-mail (alvos); as outras são as que o modelo vê.
  let(:titulos) { { 3 => 'Apólice', 4 => 'Cia', 5 => 'Ramo', 6 => 'Vig. final', 7 => '11987650009', 8 => 'Obs' } }
  let(:leitura) do
    CampaignImports::SpreadsheetReader::Result.new(
      extra_columns: titulos.map { |indice, titulo| { 'index' => indice, 'key' => titulo } },
      resolution: { 'columns' => titulos.map { |indice, titulo| { 'index' => indice, 'header' => titulo, 'example_masked' => 'AA-000000' } } }
    )
  end

  before { enable_audience_jev }

  def modelo_responde(model: 'jev-1.13.0', status: 200, **respostas)
    pedidos = []
    stub_request(:post, AudienceJevHelpers::JEV_URL).to_return do |request|
      pedidos << JSON.parse(request.body)
      { status: status, body: { model: model, answers: respostas, usage: { input_tokens: 300, output_tokens: 20 } }.to_json }
    end
    pedidos
  end

  def escolha(coluna, certeza = 0.95)
    { type: 'choice', choice: coluna, confidence: certeza }
  end

  def sugerir(**opcoes)
    described_class.new(account, leitura, **opcoes).call
  end

  it 'pergunta cada destino do seguro numa chamada só, com a saída fechada nas colunas e "não se aplica", sem valor de célula' do
    pedidos = modelo_responde(seguro_numero: escolha('column_3'), seguro_seguradora: escolha('column_4'), seguro_tipo: escolha('column_5'),
                              seguro_termina: escolha('column_6'), seguro_comeca: escolha('none'), seguro_valor: escolha('none'))

    expect(sugerir).to eq('seguro_numero' => 3, 'seguro_seguradora' => 4, 'seguro_tipo' => 5, 'seguro_termina' => 6)

    pedido = pedidos.sole
    expect(pedido.keys).to match_array(%w[state model questions])
    expect(pedido['questions'].keys).to eq(Carteira::Trazer::ColunasDeSeguro::DESTINOS)
    expect(pedido['questions'].values.pluck('type').uniq).to eq(%w[choice])
    expect(pedido['questions']['seguro_bem']['criteria'].keys).to eq(%w[column_3 column_4 column_5 column_6 column_7 column_8 none])
    expect(pedido['state']['columns']['column_3']).to eq('header' => 'Apólice', 'format' => 'AA-000000')
    # O título que parece telefone (planilha sem linha de título) não sai inteiro.
    expect(pedido.to_json).not_to include('11987650009')
    expect(Crm::AiUsageEvent.where(feature: 'carteira_colunas').pluck(:account_id, :model)).to eq([[account.id, 'jev-1.13.0']])
  end

  it 'certeza baixa, coluna fora da lista, resposta de outro tipo e a mesma coluna para dois destinos ficam sem sugestão' do
    modelo_responde(seguro_numero: escolha('column_3', 0.5), seguro_seguradora: escolha('column_1'), seguro_tipo: { type: 'noul', noul: 0.9 },
                    seguro_termina: escolha('column_6'), seguro_comeca: escolha('column_6'), seguro_bem: escolha('column_8'))

    expect(sugerir).to eq('seguro_bem' => 8)
  end

  it 'o modelo que respondeu "não se aplica" para tudo devolve uma sugestão vazia, que não é perguntada de novo' do
    modelo_responde(**Carteira::Trazer::ColunasDeSeguro::DESTINOS.to_h { |destino| [destino.to_sym, escolha('none')] })

    expect(sugerir).to eq({})
  end

  it 'o modelo fora do ar, ou a resposta de outro modelo, não devolve sugestão e não trava: só a classe do erro vai ao log' do
    allow(Rails.logger).to receive(:warn)
    modelo_responde(status: 500)
    fora_do_ar = sugerir(client: sem_esperar)
    modelo_responde(model: 'outro-modelo', seguro_numero: escolha('column_3'))
    de_outro_modelo = sugerir(client: sem_esperar)

    expect([fora_do_ar, de_outro_modelo]).to eq([nil, nil])
    expect(Rails.logger).to have_received(:warn).with('[Carteira::Trazer::SugestaoDasColunas] sem resposta: TypesafeAi::Client::Error').once
  end

  it 'desligado na instalação, ou sem coluna além das de contato, não chama o modelo' do
    sem_colunas = CampaignImports::SpreadsheetReader::Result.new(extra_columns: [], resolution: { 'columns' => [] })

    expect([sugerir(ligado: false), described_class.new(account, sem_colunas).call]).to eq([nil, nil])
    expect(a_request(:post, AudienceJevHelpers::JEV_URL)).not_to have_been_made
  end
end
