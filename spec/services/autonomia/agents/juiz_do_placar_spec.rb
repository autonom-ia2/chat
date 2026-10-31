require 'rails_helper'

# #1431 (F0) — o juiz do placar: mesma saída do juiz do autoteste (veredito por índice, válido para a origem), com a
# régua escrita do placar e os trechos que o agente usou. Saída que não fecha ou provedor fora: nil.
RSpec.describe Autonomia::Agents::JuizDoPlacar do
  include_context 'with material do agente'

  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:itens) do
    [{ 'origem' => 'material', 'pergunta' => 'Preço?', 'esperado' => 'R$ 25', 'resposta' => 'R$ 25', 'equipe' => false,
       'trechos' => ['Combo da casa: R$ 25, com refrigerante.'] },
     { 'origem' => 'fora', 'pergunta' => 'Bolo?', 'resposta' => 'Não sei.', 'equipe' => true, 'trechos' => [] }]
  end

  before do
    credencial_de_teste
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def juiz_diz(*resultados)
    allow(cliente).to receive(:create).and_return(resposta_do_modelo(resultados: resultados))
  end

  def julgar
    described_class.new(account: account).julgar(itens)
  end

  it 'gives one verdict per item, in index order' do
    juiz_diz({ indice: 1, veredito: 'recusou' }, { indice: 0, veredito: 'certo' })

    expect(julgar).to eq(%w[certo recusou])
  end

  it 'returns nil for a verdict of the other origin or a missing item', :aggregate_failures do
    juiz_diz({ indice: 0, veredito: 'recusou' }, { indice: 1, veredito: 'recusou' })
    expect(julgar).to be_nil

    juiz_diz({ indice: 0, veredito: 'certo' })
    expect(julgar).to be_nil
  end

  it 'returns nil when the provider fails' do
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    expect(julgar).to be_nil
  end

  it 'sends the written rule and the passages the agent used, to a model other than the agent' do
    juiz_diz({ indice: 0, veredito: 'certo' }, { indice: 1, veredito: 'recusou' })

    julgar

    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:model]).not_to eq(Autonomia::Agents::Config::ANSWERER_MODEL)
      expect(kwargs[:instructions]).to include('detalhe secundario', 'outro fato')
      expect(kwargs[:input].first[:content].first[:text]).to include('"trechos_que_o_agente_usou"', 'Combo da casa: R$ 25')
    end
  end
end
