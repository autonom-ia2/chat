require 'rails_helper'

# #1430, revisão final: a resposta 2xx da consulta em segundo plano mascara SÓ as credenciais do cadastro, e só o
# valor inteiro. O "ativo" de `?status=ativo` não vira "IN[oculto]" em "INATIVO"; a versão de um cabeçalho comum e o
# limite da query chegam inteiros. As credenciais (Authorization, X-Api-Key, ?token=) continuam ocultas no 2xx e no 4xx.
RSpec.describe Autonomia::Agents::Tools::SegredosDaChamada do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Clientes', slug: 'buscar_clientes',
      endpoint_url: 'https://erp.exemplo.test/clientes?status=ativo&limite=1000&token=tokQuery77abc',
      headers_config: [
        { key: 'Authorization', value: 'Bearer bearerSecreto99', secret: true },
        { key: 'X-Api-Key', value: 'chaveDaApi-123', secret: true },
        { key: 'X-Api-Version', value: '2024-01', secret: false }
      ],
      param_schema: [{ name: 'q', type: 'string', description: 'Busca', required: true }]
    )
  end
  let(:resposta) do
    '{"situacao":"INATIVO","saldo":"1000,00","versao":"2024-01","eco":"bearerSecreto99","chave":"chaveDaApi-123",' \
      '"auth":"Bearer bearerSecreto99","tk":"tokQuery77abc","parecido":"xchaveDaApi-123x"}'
  end

  def executor
    Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: { 'q' => 'ana' }, chave: 'k' * 64, higienizar: true)
  end

  def responde(corpo)
    allow(SafeFetch).to receive(:fetch) do |_url, **_opcoes, &bloco|
      arquivo = Tempfile.new('resposta')
      arquivo.write(corpo)
      arquivo.rewind
      bloco.call(SafeFetch::Result.new(tempfile: arquivo, filename: 'r.json', content_type: 'application/json'))
    end
  end

  it 'no 2xx, o dado do negocio chega inteiro: INATIVO, 1000,00 e a versao do cabecalho comum' do
    responde(resposta)

    dado = JSON.parse(executor.call)

    expect(dado).to include('situacao' => 'INATIVO', 'saldo' => '1000,00', 'versao' => '2024-01')
  end

  it 'no 2xx, Authorization, X-Api-Key e ?token= continuam ocultos, inteiros' do
    responde(resposta)

    dado = JSON.parse(executor.call)

    expect(dado).to include('eco' => '[oculto]', 'chave' => '[oculto]', 'auth' => '[oculto]', 'tk' => '[oculto]')
  end

  it 'no 2xx, so o valor inteiro: o segredo colado a outra palavra ou com outras maiusculas nao e um pedaco a trocar' do
    responde('{"parecido":"xchaveDaApi-123x","caixa":"CHAVEDAAPI-123"}')

    expect(JSON.parse(executor.call)).to eq('parecido' => 'xchaveDaApi-123x', 'caixa' => 'CHAVEDAAPI-123')
  end

  it 'no 4xx, Authorization, X-Api-Key e ?token= continuam ocultos' do
    corpo = 'recusado: Bearer bearerSecreto99 chave chaveDaApi-123 token tokQuery77abc'
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('422 Unprocessable', status: 422, body_excerpt: corpo))

    expect { executor.call }.to raise_error(Autonomia::Agents::Tools::HttpExecutor::Error) do |erro|
      expect(erro.trecho).not_to include('bearerSecreto99', 'chaveDaApi-123', 'tokQuery77abc')
      expect(erro.trecho).to include('[oculto]')
    end
  end

  describe 'cavecrew 3: segredo e o que o cadastro marca, nao o formato nem um pedaco do nome' do
    let(:uuid) { '3f2b8c1e-9a4d-4e7b-8c21-5d6f7a8b9c0d' }
    let(:tool) do
      Autonomia::Agents::Tool.create!(
        account: account, agent: agent, name: 'Pedidos', slug: 'buscar_pedidos',
        endpoint_url: "https://erp.exemplo.test/pedidos?pedido=#{uuid}&keyword=boleto&author=maria&api_key=chaveQuery55",
        headers_config: [
          { key: 'X-Cliente', value: 'valorGuardado-777', secret: true },
          { key: 'X-Keyword', value: 'campanhaPublica', secret: false }
        ],
        param_schema: [{ name: 'q', type: 'string', description: 'Busca', required: true }]
      )
    end

    it 'UUID da query, keyword e author chegam inteiros; o cabecalho marcado secret e a api_key saem' do
      responde({ pedido: uuid, keyword: 'boleto', author: 'maria', campanha: 'campanhaPublica',
                 eco: 'valorGuardado-777', chave: 'chaveQuery55' }.to_json)

      dado = JSON.parse(executor.call)

      expect(dado).to include('pedido' => uuid, 'keyword' => 'boleto', 'author' => 'maria', 'campanha' => 'campanhaPublica')
      expect(dado).to include('eco' => '[oculto]', 'chave' => '[oculto]')
    end
  end
end
