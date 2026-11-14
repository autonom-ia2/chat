require 'rails_helper'

# E4 (#2897): o ramo de seguro como a corretora escreve vira um dos cinco tipos, e quem decide é o modelo. O modelo nunca
# é chamado de verdade nos specs: a resposta dele é a que o exemplo põe (WebMock).
RSpec.describe Carteira::Trazer::PerguntaDoRamo, :aggregate_failures do
  let(:account) { create(:account) }
  let(:sem_esperar) { TypesafeAi::Client.new(sleeper: ->(_segundos) {}) }

  before { enable_audience_jev }

  def modelo_responde(model: 'jev-1.13.0', status: 200, **respostas)
    pedidos = []
    stub_request(:post, AudienceJevHelpers::JEV_URL).to_return do |request|
      pedidos << JSON.parse(request.body)
      { status: status, body: { model: model, answers: respostas, usage: { input_tokens: 120, output_tokens: 8 } }.to_json }
    end
    pedidos
  end

  def escolha(tipo, certeza = 0.95)
    { type: 'choice', choice: tipo, confidence: certeza }
  end

  it 'pergunta os ramos numa chamada só, com a saída fechada nos cinco tipos e "não sei", e manda só o texto do ramo' do
    pedidos = modelo_responde(ramo_0: escolha('auto'), ramo_1: escolha('vida'))
    pergunta = described_class.new(account: account)

    expect(pergunta.call(['automóvel', 'vg/apc'])).to eq('automóvel' => 'auto', 'vg/apc' => 'vida')

    pedido = pedidos.sole
    expect(pedido.keys).to match_array(%w[state model questions])
    expect(pedido['state'].keys).to eq(%w[task lines_of_business])
    expect(pedido['state']['lines_of_business']).to eq(['automóvel', 'vg/apc'])
    expect(pedido['questions'].keys).to eq(%w[ramo_0 ramo_1])
    expect(pedido['questions'].values.pluck('type')).to eq(%w[choice choice])
    expect(pedido['questions']['ramo_1']['criteria'].keys).to eq(Carteira::Apolice::TIPOS + ['nao_sei'])
    expect(pergunta.uso).to eq(chamadas: 1, input_tokens: 120, output_tokens: 8)
    expect(Crm::AiUsageEvent.where(feature: 'carteira_ramo').pluck(:account_id, :model)).to eq([[account.id, 'jev-1.13.0']])
  end

  it '"não sei", resposta fora da lista, certeza baixa e ramo sem resposta viram "outro"' do
    modelo_responde(ramo_0: escolha('nao_sei'), ramo_1: escolha('moto'), ramo_2: escolha('auto', 0.5), ramo_4: { type: 'noul', noul: 0.9 })

    tipos = described_class.new(account: account).call(%w[diversos motocicleta aut. massificados re])

    expect(tipos).to eq('diversos' => 'outro', 'motocicleta' => 'outro', 'aut.' => 'outro', 'massificados' => 'outro', 're' => 'outro')
  end

  it 'o modelo fora do ar, ou a resposta de outro modelo, não devolve nada e não trava: só a classe do erro vai ao log' do
    allow(Rails.logger).to receive(:warn)
    modelo_responde(status: 500)
    fora_do_ar = described_class.new(account: account, client: sem_esperar).call(['automóvel'])
    modelo_responde(model: 'outro-modelo', ramo_0: escolha('auto'))
    de_outro_modelo = described_class.new(account: account, client: sem_esperar).call(['automóvel'])

    expect([fora_do_ar, de_outro_modelo]).to eq([{}, {}])
    expect(Rails.logger).to have_received(:warn).with('[Carteira::Trazer::PerguntaDoRamo] sem resposta: TypesafeAi::Client::Error').once
  end

  it 'desligado na instalação, não chama o modelo' do
    pedidos = modelo_responde(ramo_0: escolha('auto'))

    expect(described_class.new(account: account, ligado: false).call(['automóvel'])).to eq({})
    expect(pedidos).to be_empty
  end

  it 'manda no máximo 40 ramos por chamada' do
    pedidos = modelo_responde(ramo_0: escolha('vida'))
    pergunta = described_class.new(account: account)

    tipos = pergunta.call((1..41).map { |numero| "ramo #{numero}" })

    expect(pedidos.map { |pedido| pedido['questions'].size }).to eq([40, 1])
    expect([tipos.size, tipos['ramo 1'], tipos['ramo 2'], tipos['ramo 41'], pergunta.uso[:chamadas]]).to eq([41, 'vida', 'outro', 'vida', 2])
  end
end
