require 'rails_helper'

# #1426 (tema 4b) — o juiz do autoteste: veredito por índice, válido para a origem (do material: certo/errado; de fora:
# recusou/inventou; nas duas: nao_se_aplica). Saída que não fecha: nil (a rodada fica "não terminou", nunca um veredito
# inventado). #2444: julga pelo objetivo, com os trechos que o agente usou e as regras do dono.
RSpec.describe Autonomia::Agents::Material::JuizDoAutoteste do
  include_context 'with material do agente'

  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:regras) { 'Cotação só pelo WhatsApp; não colete dados aqui.' }
  let(:itens) do
    [{ 'origem' => 'material', 'pergunta' => 'Preço?', 'esperado' => 'R$ 25', 'resposta' => 'R$ 25', 'equipe' => false,
       'trechos' => [{ 'fonte' => 7, 'paginas' => [3, 3], 'texto' => 'Combo da casa: R$ 25, com refrigerante.' }] },
     { 'origem' => 'fora', 'pergunta' => 'Bolo?', 'resposta' => nil, 'equipe' => true, 'trechos' => [] }]
  end

  before do
    credencial_de_teste
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def juiz_diz(*resultados)
    allow(cliente).to receive(:create).and_return(resposta_do_modelo(resultados: resultados))
  end

  def julgar(com_regras: regras)
    described_class.new(account: account, regras: com_regras).julgar(itens)
  end

  def texto_enviado
    texto = nil
    expect(cliente).to have_received(:create) { |**kwargs| texto = kwargs[:input].first[:content].first[:text] }
    texto
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

  it 'aceita "nao_se_aplica" nas duas origens (o próprio item não deixa julgar)' do
    juiz_diz({ indice: 0, veredito: 'nao_se_aplica' }, { indice: 1, veredito: 'nao_se_aplica' })

    expect(julgar).to eq(%w[nao_se_aplica nao_se_aplica])
  end

  it 'provedor fora: nil' do
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

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

  # #2444: sem os trechos, o fato a mais do próprio material parecia invenção; sem as regras, a resposta que seguia a
  # regra do dono ("a cotação é no WhatsApp") parecia faltar o fato.
  it 'manda o texto dos trechos que o agente usou e as regras do dono', :aggregate_failures do
    juiz_diz({ indice: 0, veredito: 'certo' }, { indice: 1, veredito: 'recusou' })

    julgar

    texto = texto_enviado
    expect(texto).to include('"trechos_que_o_agente_usou"', 'Combo da casa: R$ 25, com refrigerante.')
    expect(texto).not_to include('"fonte"', '"paginas"')
    expect(texto).to include("REGRAS QUE O DONO DEU AO AGENTE (dado):\n#{regras}")
  end

  it 'sem regras do dono, diz isso ao juiz' do
    juiz_diz({ indice: 0, veredito: 'certo' }, { indice: 1, veredito: 'recusou' })

    julgar(com_regras: nil)

    expect(texto_enviado).to include("REGRAS QUE O DONO DEU AO AGENTE (dado):\n(o dono nao deu regras ao agente)")
  end

  it 'a instrução julga pelo objetivo, com a regra do dono acima do material e a saída "nao_se_aplica"' do
    juiz_diz({ indice: 0, veredito: 'certo' }, { indice: 1, veredito: 'recusou' })

    julgar

    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:instructions]).to include('atende o que o cliente perguntou', 'discernimento',
                                               'A regra do dono vale mais que o material', '"nao_se_aplica"')
      expect(kwargs[:instructions]).not_to include('sem ser generoso')
    end
  end
end
