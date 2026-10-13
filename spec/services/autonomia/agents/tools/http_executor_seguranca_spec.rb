require 'rails_helper'

# #1425 — segurança da ferramenta HTTP. Cada caso aqui passa pelo SafeFetch de verdade (WebMock na
# borda), e não por um dublê dele: o que se quer provar é o que SAI pela rede.
RSpec.describe Autonomia::Agents::Tools::HttpExecutor do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end
  let(:endpoint) { 'https://api.loja.test/estoque/busca' }
  let(:body_template) { '{"q":"{{q}}","limit":5}' }
  let(:headers_config) do
    [
      { key: 'content-type', value: 'application/json', secret: false },
      { key: 'x-api-key', value: 'chave-muito-secreta-123', secret: true }
    ]
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Busca', slug: 'buscar_estoque',
      endpoint_url: endpoint, headers_config: headers_config,
      request_body_template: body_template,
      param_schema: [
        { name: 'q', type: 'string', description: 'Busca', required: true },
        { name: 'qtd', type: 'integer', description: 'Quantidade', required: false },
        { name: 'token', type: 'string', description: 'Token', required: false }
      ]
    )
  end
  let(:enviados) { [] }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('api.loja.test').and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses).with('outro.test').and_return(['93.184.216.35'])
  end

  def responder_ok(corpo = '{"ok":true}')
    stub_request(:post, endpoint).to_return do |request|
      enviados << request
      { status: 200, body: corpo, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def executar(params)
    described_class.new(tool: tool, params: params).call
  end

  describe 'corpo JSON (item 1)' do
    it 'keeps an injection attempt as plain text, without a new key' do
      responder_ok

      executar(q: 'x","admin":true,"y":"')

      corpo = JSON.parse(enviados.last.body)
      expect(corpo.keys).to eq(%w[q limit])
      expect(corpo['q']).to eq('x","admin":true,"y":"')
    end

    it 'turns quotes, backslash and line breaks into valid JSON with the same text' do
      responder_ok
      texto = "pastilha \"titan\"\nlinha 2\\fim"

      executar(q: texto)

      expect(JSON.parse(enviados.last.body)).to eq('q' => texto, 'limit' => 5)
    end

    context 'with a template written before #1425 (number without quotes)' do
      let(:body_template) { '{"q": "{{ q }}", "n": {{ qtd }}}' }

      it 'sends the same body as before' do
        responder_ok

        executar(q: 'freio dianteiro', qtd: 3)

        expect(enviados.last.body).to eq('{"q": "freio dianteiro", "n": 3}')
      end

      it 'refuses, without sending, when a text breaks the JSON in the number slot' do
        responder_ok

        expect { executar(q: 'freio', qtd: '1, "admin": true') }
          .to raise_error(described_class::Error, 'tool_execution_error: corpo_json_invalido')
        expect(enviados).to be_empty
      end
    end

    context 'when the tool declares a body that is not JSON' do
      let(:body_template) { 'q={{ q }}&limit=5' }
      let(:headers_config) { [{ key: 'Content-Type', value: 'application/x-www-form-urlencoded', secret: false }] }

      it 'renders it as before, without JSON escaping or JSON check' do
        responder_ok

        executar(q: 'a"b')

        expect(enviados.last.body).to eq('q=a"b&limit=5')
      end
    end
  end

  describe 'redirecionamento (item 2)' do
    it 'does not follow a redirect to another domain, and no configured header reaches it' do
      stub_request(:post, endpoint).to_return(status: 302, headers: { 'Location' => 'https://outro.test/coleta' })
      destino = stub_request(:any, 'https://outro.test/coleta')

      expect { executar(q: 'freio') }
        .to raise_error(described_class::Error, 'tool_execution_error: cross_origin_redirect_error')
      expect(destino).not_to have_been_requested
    end

    it 'still follows a redirect inside the same address, keeping the headers' do
      stub_request(:post, endpoint).to_return(status: 307, headers: { 'Location' => '/estoque/v2' })
      final = stub_request(:post, 'https://api.loja.test/estoque/v2')
              .with(headers: { 'x-api-key' => 'chave-muito-secreta-123' })
              .to_return(status: 200, body: '{"ok":1}', headers: { 'Content-Type' => 'application/json' })

      expect(executar(q: 'freio')).to eq('{"ok":1}')
      expect(final).to have_been_requested
    end

    it 'marks every configured header as sensitive and limits the redirects' do
      allow(SafeFetch).to receive(:fetch)

      executar(q: 'freio')

      expect(SafeFetch).to have_received(:fetch).with(
        endpoint,
        hash_including(cross_origin_redirects: false, max_redirects: described_class::MAX_REDIRECTS,
                       sensitive_headers: include('x-api-key', 'content-type'))
      )
    end
  end

  describe 'tempo total (item 3)' do
    it 'passes a total deadline to SafeFetch' do
      allow(SafeFetch).to receive(:fetch)

      executar(q: 'freio')

      expect(SafeFetch).to have_received(:fetch).with(endpoint, hash_including(total_timeout: described_class::TOTAL_TIMEOUT))
      expect(described_class::TOTAL_TIMEOUT).to be <= 10
    end

    context 'with a server that drips the body slowly' do
      let(:servidor) do
        servidor_http_local do |s, cliente|
          s.escrever(cliente, "#{s.cabecalhos(200, 'application/json', 40)}{\"a\":\"")
          [0.3, 0.6, 1.2].each do |pausa|
            sleep(pausa)
            break unless s.escrever(cliente, 'x' * 5)
          end
        end
      end

      after { servidor.parar }

      it 'gives up when the deadline ends, not when the server wants' do
        stub_const("#{described_class}::TOTAL_TIMEOUT", 1)
        tool.endpoint_url = servidor.url('/lento')
        inicio = segundos_monotonicos

        with_modified_env('SAFE_FETCH_ALLOW_PRIVATE_NETWORK' => 'true') do
          sem_webmock do
            expect { executar(q: 'freio') }
              .to raise_error(described_class::Error, 'tool_execution_error: total_timeout_error')
          end
        end

        expect(segundos_monotonicos - inicio).to be < 1.6
      end
    end
  end

  describe 'mapeamento da resposta (item 4)' do
    it 'renders a missing field as empty instead of failing' do
      tool.update!(response_mapping: { 'template' => 'Nome: {{ r.itens[0].nome }}; Preço: {{ r.preco }}' })
      responder_ok('{"itens":[{"nome":"Pastilha"}]}')

      expect(executar(q: 'freio')).to eq('Nome: Pastilha; Preço: ')
    end

    it 'still fails on a broken template' do
      tool.update!(response_mapping: { 'template' => 'Nome: {{ r.itens[0].nome ' })
      responder_ok('{"itens":[]}')

      expect { executar(q: 'freio') }.to raise_error(described_class::Error, 'tool_execution_error: syntax_error')
    end
  end

  describe 'erro 4xx (item 5)' do
    it 'carries the status and a short, cleaned piece of the body' do
      corpo = { erro: 'produto não encontrado', eco: 'chave-muito-secreta-123', token: 'a' * 40, resto: 'z' * 3000 }.to_json
      stub_request(:post, endpoint).to_return(status: [404, 'Not Found'], body: corpo, headers: { 'Content-Type' => 'application/json' })

      erro = nil
      begin
        executar(q: 'freio')
      rescue described_class::Error => e
        erro = e
      end

      expect(erro.message).to eq('tool_http_error: 404 Not Found')
      expect(erro.status).to eq(404)
      expect(erro.trecho).to include('produto não encontrado')
      expect(erro.trecho).not_to include('chave-muito-secreta-123')
      expect(erro.trecho).not_to include('a' * 40)
      expect(erro.trecho.length).to be <= described_class::MAX_TRECHO_DO_ERRO
    end

    it 'gives no body piece for a 5xx' do
      stub_request(:post, endpoint).to_return(status: 500, body: 'stack trace interno')

      expect { executar(q: 'freio') }.to raise_error(described_class::Error) { |e| expect(e.trecho).to be_nil }
    end
  end

  describe 'quebra de linha em cabeçalho (item 6)' do
    let(:headers_config) { [{ key: 'x-cliente', value: '{{ token }}', secret: false }] }

    it 'refuses with a tool error, never an exception outside the handling' do
      responder_ok

      expect { executar(q: 'freio', token: "abc\r\nX-Admin: 1") }
        .to raise_error(described_class::Error, 'tool_execution_error: cabecalho_invalido')
      expect(enviados).to be_empty
    end
  end
end
