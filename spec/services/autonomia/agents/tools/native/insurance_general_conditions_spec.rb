require 'rails_helper'

# A ferramenta que INVERTE a proibição do multicálculo: até agora o agente não podia explicar
# cobertura, porque não tinha o contrato. Com a CG da seguradora certa, explicar deixa de ser
# opinião. O que estes exemplos travam é o limite disso — quando a base NÃO sustenta, a ferramenta
# manda escalar e nunca deixa o agente dizer "não cobre".
#
# Os corpos em `spec/fixtures/files/condicoes_gerais/` são respostas REAIS do `/perguntar` de
# 15/11/2026 (sem os blocos de telemetria de custo). O catálogo veio do mesmo dia, pelo time da API.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceGeneralConditions do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:account_key) { 'sk-conta-do-cliente-0123456789' }
  let(:params) do
    { 'seguradora' => 'Porto', 'pergunta' => 'A cobertura de danos elétricos tem franquia?' }
  end
  let(:tool) { described_class.new(agent: agent, params: params) }
  let(:url) { 'https://agent.autonomia.site/perguntar' }

  # O gate é ENV mestre + marca da conta + chave da conta. Sem a ENV, `available_for?` é false.
  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => account_key })
  end

  # Um item do comparativo, pelo nome da seguradora: o texto de cada uma pode ter várias linhas.
  def comparison_item(out, insurer)
    out.split("\n- ").find { |item| item.start_with?("#{insurer}:") }
  end

  def requested_question
    body = nil
    expect(WebMock).to(have_requested(:post, url).with(query: { 'api_key' => account_key }) { |req| body = JSON.parse(req.body) })
    body
  end

  def real_body(name)
    JSON.parse(file_fixture("condicoes_gerais/#{name}.json").read)
  end

  def stub_body(body, status: 200)
    stub_request(:post, url).with(query: { 'api_key' => account_key })
                            .to_return(status: status, body: body.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
  end

  # O corpo real da consulta, com a `resposta` trocada no que cada exemplo precisa.
  def stub_query(**changes)
    body = real_body('consulta')
    body['resposta'] = body['resposta'].merge(changes.transform_keys(&:to_s))
    stub_body(body)
  end

  describe 'the request' do
    it 'asks /perguntar with the account key and the question as written, never a fixed product' do
      # Arrange
      stub_query

      # Act
      tool.call

      # Assert — quem escolhe o produto é a API; com "Automóvel" fixo, residencial caía no contrato de carro.
      # Sem rótulo colado: o contexto que falta o modelo junta ao escrever a pergunta.
      body = requested_question
      expect(body['pergunta']).to eq('A cobertura de danos elétricos tem franquia?')
      expect(body['include_evidence']).to be(false)
      expect(body).not_to have_key('insurance_type')
    end

    it 'has only seguradora and pergunta, both required and never null: the branch goes inside the question' do
      # Arrange
      schema = described_class.openai_schema[:parameters]

      # Act / Assert — o `ramo` saiu (#3035); um opcional mal declarado derrubou a chamada em 08/09/2026
      expect(schema[:properties].keys).to eq(%w[seguradora pergunta])
      expect(schema[:required]).to eq(%w[seguradora pergunta])
      expect(schema[:properties].values.pluck('type')).to all(eq('string'))
    end

    it 'asks for the insurer instead of querying without it' do
      # Arrange / Act
      out = described_class.new(agent: agent, params: params.merge('seguradora' => '')).call

      # Assert
      expect(out).to match(/informe a seguradora/i)
      expect(WebMock).not_to have_requested(:post, /perguntar/)
    end
  end

  describe 'consulta' do
    it 'answers from the clause, says whose rule it is and flags the partial answer' do
      # Arrange — corpo real: `answered` + `grounded`, com `model_marked_partial`
      stub_query

      # Act
      out = tool.call

      # Assert
      expect(out).to include('Porto Seguro')
      expect(out).to include('a franquia é descontada da indenização')
      expect(out).to match(/PARCIAL/)
      expect(out).to match(/não estenda para as outras/i)
      expect(out).not_to match(/contratos diferentes/i)
    end

    it 'treats an answer whose model did not say it resolves the question as partial' do
      # Arrange
      stub_query('warnings' => ['llm_json_answers_question_missing'])

      # Act / Assert
      expect(tool.call).to match(/PARCIAL/)
    end

    it 'does not present a rule from two contracts as the rule of the insurer' do
      # Arrange
      stub_query('warnings' => [], 'contracts' => { 'cited' => %w[15414.652124/2021-13 15414.000573/2006-42] })

      # Act
      out = tool.call

      # Assert
      expect(out).to include('2 contratos diferentes')
      expect(out).to include('15414.000573/2006-42')
      expect(out).not_to match(/PARCIAL/)
    end

    %w[insufficient_context unsupported].each do |status|
      it "never turns #{status} into 'not covered'" do
        # Arrange — `insufficient_context` sai com texto plausível junto
        stub_query('answer_status' => status, 'grounded' => false,
                   'answer_text' => 'O contexto sugere que talvez esteja coberto.')

        # Act
        out = tool.call

        # Assert
        expect(out).not_to include('talvez esteja coberto')
        expect(out).to match(/NÃO quer dizer que o contrato não cobre/)
        expect(out).to match(/NÃO responda de memória/)
      end
    end

    it 'treats grounded:false as unusable even when the status says answered' do
      # Arrange — as duas marcas existem porque uma sem a outra não vale
      stub_query('answer_status' => 'answered', 'grounded' => false, 'answer_text' => 'Está coberto.')

      # Act / Assert
      expect(tool.call).to match(/não encontrei/i)
    end

    it 'asks which insurer when the name did not resolve, instead of inventing a gap' do
      # Arrange — "Bradesco" resolve para empresas diferentes; dizer "não tem na CG" seria mentir
      stub_query('answer_status' => 'insufficient_context', 'grounded' => false,
                 'interpreted' => { 'insurers' => [{ 'sent' => 'Bradesco', 'resolved' => [],
                                                     'did_you_mean' => ['Bradesco Seguros', 'Bradesco Vida e Previdência'] }] })

      # Act
      out = tool.call

      # Assert
      expect(out).to include('Bradesco Seguros')
      expect(out).not_to match(/não encontrei/i)
    end

    it 'does not say the name did not resolve when it did, even with suggestions' do
      # Arrange
      stub_query('answer_status' => 'insufficient_context', 'grounded' => false,
                 'interpreted' => { 'insurers' => [{ 'sent' => 'Porto', 'resolved' => ['Porto Seguro'],
                                                     'did_you_mean' => ['Porto Seguro Cia'] }] })

      # Act
      out = tool.call

      # Assert
      expect(out).not_to match(/Não identifiquei a seguradora/)
      expect(out).to match(/NÃO quer dizer que o contrato não cobre/)
    end

    it 'asks which company when the product is in a sister brand' do
      # Arrange — formato do `aviso` informado pelo time da API (#202)
      stub_query('answer_text' => 'Na Mapfre Vida há assistência funeral.',
                 'aviso' => { 'codigo' => 'produto_em_seguradora_parecida', 'seguradora' => 'Mapfre Seguros',
                              'produto' => 'Vida', 'seguradoras_parecidas' => ['Mapfre Vida'] })

      # Act
      out = tool.call

      # Assert — quem decide qual empresa vale é o cliente, não a busca
      expect(out).to include('Mapfre Vida')
      expect(out).to match(/de qual empresa/i)
      expect(out).not_to include('assistência funeral')
    end

    it 'does not read a product missing from the base as the insurer not selling it' do
      # Arrange
      stub_query('aviso' => { 'codigo' => 'seguradora_sem_o_produto', 'seguradora' => 'Porto Seguro',
                              'produto' => 'GAP', 'produtos_da_seguradora' => ['Residencial'] })

      # Act
      out = tool.call

      # Assert
      expect(out).to match(/não quer dizer que a seguradora não vende/i)
      expect(out).not_to include('Trecho das condições gerais')
    end

    it 'says when the rule came from another product of the same insurer' do
      # Arrange
      stub_query('warnings' => [], 'aviso' => { 'codigo' => 'produto_trocado', 'seguradora' => 'Porto Seguro',
                                                'produto_pedido' => 'Condomínio', 'produto_usado' => 'Residencial' })

      # Act
      out = tool.call

      # Assert
      expect(out).to include('A regra é do produto Residencial, não de Condomínio')
    end

    it 'stays out of a question that is not about the policy' do
      # Arrange — rota `fora_do_escopo`: a resposta é só status, frase fixa e grounded false
      body = real_body('consulta')
      body['encaminhamento']['rota'] = 'fora_do_escopo'
      body['resposta'] = { 'answer_status' => 'out_of_scope', 'answer_text' => 'Fora do escopo.', 'grounded' => false }
      stub_body(body)

      # Act / Assert
      expect(tool.call).to match(/não é sobre as condições gerais/i)
    end

    it 'bounds what the clause is good for, because grounded does not mean relevant' do
      # Arrange — caso REAL de 04/09/2026: a cor preferida do presidente voltou `answered` + `grounded`
      stub_query('warnings' => [], 'answer_text' => 'O presidente do grupo é Fulano de Tal.')

      # Act
      out = tool.call

      # Assert — a ferramenta entrega, mas manda o agente não repassar o que não é do contrato
      expect(out).to match(/SÓ se a pergunta for sobre cobertura/i)
      expect(out).to match(/NÃO repasse/i)
    end
  end

  describe 'comparativo' do
    it 'keeps each insurer with its own rule and status' do
      # Arrange — corpo real: Porto parcial, Allianz completa
      stub_body(real_body('comparativo'))

      # Act
      out = tool.call

      # Assert
      expect(comparison_item(out, 'Porto Seguro')).to include('Na Porto, o carro reserva')
      expect(comparison_item(out, 'Porto Seguro')).to include('(parcial')
      expect(comparison_item(out, 'Allianz Seguros')).to include('No Allianz Auto')
      expect(comparison_item(out, 'Allianz Seguros')).not_to include('(parcial')
    end

    it 'never reads an insurer without excerpts as not covering' do
      # Arrange — `no_context`: a busca não achou trecho daquela seguradora
      body = real_body('comparativo')
      body['resposta']['insurer_results'][1].merge!('answer_status' => 'no_context', 'grounded' => false,
                                                    'answer_text' => '')
      stub_body(body)

      # Act
      out = tool.call

      # Assert
      expect(comparison_item(out, 'Allianz Seguros')).to include('Não diga que não cobre')
    end
  end

  describe 'comparativo coverage' do
    it 'says who was left out, without reading it as not covering' do
      # Arrange — avisos do comparativo, formato do time da API
      body = real_body('comparativo')
      body['resposta']['coverage']['insurers_without_documents'] = ['Sompo Seguros']
      body['resposta']['warnings'] = ['insurers_truncated_from_8_to_6', 'insurers_left_out:HDI Seguros; Azul Seguros',
                                      'insurer_name_resolved:Bradesco=Bradesco Seguros;also_compared=Bradesco Auto/RE|Bradesco Vida']
      stub_body(body)

      # Act
      out = tool.call

      # Assert
      expect(out).to include('- Sompo Seguros: a base não tem as condições gerais dela para este seguro')
      expect(out).to include('Ficaram fora do comparativo: HDI Seguros, Azul Seguros.')
      expect(out).to include('O comparativo ficou incompleto')
      expect(out).to include('"Bradesco" foi lido como Bradesco Seguros, não o grupo inteiro.')
      expect(out).not_to include('also_compared')
    end

    it 'reports a failed insurer as a failure, not as a gap' do
      # Arrange
      body = real_body('comparativo')
      body['resposta']['insurer_results'][1].merge!('answer_status' => 'failed', 'grounded' => false,
                                                    'warnings' => ['llm_auth_failed'])
      stub_body(body)

      # Act
      out = tool.call

      # Assert
      expect(comparison_item(out, 'Allianz Seguros')).to include('a consulta não respondeu agora')
    end
  end

  describe 'documentos' do
    it 'does not send a link when the base has several contracts for the request' do
      # Arrange — corpo real: 4 contratos residenciais da Tokio Marine
      stub_body(real_body('documentos'))

      # Act
      out = tool.call

      # Assert — qual vale depende da apólice; mandar o errado é pior do que não mandar
      expect(out).to include('Há 4 condições gerais de Residencial da Tokio Marine')
      expect(out).not_to include('https://')
    end

    it 'gives the PDF when there is only one' do
      # Arrange
      body = real_body('documentos')
      body['resposta']['documents'] = body['resposta']['documents'].first(1)
      stub_body(body)

      # Act
      out = tool.call

      # Assert
      expect(out).to include('https://agent.autonomia.site/documents/pdf/f7bf252e-284b-59c4-a138-990c1f1acf78')
      expect(out).to match(/só se a pessoa pediu o documento/i)
    end

    it 'falls back to the SUSEP link when the PDF is not stored' do
      # Arrange — `pdf_url` só vem quando o PDF está guardado; `url` da SUSEP vem sempre
      body = real_body('documentos')
      body['resposta']['documents'] = [body['resposta']['documents'].first.except('pdf_url')]
      stub_body(body)

      # Act / Assert
      expect(tool.call).to include('https://www2.susep.gov.br/safe/menumercado/REP2/Produto.aspx/DownloadConsultaPublica/489293')
    end
  end

  it 'lists who has the product in the catalog without promising sale' do
    # Arrange — o catálogo não tem síntese; quem responde são os pares de `availability`
    stub_body(real_body('catalogo'))

    # Act
    out = tool.call

    # Assert
    expect(out).to include('Akad Seguros S.A. (Automóvel - Casco)')
    expect(out).to include('Alfa Seguradora (Automóvel - Casco)')
    expect(out).to match(/não o que cada seguradora vende hoje/i)
    expect(out).not_to include('151')
  end

  describe 'failures' do
    it 'separates "we do not have this insurer" from "the query failed"' do
      # Arrange — corpo real do 404: o erro vem dentro de `resposta`
      stub_body(real_body('seguradora_inexistente'), status: 404)

      # Act
      out = described_class.new(agent: agent, params: params.merge('seguradora' => 'Zorblax')).call

      # Assert
      expect(out).to match(/não tenho as condições gerais da Zorblax/i)
      expect(out).not_to match(/não respondeu agora/i)
    end

    it 'escalates when the account key is refused, without logging the key' do
      # Arrange — chave recusada no roteador: 401 `llm_auth_failed`
      stub_body({ 'detail' => 'llm_auth_failed' }, status: 401)
      allow(Rails.logger).to receive(:warn)

      # Act
      out = tool.call

      # Assert
      expect(out).to match(/confirmar com um especialista/i)
      expect(Rails.logger).to have_received(:warn).with(include('http_401_llm_auth_failed'))
      expect(Rails.logger).not_to have_received(:warn).with(include(account_key))
      expect(Rails.logger).not_to have_received(:warn).with(include('api_key='))
    end

    it 'escalates when the key fails in the middle of the answer' do
      # Arrange — a recusa na síntese chega como 200 com `failed`
      stub_query('answer_status' => 'failed', 'grounded' => false, 'warnings' => ['llm_auth_failed'])

      # Act / Assert
      expect(tool.call).to match(/confirmar com um especialista/i)
    end

    it 'never puts the address, which carries the key, in the log of a timeout' do
      # Arrange
      stub_request(:post, url).with(query: hash_including({})).to_raise(Net::ReadTimeout)
      allow(Rails.logger).to receive(:warn)

      # Act
      out = tool.call

      # Assert
      expect(out).to match(/não respondeu agora/i)
      expect(Rails.logger).not_to have_received(:warn).with(include(account_key))
      expect(Rails.logger).not_to have_received(:warn).with(include('api_key='))
    end

    it 'tells the agent to escalate when the API itself is down' do
      # Arrange
      stub_body({ 'detail' => 'router_unavailable' }, status: 503)

      # Act
      out = tool.call

      # Assert — nada de mensagem de erro crua chegando perto do cliente
      expect(out).to match(/confirmar com um especialista/i)
      expect(out).not_to include('503')
    end
  end

  describe '.available_for?' do
    it 'is offered when the account has the insurance module and its own key' do
      # Arrange / Act / Assert — não exige conexão pronta: explicar cobertura vale antes de cotar
      expect(described_class.available_for?(agent)).to be(true)
    end

    it 'stays out of the prompt when the module is off' do
      # Arrange
      account.update!(internal_attributes: { 'autonomia_insurance_enabled' => false })

      # Act / Assert
      expect(described_class.available_for?(agent.reload)).to be(false)
    end

    it 'never falls back to the installation key' do
      # Arrange — sem hook, o resolvedor devolveria a chave da instalação
      account.hooks.where(app_id: 'crm_kanban_ai').destroy_all
      InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: 'chave-da-instalacao')

      # Act / Assert
      expect(described_class.available_for?(agent.reload)).to be(false)
    end

    it 'stays out when the account key points to another endpoint' do
      # Arrange — a API da Mia só fala com a OpenAI; outra chave voltaria 401
      account.hooks.find_by(app_id: 'crm_kanban_ai')
             .update!(settings: { 'api_key' => account_key, 'api_base' => 'https://outro-provedor.example' })

      # Act / Assert
      expect(described_class.available_for?(agent.reload)).to be(false)
    end
  end

  it 'is registered, otherwise no agent can ever turn it on' do
    # Arrange / Act / Assert
    expect(Autonomia::Agents::Tools::Registry.find('consultar_condicoes_gerais')).to eq(described_class)
  end
end
