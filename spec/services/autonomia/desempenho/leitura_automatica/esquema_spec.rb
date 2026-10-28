require 'rails_helper'

# O esquema da resposta do leitor (#2301): listas fechadas do catálogo da ficha, nunca do código. Loja inventada.
RSpec.describe Autonomia::Desempenho::LeituraAutomatica::Esquema do
  let(:account) { create(:account) }
  let(:ficha) { ficha_da_loja!(account, sujeito_id: 7) }
  let(:esquema) { described_class.new(ficha) }

  def propriedades = esquema.json.dig('properties', 'procuras', 'items', 'properties')

  def procura(campos = {})
    { 'conversa' => 1, 'procura' => 1, 'inicio' => '10-21 13:00', 'fim' => '10-21 13:01', 'quem' => 'cliente', 'pedido' => 'duvida',
      'tema' => 'troca', 'marcos' => [], 'resultado' => 'duvida_resolvida', 'motivos' => [], 'perda_evitavel' => false,
      'por_que' => '', 'qualidade' => 'acertou', 'regras' => [], 'teve_pessoa' => false, 'precisava_pessoa' => false,
      'origem' => 'desconhecida', 'resumo' => 'Quis trocar.' }.merge(campos)
  end

  it 'é estrito, com as listas fechadas do catálogo da ficha' do
    item = esquema.json.dig('properties', 'procuras', 'items')

    expect(item['additionalProperties']).to be(false)
    expect(item['required']).to eq(item['properties'].keys)
    listas = { 'tema' => propriedades['tema']['enum'], 'marcos' => propriedades['marcos']['items']['enum'],
               'resultado' => propriedades['resultado']['enum'], 'regras' => propriedades['regras']['items']['enum'],
               'pedido' => propriedades['pedido']['enum'], 'qualidade' => propriedades['qualidade']['enum'] }
    expect(listas).to eq('tema' => %w[entrega troca], 'marcos' => %w[orcamento_enviado pagou],
                         'resultado' => %w[comprou vai_pensar duvida_resolvida], 'regras' => ['R-PRAZO'], 'pedido' => %w[comprar duvida],
                         'qualidade' => %w[acertou erro_leve erro_grave nao_atuou])
    expect(propriedades).not_to have_key('teste')
    expect(propriedades['inicio']['description']).to eq('MM-DD HH:MM em UTC, igual ao horário da linha da transcrição')
  end

  it 'pede o campo teste só com configuracao.leitura.com_teste' do
    ficha.update!(chave_de_leitura: 'Marque `teste` quando for teste da equipe.')
    expect(propriedades).not_to have_key('teste')

    ficha.update!(configuracao: ficha.configuracao.merge('leitura' => { 'com_teste' => true }))

    expect(described_class.new(ficha).json.dig('properties', 'procuras', 'items', 'properties', 'teste')).to eq('type' => 'boolean')
  end

  it 'troca o nome de um papel e acrescenta extras pela ficha, e o corte com faixas vira número' do
    configuracao = ficha.configuracao.merge(
      'leitura' => { 'campos' => { 'quem' => 'quem_e' }, 'extras' => { 'sentimento' => { 'type' => 'string' } } },
      'cortes' => ficha.configuracao['cortes'] + [{ 'id' => 'itens', 'nome' => 'Itens', 'base' => 'compra', 'campo' => 'itens',
                                                    'faixas' => [[1, 1, '1 item'], [2, nil, '2 ou mais']] }]
    )
    ficha.update!(configuracao: configuracao)

    expect(propriedades.keys).to include('quem_e', 'sentimento', 'itens')
    expect(propriedades).not_to have_key('quem')
    expect(propriedades['itens']).to eq('type' => %w[integer null])
    conferida = esquema.procuras('procuras' => [procura('quem_e' => 'cliente', 'itens' => 3, 'sentimento' => 'bom')]).first
    expect(esquema.cortes(conferida)).to eq('pedido' => 'duvida', 'itens' => '2_mais')
    expect(esquema.cortes(conferida.merge('itens' => nil))).to eq('pedido' => 'duvida', 'itens' => 'sem_info')
  end

  it 'recusa id fora do catálogo, lista vazia e resposta sem a lista' do
    invalida = Autonomia::Desempenho::LeituraAutomatica::Esquema::Invalida

    expect { esquema.procuras('procuras' => [procura('tema' => 'inventado')]) }.to raise_error(invalida)
    expect { esquema.procuras('procuras' => [procura('marcos' => ['inventado'])]) }.to raise_error(invalida)
    expect { esquema.procuras('procuras' => []) }.to raise_error(invalida)
    expect { esquema.procuras('outra' => 1) }.to raise_error(invalida)
    expect(esquema.procuras('procuras' => [procura]).first).to include('tema' => 'troca', 'pedido' => 'duvida')
  end
end
