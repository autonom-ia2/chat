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
        { name: 'limite', type: 'integer', description: 'Limite', required: false },
        { name: 'ativo', type: 'boolean', description: 'Ativo', required: false },
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

  def erro_de(params)
    executar(params)
    nil
  rescue described_class::Error => e
    e
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

        expect(enviados.last.body).to eq('{"q":"freio dianteiro","n":3}')
      end

      it 'refuses, without sending, a text in the number slot' do
        responder_ok

        expect { executar(q: 'freio', qtd: '1, "admin": true') }
          .to raise_error(described_class::Error, 'tool_execution_error: parametro_invalido')
        expect(enviados).to be_empty
      end
    end

    # Revisão do #1425: o escape vale na SAÍDA de cada {{ }}, depois dos filtros.
    context 'with a filter that decodes the value' do
      let(:body_template) { '{"q":"{{ q | url_decode }}"}' }

      it 'escapes what the filter produced, so no key is injected' do
        responder_ok

        executar(q: 'x%22,%22admin%22:true,%22b%22:%22y')

        expect(JSON.parse(enviados.last.body)).to eq('q' => 'x","admin":true,"b":"y')
      end
    end

    context 'with a text filter on a value that has a line break' do
      let(:body_template) { '{"q":"{{ q | upcase }}"}' }

      it 'keeps the JSON valid' do
        responder_ok

        executar(q: "a\nb")

        expect(JSON.parse(enviados.last.body)).to eq('q' => "A\nB")
      end
    end

    # Os params viram o tipo do param_schema antes de renderizar; o fio leva o JSON regerado.
    context 'with a template that has numbers without quotes' do
      let(:body_template) { '{"qtd": {{qtd}}, "conta": "loja-7", "limite": {{limite}}, "ativo": {{ ativo }}}' }

      it 'refuses a comment opened by the model in a number slot' do
        responder_ok

        expect(erro_de(q: 'x', qtd: '[1 /*', limite: '*/]').message).to eq('tool_execution_error: parametro_invalido')
        expect(enviados).to be_empty
      end

      it 'converts typed text to the declared type' do
        responder_ok

        executar(q: 'x', qtd: '3', limite: 10, ativo: 'true')

        expect(enviados.last.body).to eq('{"qtd":3,"conta":"loja-7","limite":10,"ativo":true}')
      end

      it 'refuses a boolean that is not true or false' do
        responder_ok

        expect(erro_de(q: 'x', qtd: 1, limite: 1, ativo: 'sim').message).to eq('tool_execution_error: parametro_invalido')
      end
    end

    context 'with a text information placed without quotes' do
      let(:body_template) { '{"q": {{q}}, "conta": "loja-7"}' }

      it 'refuses, instead of letting the text open a structure' do
        responder_ok

        expect(erro_de(q: '[1 /*').message).to eq('tool_execution_error: corpo_json_invalido')
        expect(enviados).to be_empty
      end

      # Revisão 2 do #1425: o tipo padrão da tela é texto. Numa vaga sem aspas, o texto vale se for um
      # escalar JSON (número, true, false, null) — como antes do PR; o resto é recusado.
      it 'accepts a text that is a JSON number, as before' do
        responder_ok

        executar(q: '4512')

        expect(enviados.last.body).to eq('{"q":4512,"conta":"loja-7"}')
      end
    end

    context 'with a text in quotes that looks like a number' do
      let(:body_template) { '{"cep": "{{q}}"}' }

      it 'keeps it as text, with the leading zero' do
        responder_ok

        executar(q: '01234')

        expect(enviados.last.body).to eq('{"cep":"01234"}')
      end
    end

    # Revisão 2: comentário no modelo do corpo pode esconder uma {{ }}; o corpo é recusado.
    context 'with a comment written in the template' do
      let(:body_template) { '{"a": [1 /* {{ q }} */]}' }

      it 'refuses, so no value hides in or closes a comment' do
        responder_ok

        expect(erro_de(q: '*/, 2, 3 /*').message).to eq('tool_execution_error: corpo_json_invalido')
        expect(enviados).to be_empty
      end
    end

    # Revisão 2: só tags que não escrevem valor fora de {{ }} (cycle escreve cru).
    context 'with a tag that writes the value without the escape' do
      let(:body_template) { '{"role":"cliente","q":"{% cycle q %}"}' }

      it 'refuses the body' do
        responder_ok

        expect(erro_de(q: 'x","role":"admin","z":"').message).to eq('tool_execution_error: corpo_sem_escape')
        expect(enviados).to be_empty
      end
    end

    context 'with if and for around the variables' do
      let(:body_template) { '{"q":"{% if q %}{{ q }}{% else %}nada{% endif %}"}' }

      it 'still works' do
        responder_ok

        executar(q: 'a"b')

        expect(JSON.parse(enviados.last.body)).to eq('q' => 'a"b')
      end
    end

    # Revisão 2: Content-Type cadastrado vazio é o mesmo que ausente (o executor manda JSON).
    context 'with an empty Content-Type' do
      let(:body_template) { '{"q":"{{ q }}"}' }
      let(:headers_config) { [{ key: 'Content-Type', value: '', secret: false }] }

      it 'treats the body as JSON' do
        responder_ok

        executar(q: 'x","admin":true')

        expect(JSON.parse(enviados.last.body)).to eq('q' => 'x","admin":true')
      end
    end

    # Fato de produção (13/10/2026): a única ferramenta cadastrada é POST, sem Content-Type, com uma
    # única {{ }} entre aspas no corpo. Ela tem de continuar igual.
    context 'with the shape of the tool that exists in production' do
      let(:body_template) { '{"q":"{{q}}"}' }
      let(:headers_config) { [{ key: 'x-api-key', value: 'chave-muito-secreta-123', secret: true }] }

      it 'sends the same body as before, with JSON content type' do
        responder_ok

        executar(q: 'pastilha de freio')

        expect(enviados.last.body).to eq('{"q":"pastilha de freio"}')
        expect(enviados.last.headers['Content-Type']).to eq('application/json')
      end
    end

    context 'when the tool declares a form body' do
      let(:body_template) { 'q={{ q }}&limit=5' }
      let(:headers_config) { [{ key: 'Content-Type', value: 'application/x-www-form-urlencoded', secret: false }] }

      it 'encodes each value as a form field, so no field is injected' do
        responder_ok

        executar(q: 'a&admin=true&limit=999')

        expect(enviados.last.body).to eq('q=a%26admin%3Dtrue%26limit%3D999&limit=5')
        expect(URI.decode_www_form(enviados.last.body).to_h).to eq('q' => 'a&admin=true&limit=999', 'limit' => '5')
      end

      context 'with url_encode already written in the variable' do
        let(:body_template) { 'q={{ q | url_encode }}&limit=5' }

        it 'encodes only once' do
          responder_ok

          executar(q: 'a b&c')

          expect(URI.decode_www_form(enviados.last.body).to_h).to eq('q' => 'a b&c', 'limit' => '5')
        end
      end
    end

    context 'when the tool declares another body type' do
      let(:headers_config) { [{ key: 'Content-Type', value: 'application/xml', secret: false }] }

      context 'with a variable in the body' do
        let(:body_template) { '<q>{{ q }}</q>' }

        it 'refuses: there is no safe escape for it' do
          responder_ok

          expect(erro_de(q: '</q><admin>1</admin>').message).to eq('tool_execution_error: corpo_sem_escape')
          expect(enviados).to be_empty
        end
      end

      context 'with a fixed body' do
        let(:body_template) { '<ping/>' }

        it 'sends it as written' do
          responder_ok

          executar(q: 'x')

          expect(enviados.last.body).to eq('<ping/>')
        end
      end
    end
  end

  # Revisão 3 do #1425: o valor do modelo no ENDEREÇO vai codificado conforme a posição da {{ }} —
  # pedaço do caminho (`/` incluso) ou valor da query —, e nunca no esquema, no host ou no fragmento.
  describe 'endereço (revisão 3)' do
    let(:body_template) { '' }

    def url_chamada(endereco, params)
      tool.endpoint_url = endereco
      allow(SafeFetch).to receive(:fetch)
      executar(params)
      url = nil
      expect(SafeFetch).to have_received(:fetch) { |chamada, **| url = chamada }
      url
    end

    it 'keeps a fixed address identical' do
      fixo = 'https://api.loja.test/v1/estoque?x=1&y=a%20b#frag'

      expect(url_chamada(fixo, q: 'x')).to eq(fixo)
    end

    it 'encodes a path value as one segment, slash included' do
      expect(url_chamada('https://api.loja.test/estoque/{{q}}/itens', q: 'a/b?x=1#y'))
        .to eq('https://api.loja.test/estoque/a%2Fb%3Fx%3D1%23y/itens')
    end

    it 'encodes spaces and accents in the path' do
      expect(url_chamada('https://api.loja.test/estoque/{{q}}', q: 'freio ção'))
        .to eq('https://api.loja.test/estoque/freio%20%C3%A7%C3%A3o')
    end

    it 'refuses a path value that is . or ..' do
      tool.endpoint_url = 'https://api.loja.test/estoque/{{q}}/itens'

      expect(erro_de(q: '..').message).to eq('tool_execution_error: endereco_invalido')
      expect(erro_de(q: '.').message).to eq('tool_execution_error: endereco_invalido')
    end

    # Revisão 4: um servidor que decodifica %2F antes de rotear resolveria o "../" de dentro do valor.
    it 'refuses . or .. inside a path value, split by slash and backslash' do
      tool.endpoint_url = 'https://api.loja.test/estoque/{{q}}/itens'

      ['../admin', '..\admin', 'a/../b', 'a\.\b'].each do |valor|
        expect(erro_de(q: valor).message).to eq('tool_execution_error: endereco_invalido'), valor
      end
    end

    # Revisão 4: pedaço vazio cairia na coleção (`/clientes/`).
    it 'refuses an empty path value' do
      tool.endpoint_url = 'https://api.loja.test/clientes/{{q}}'

      expect(erro_de(q: '').message).to eq('tool_execution_error: endereco_invalido')
    end

    # #1444: valor só de espaços viraria `/clientes/%20` — o mesmo pedaço vazio, disfarçado.
    it 'refuses a path value made only of spaces' do
      tool.endpoint_url = 'https://api.loja.test/clientes/{{q}}'

      [' ', "  \t "].each do |valor|
        expect(erro_de(q: valor).message).to eq('tool_execution_error: endereco_invalido'), valor.inspect
      end
    end

    # #1444: o Liquid engolia o erro de render e escrevia "Liquid error: ..." cru no endereço, sem
    # escape. Agora o erro recusa a chamada, e nada sai pela rede.
    it 'refuses, without calling, an address whose render fails' do
      tool.endpoint_url = 'https://api.loja.test/estoque/{{ mapa[q] }}'
      allow(SafeFetch).to receive(:fetch)

      expect(erro_de(q: 'tenis').message).to eq('tool_execution_error: undefined_variable')
      expect(SafeFetch).not_to have_received(:fetch)
    end

    # Revisão 4: `echo` com url_encode final também codifica uma vez só.
    it 'encodes only once with echo and url_encode' do
      expect(url_chamada('https://api.loja.test/estoque/{% echo q | url_encode %}', q: 'a b'))
        .to eq('https://api.loja.test/estoque/a%20b')
    end

    # Revisão 4: o global_filter roda dentro do assign; o valor sairia escapado duas vezes.
    it 'refuses assign in the address' do
      tool.endpoint_url = 'https://api.loja.test/estoque/{% assign x = q %}{{ x }}'

      expect(erro_de(q: 'a b').message).to eq('tool_execution_error: endereco_invalido')
    end

    it 'encodes a query value as a form field, so & and # do not add or cut anything' do
      expect(url_chamada('https://api.loja.test/estoque?termo={{q}}&limit=5', q: 'a&admin=1#x ção'))
        .to eq('https://api.loja.test/estoque?termo=a%26admin%3D1%23x+%C3%A7%C3%A3o&limit=5')
    end

    it 'encodes only once when url_encode is already written' do
      expect(url_chamada('https://api.loja.test/estoque/{{ q | url_encode }}?t={{ q | url_encode }}', q: 'a b&c'))
        .to eq('https://api.loja.test/estoque/a%20b%26c?t=a+b%26c')
    end

    # Host ou esquema vindos do modelo mandariam os cabeçalhos de autenticação para onde ele quiser;
    # o cadastro já não aceita (`validate_endpoint_url`), e aqui a recusa é explícita.
    it 'refuses a variable in the scheme, the host or the fragment' do
      %w[https://{{q}}.loja.test/x {{q}}://api.loja.test/x https://api.loja.test/x#{{q}}].each do |endereco|
        tool.endpoint_url = endereco

        expect(erro_de(q: 'outro').message).to eq('tool_execution_error: endereco_invalido')
      end
    end
  end

  # Revisão 3: número não finito e UTF-8 inválido viram recusa tratada, nunca exceção solta.
  # Revisão 4: assign no corpo escaparia duas vezes (o global_filter roda dentro dele).
  it 'refuses assign in the body' do
    tool.request_body_template = '{% assign x = q %}{"q":"{{ x }}"}'
    responder_ok

    expect(erro_de(q: 'a"b').message).to eq('tool_execution_error: corpo_sem_escape')
  end

  # #1444: no corpo e no cabeçalho, o erro de render também recusa sem enviar — em JSON, no corpo fixo e
  # no cabeçalho o texto "Liquid error: ..." ia direto para o sistema do dono.
  describe 'erro de render do Liquid no corpo e no cabeçalho (#1444)' do
    it 'refuses a JSON body whose render fails, sending nothing' do
      tool.request_body_template = '{"q":"{{ inexistente }}"}'
      responder_ok

      expect(erro_de(q: 'x').message).to eq('tool_execution_error: undefined_variable')
      expect(enviados).to be_empty
    end

    it 'refuses a fixed body whose render fails, sending nothing' do
      tool.headers_config = [{ key: 'content-type', value: 'text/plain', secret: false }]
      tool.request_body_template = 'pedido {{ inexistente }}'
      responder_ok

      expect(erro_de(q: 'x').message).to eq('tool_execution_error: undefined_variable')
      expect(enviados).to be_empty
    end

    # O valor do cabeçalho passa pelo mesmo render e tinha o mesmo defeito.
    it 'refuses a header whose render fails, sending nothing' do
      tool.headers_config = headers_config + [{ key: 'x-cliente', value: '{{ inexistente }}', secret: false }]
      responder_ok

      expect(erro_de(q: 'x').message).to eq('tool_execution_error: undefined_variable')
      expect(enviados).to be_empty
    end
  end

  describe 'valores que o JSON não representa' do
    it 'refuses 1e999 in a slot without quotes' do
      tool.request_body_template = '{"n": {{q}}}'
      responder_ok

      expect(erro_de(q: '1e999').message).to eq('tool_execution_error: corpo_json_invalido')
    end

    it 'refuses invalid UTF-8 in the body' do
      responder_ok

      expect(erro_de(q: (+"ab\xFFcd").force_encoding('UTF-8')).message).to eq('tool_execution_error: corpo_json_invalido')
    end

    it 'answers with valid text when the system sends invalid UTF-8' do
      responder_ok((+"{\"a\":\"\xFF\"}").force_encoding('UTF-8'))

      resposta = executar(q: 'freio')

      expect(resposta).to be_a(String)
      expect(resposta.valid_encoding?).to be(true)
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

    # Revisão do #1425: mapeamento que renderiza vazio NÃO cai na resposta crua (que ele existe para filtrar).
    it 'returns empty, never the raw answer, when every mapped field is missing' do
      tool.update!(response_mapping: { 'template' => '{{ r.campo_ausente }}' })
      responder_ok('{"cpf":"123.456.789-00"}')

      expect(executar(q: 'freio')).to eq('')
    end

    it 'fails instead of handing the raw answer when it is not JSON and there is a mapping' do
      tool.update!(response_mapping: { 'template' => '{{ r.nome }}' })
      responder_ok('cpf 123.456.789-00')

      expect(erro_de(q: 'freio').message).to eq('tool_execution_error: parser_error')
    end

    it 'still fails on a broken template' do
      tool.update!(response_mapping: { 'template' => 'Nome: {{ r.itens[0].nome ' })
      responder_ok('{"itens":[]}')

      expect { executar(q: 'freio') }.to raise_error(described_class::Error, 'tool_execution_error: syntax_error')
    end
  end

  describe 'erro 4xx (item 5)' do
    it 'carries the status and a short, cleaned piece of the body' do
      corpo = { erro: 'produto não encontrado', eco: 'chave-muito-secreta-123', token: 'a' * 40, resto: 'palavra ' * 400 }.to_json
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

    it 'hides what came from the tool setup: path, userinfo and literal body values' do
      tool.endpoint_url = 'https://usuario:senha-da-loja@api.loja.test/v1/tok3n-do-caminho/estoque'
      tool.request_body_template = '{"api_key":"sk_live_ab12-xyz","q":"{{q}}"}'
      eco = { erro: 'campo inválido', recebido: { api_key: 'SK_LIVE_AB12-XYZ', path: '/v1/tok3n-do-caminho', u: 'senha-da-loja' } }.to_json
      stub_request(:post, 'https://api.loja.test/v1/tok3n-do-caminho/estoque')
        .with(basic_auth: %w[usuario senha-da-loja])
        .to_return(status: [422, 'Unprocessable Entity'], body: eco)

      trecho = erro_de(q: 'freio').trecho

      expect(trecho).to include('campo inválido')
      %w[sk_live_ab12-xyz SK_LIVE_AB12-XYZ tok3n-do-caminho senha-da-loja].each do |segredo|
        expect(trecho).not_to include(segredo)
      end
    end

    # Revisão 2: literal do cadastro só é oculto quando tem cara de credencial; palavra comum fica.
    it 'keeps common words of the path and of the body readable' do
      tool.endpoint_url = 'https://api.loja.test/v1/clientes/busca'
      tool.request_body_template = '{"q":"{{q}}","status":"ativo"}'
      stub_request(:post, 'https://api.loja.test/v1/clientes/busca')
        .to_return(status: [404, 'Not Found'], body: '{"error":"Clientes: campo busca inválido","status":"ativo"}')

      trecho = erro_de(q: 'freio').trecho

      expect(trecho).to include('Clientes: campo busca inválido')
      expect(trecho).to include('ativo')
    end

    it 'hides a short key written in a fixed body that is not JSON' do
      tool.headers_config = [{ 'key' => 'Content-Type', 'value' => 'text/xml', 'secret' => false }]
      tool.request_body_template = '<auth><key>s3cr3t.k3y</key></auth>'
      stub_request(:post, endpoint).to_return(status: [401, 'Unauthorized'], body: 'invalid key s3cr3t.k3y for user')

      trecho = erro_de(q: 'freio').trecho

      expect(trecho).to include('invalid key')
      expect(trecho).not_to include('s3cr3t.k3y')
    end

    # Revisão 3: chave só de letras na query e Basic auth em todas as formas são sempre segredo.
    # Revisão 4: o servidor pode ecoar o usuário e a senha ainda codificados, como estão na URL.
    it 'hides the userinfo also in its raw, still encoded form' do
      tool.endpoint_url = 'https://usuario.loja:senha%2Dmuito%2Dforte@api.loja.test/estoque'
      stub_request(:post, 'https://api.loja.test/estoque')
        .with(basic_auth: ['usuario.loja', 'senha-muito-forte'])
        .to_return(status: [401, 'Unauthorized'], body: 'negado para senha%2Dmuito%2Dforte')

      trecho = erro_de(q: 'freio').trecho

      expect(trecho).to start_with('negado para')
      expect(trecho).not_to include('senha%2Dmuito')
    end

    it 'hides query values and every form of a Basic auth header' do
      basic = Base64.strict_encode64('usuarioloja:senhasoletrasmuitolonga')
      tool.headers_config = [{ 'key' => 'Authorization', 'value' => "Basic #{basic}", 'secret' => true }]
      tool.endpoint_url = 'https://api.loja.test/estoque/busca?api_key=chaveapenasletrasx'
      eco = "negado: usuarioloja senhasoletrasmuitolonga #{basic} chaveapenasletrasx"
      stub_request(:post, 'https://api.loja.test/estoque/busca?api_key=chaveapenasletrasx')
        .to_return(status: [403, 'Forbidden'], body: eco)

      trecho = erro_de(q: 'freio').trecho

      expect(trecho).to start_with('negado:')
      ['usuarioloja', 'senhasoletrasmuitolonga', basic, 'chaveapenasletrasx'].each { |segredo| expect(trecho).not_to include(segredo) }
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
