require 'rails_helper'

# A ferramenta que INVERTE a proibição do multicálculo: até agora o agente não podia explicar
# cobertura, porque não tinha o contrato. Com a CG da seguradora certa, explicar deixa de ser
# opinião. O que estes exemplos travam é o limite disso — quando a base NÃO sustenta, a ferramenta
# tem que mandar escalar, nunca devolver prosa que pareça resposta.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceGeneralConditions do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:params) do
    { 'seguradora' => 'HDI', 'pergunta' => 'A cobertura de vidros inclui o vidro traseiro?' }
  end
  let(:tool) { described_class.new(agent: agent, params: params) }
  let(:url) { 'https://agent.autonomia.site/query' }

  # O gate é ENV mestre + marca da conta. Sem a ENV, `available_for?` é false e a ferramenta nem
  # entra no prompt — que é o comportamento certo, e por isso o exemplo do gate precisa dela ligada.
  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def stub_answer(status:, grounded:, text: 'O vigia está coberto.', resolved: ['HDI Seguros'],
                  did_you_mean: [])
    body = {
      'answer_text' => text, 'answer_status' => status, 'grounded' => grounded,
      'interpreted' => { 'insurers' => [{ 'sent' => 'HDI', 'resolved' => resolved,
                                          'did_you_mean' => did_you_mean }] }
    }
    stub_request(:post, url).to_return(status: 200, body: body.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
  end

  it 'answers from the clause and says whose rule it is' do
    # Arrange — só `answered` + `grounded` é resposta de verdade
    stub_answer(status: 'answered', grounded: true)

    # Act
    out = tool.call

    # Assert — sem o nome da seguradora o cliente entende que a regra vale para o comparativo todo
    expect(out).to include('HDI Seguros')
    expect(out).to include('O vigia está coberto.')
    expect(out).to match(/não estenda para as outras/i)
  end

  it 'refuses to answer when the material does not sustain it' do
    # Arrange — medido na API real: `insufficient_context` sai com texto plausível junto
    stub_answer(status: 'insufficient_context', grounded: false,
                text: 'O contexto sugere que talvez esteja coberto.')

    # Act
    out = tool.call

    # Assert
    expect(out).not_to include('talvez esteja coberto')
    expect(out).to match(/NÃO responda de memória/i)
  end

  it 'treats grounded:false as unusable even when the status says answered' do
    # Arrange — as duas marcas existem porque uma sem a outra não vale; é a trava anti-alucinação
    stub_answer(status: 'answered', grounded: false, text: 'Está coberto.')

    # Act / Assert
    expect(tool.call).to match(/não encontrei/i)
  end

  it 'asks which insurer when the name did not resolve, instead of inventing a gap' do
    # Arrange — "Bradesco" resolve para três empresas diferentes; dizer "não tem na CG" seria mentir
    stub_answer(status: 'insufficient_context', grounded: false, resolved: [],
                did_you_mean: ['Bradesco Seguros', 'Bradesco AUTO/RE Companhia Seguros',
                               'Bradesco VIDA Previdência .'])

    # Act
    out = described_class.new(agent: agent, params: params.merge('seguradora' => 'Bradesco')).call

    # Assert
    expect(out).to include('Bradesco Seguros')
    expect(out).not_to match(/não encontrei essa regra/i)
  end

  it 'sends the branch, defaulting to Auto' do
    # Arrange
    stub_answer(status: 'answered', grounded: true)

    # Act
    tool.call

    # Assert
    expect(WebMock).to(have_requested(:post, url)
      .with { |req| JSON.parse(req.body)['insurance_type'] == 'Automóvel' })
  end

  it 'never asks for the evidence payload — the agent reads prose, not clauses' do
    # Arrange — `include_evidence` devolve 20 trechos crus e estoura o contexto do turno
    stub_answer(status: 'answered', grounded: true)

    # Act
    tool.call

    # Assert
    expect(WebMock).to(have_requested(:post, url)
      .with { |req| JSON.parse(req.body)['include_evidence'] == false })
  end

  it 'tells the agent to escalate when the API itself is down' do
    # Arrange
    stub_request(:post, url).to_return(status: 502, body: '')

    # Act
    out = tool.call

    # Assert — nada de mensagem de erro crua chegando perto do cliente
    expect(out).to match(/confirmar com um especialista/i)
    expect(out).not_to include('502')
  end

  it 'asks for the insurer instead of querying without it' do
    # Arrange / Act
    out = described_class.new(agent: agent, params: params.merge('seguradora' => '')).call

    # Assert
    expect(out).to match(/informe a seguradora/i)
    expect(WebMock).not_to have_requested(:post, url)
  end

  describe '.available_for?' do
    it 'is offered whenever the account has the insurance module on' do
      # Arrange / Act / Assert — não exige conexão pronta: explicar cobertura vale antes de cotar
      expect(described_class.available_for?(agent)).to be(true)
    end

    it 'stays out of the prompt when the module is off' do
      # Arrange
      account.update!(internal_attributes: { 'autonomia_insurance_enabled' => false })

      # Act / Assert
      expect(described_class.available_for?(agent.reload)).to be(false)
    end
  end

  it 'is registered, otherwise no agent can ever turn it on' do
    # Arrange / Act / Assert
    expect(Autonomia::Agents::Tools::Registry.find('consultar_condicoes_gerais')).to eq(described_class)
  end
end
