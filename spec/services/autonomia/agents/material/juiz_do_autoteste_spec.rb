require 'rails_helper'

# #1426 (tema 4b) — o juiz do autoteste: veredito por índice, válido para a origem (do material: certo/errado; de fora:
# recusou/inventou). Saída que não fecha: nil (a rodada fica "não terminou", nunca um veredito inventado).
RSpec.describe Autonomia::Agents::Material::JuizDoAutoteste do
  include_context 'with material do agente'

  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:itens) do
    [{ 'origem' => 'material', 'pergunta' => 'Preço?', 'esperado' => 'R$ 25', 'resposta' => 'R$ 25', 'equipe' => false },
     { 'origem' => 'fora', 'pergunta' => 'Bolo?', 'resposta' => nil, 'equipe' => true }]
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

  it 'um veredito por item, na ordem dos índices' do
    juiz_diz({ indice: 1, veredito: 'recusou' }, { indice: 0, veredito: 'certo' })

    expect(julgar).to eq(%w[certo recusou])
  end

  it 'veredito de outra origem (recusou numa pergunta do material) ou item faltando: nil', :aggregate_failures do
    juiz_diz({ indice: 0, veredito: 'recusou' }, { indice: 1, veredito: 'recusou' })
    expect(julgar).to be_nil

    juiz_diz({ indice: 0, veredito: 'certo' })
    expect(julgar).to be_nil
  end

  it 'manda origem, o que o material responde, a resposta e a passagem para a equipe; outro modelo que o do agente' do
    juiz_diz({ indice: 0, veredito: 'errado' }, { indice: 1, veredito: 'inventou' })

    julgar

    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:model]).not_to eq(Autonomia::Agents::Config::ANSWERER_MODEL)
      expect(kwargs[:input].first[:content].first[:text]).to include('"o_material_responde": "R$ 25"', '"passa_para_equipe": true',
                                                                     '"origem": "fora"')
    end
  end
end
