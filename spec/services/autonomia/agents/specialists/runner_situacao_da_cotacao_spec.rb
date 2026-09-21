require 'rails_helper'

# A SITUAÇÃO DA COTAÇÃO, DITA PELO SISTEMA (#585). O principal só conhece a prosa do especialista. Em
# 21/09/2026 (conversa display 73) a conferência recusou a cotação e, dezesseis segundos depois, a Lia
# disse ao cliente "Vou seguir com assistência completa…": nada tinha sido aberto. Quem sabe se a
# cotação abriu é o sistema (`Delivery#runs`), e é o sistema que passa a dizer — ao principal, não ao
# cliente. Aqui a ferramenta é a assíncrona de verdade pelo `Bound`: a conferência recusa (o `precheck`)
# ou aceita e abre a execução; só o modelo é dublado, e ele chama a ferramenta pelo executor.
RSpec.describe Autonomia::Agents::Specialists::Runner do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda.')
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 7) }
  let(:specialist) do
    Autonomia::Agents::Specialist.create!(agent: agent, name: 'Especialista de Automóvel', slug: 'auto',
                                          description: 'cotação de automóvel', instruction: 'Você cota automóvel.')
  end
  let(:recusa) { 'Antes de cotar, corrija ou complete: coverage.assistance24h — 2000 não existe nesta cobertura.' }
  let(:resposta) { { resposta: 'Já estou cuidando da renovação.', dados_faltando: [] }.to_json }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  # O modelo dublado chama a ferramenta pelo executor, uma vez por item de `rodadas`, e devolve `texto`.
  def modelo(rodadas:, texto: resposta)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'cred')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      rodadas.times { |i| executor.call([{ 'name' => 'cotar_teste', 'arguments' => '{"placa":"ABC1D23"}', 'call_id' => "c#{i}" }]) }
      { text: texto }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  # A conferência de cada tentativa, na ordem: texto = recusa, nil = aceita.
  def ferramenta(*conferencias)
    fila = conferencias.dup
    nativa = build_async_tool(slug: 'cotar_teste', precheck: -> { fila.shift })
    allow(specialist).to receive(:tools).and_return([Autonomia::Agents::Tools::Bound.new(agent: agent, native: nativa)])
  end

  def consultar
    described_class.new(specialist: specialist, request: 'cotar a renovação', delivery: delivery).call
  end

  it 'conferência recusou e nada abriu: o principal fica sabendo, com o que não pode dizer' do
    ferramenta(recusa)
    modelo(rodadas: 1)

    saida = consultar

    expect(delivery.runs).to be_empty
    expect(saida).to start_with('Já estou cuidando da renovação.')
    expect(saida).to end_with(described_class::COTACAO_NAO_ABERTA)
  end

  it 'a cotação abriu: o principal fica sabendo que abriu' do
    ferramenta(nil)
    modelo(rodadas: 1)

    saida = consultar

    expect(delivery.runs.size).to eq(1)
    expect(saida).to end_with(described_class::COTACAO_ABERTA)
    expect(saida).not_to include(described_class::COTACAO_NAO_ABERTA)
  end

  it 'recusou, o especialista corrigiu e chamou de novo no mesmo turno: vale o que aconteceu no fim, abriu' do
    ferramenta(recusa, nil)
    modelo(rodadas: 2)

    saida = consultar

    expect(delivery.runs.size).to eq(1)
    expect(saida).to end_with(described_class::COTACAO_ABERTA)
  end

  # MAIS DE UMA RODADA (#585). Com `max_rodadas: 1` — o padrão do cliente — a recusa da conferência
  # chegava ao especialista na ida de FECHAMENTO, já sem ferramenta: ele sabia a troca ("deve ser usada a
  # completa") e não tinha como chamar de novo. Foi a cadeia de 21/09. Medido com o modelo real: 0 de 3
  # correções no turno com uma rodada.
  it 'o especialista tem rodadas para corrigir uma recusa e chamar de novo no mesmo turno' do
    ferramenta(nil)
    modelo(rodadas: 0)

    consultar

    expect(Crm::Ai::ResponsesClient.new(credential: 'x')).to have_received(:create_with_tool_executor)
      .with(hash_including(max_rodadas: described_class::RODADAS_DE_FERRAMENTA))
    expect(described_class::RODADAS_DE_FERRAMENTA).to be >= 3
  end

  # O VALOR RECUSADO CHEGA AO REGISTRO (#585): a conferência o entrega, e é o `Bound` que o leva à linha.
  it 'a recusa da conferência registra o valor da cobertura recusada' do
    linhas = []
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_starting_with(Autonomia::Agents::Tools::Recusa::PREFIXO)) { |t| linhas << t }
    ferramenta(Autonomia::Agents::Tools::Native::Conferencia.new(texto: recusa, faltando: ['coverage.assistance24h'], motivo: 'faltam_dados',
                                                                 recusados: { 'coverage.assistance24h' => 2000 }))
    modelo(rodadas: 1)

    consultar

    expect(linhas.join).to include('recusados=coverage.assistance24h=2000')
  end

  it 'o especialista não tentou cotar (respondeu uma dúvida): nenhuma situação é dita' do
    ferramenta(nil)
    modelo(rodadas: 0, texto: { resposta: 'Franquia é o valor que você paga no conserto.', dados_faltando: [] }.to_json)

    expect(consultar).to eq('Franquia é o valor que você paga no conserto.')
  end

  it 'o especialista caiu depois de tentar e nada abriu: a situação vai junto da falha' do
    ferramenta(recusa)
    modelo(rodadas: 1, texto: '<html>manutencao</html>')

    expect(consultar).to eq("#{described_class::INDISPONIVEL} #{described_class::COTACAO_NAO_ABERTA}")
  end
end
