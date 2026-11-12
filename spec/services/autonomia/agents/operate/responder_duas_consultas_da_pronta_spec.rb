require 'rails_helper'

# #2918, de ponta a ponta: o caso que abriu a Issue. "Café torrado" na NCM volta o grupo 0901.2; o código da nota
# (0901.21.00) só vem na segunda consulta, pelo grupo. Com as rodadas do Experimente, as duas consultas acontecem no mesmo
# turno e o cliente recebe o código. Nada é dublado entre o Responder e a fonte, salvo o HTTP: a OpenAI e a BrasilAPI
# respondem pelo WebMock (o laço de rodadas é o do `ResponsesClient` de verdade).
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:ncm_api) { 'https://brasilapi.com.br/api/ncm/v1' }
  let(:corpos) { [] }
  let(:resposta_final) do
    { reply: 'O NCM do café torrado não descafeinado é 0901.21.00.', confidence: 0.9, should_handoff: false,
      handoff_reason: nil, used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
    incluir_pronta('ncm', conta: account, agente: agent)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
    conversation.update!(assignee_agent_bot_id: agent_bot.id)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming,
                     content: 'qual o NCM do café torrado?')
    a_fonte_responde
    o_modelo_consulta_duas_vezes
  end

  # As respostas reais da BrasilAPI (#2917): a palavra traz o grupo 0901.2; o grupo é buscado pela posição dele
  # ("search=0901"), que traz os códigos da nota.
  def a_fonte_responde
    { 'café torrado' => 'ncm_busca_cafe_torrado.json', '0901' => 'ncm_busca_0901.json' }.each do |busca, arquivo|
      stub_request(:get, ncm_api).with(query: { 'search' => busca })
                                 .to_return(status: 200, body: Rails.root.join('spec/fixtures/ferramentas_prontas', arquivo).read,
                                            headers: { 'Content-Type' => 'application/json' })
    end
  end

  def chamada(call_id, busca)
    { output: [{ type: 'function_call', name: 'pronta_ncm', call_id: call_id,
                 arguments: { consulta: 'buscar', busca: busca }.to_json }] }
  end

  # 1ª ida: busca pelo produto. 2ª: busca pelo grupo que voltou. 3ª: responde com o código da nota.
  def o_modelo_consulta_duas_vezes
    respostas = [chamada('c1', 'café torrado'), chamada('c2', '0901.2'), { output_text: resposta_final }]
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      { status: 200, body: respostas[corpos.size - 1].to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def saidas_das_ferramentas(corpo)
    corpo['input'].select { |item| item['type'] == 'function_call_output' }.map { |item| JSON.parse(item['output']) }
  end

  def responder
    described_class.new(conversation: conversation, agent_inbox: agent_inbox,
                        reply_to_message_id: conversation.messages.incoming.last.id).perform
  end

  shared_examples 'duas consultas no mesmo turno' do
    it 'as duas consultas acontecem no mesmo turno e o cliente recebe o código da nota', :aggregate_failures do
      result = responder

      expect(result.status).to eq(:replied)
      expect(a_request(:get, ncm_api).with(query: { 'search' => 'café torrado' })).to have_been_made.once
      expect(a_request(:get, ncm_api).with(query: { 'search' => '0901' })).to have_been_made.once
      expect(corpos.size).to eq(3)
      # As três idas levam a pronta: a terceira ainda podia consultar, e respondeu.
      expect(corpos.map { |corpo| corpo['tools'].to_a.pluck('name').include?('pronta_ncm') }).to eq([true, true, true])
      # A segunda ida já leu o grupo; a terceira, o código da nota.
      expect(saidas_das_ferramentas(corpos[1]).last.dig('dados', 'itens').pluck('codigo')).to eq(['0901.2'])
      expect(saidas_das_ferramentas(corpos[2]).last.dig('dados', 'itens').pluck('codigo')).to include('0901.21.00')
      expect(conversation.messages.outgoing.last.content).to include('0901.21.00')
    end
  end

  it_behaves_like 'duas consultas no mesmo turno'

  # Com a consulta em segundo plano (#2749), cada rodada abre a janela dela (8 s): a segunda consulta também chega a tempo.
  context 'when a consulta roda em segundo plano' do
    before do
      ligar_consulta_em_segundo_plano
      relogio_do_turno { rodar_consultas }
    end

    it_behaves_like 'duas consultas no mesmo turno'

    it 'cada consulta abre a execução dela, no mesmo turno' do
      responder

      expect(Autonomia::Agents::ToolRun.where(slug: 'pronta_ncm').count).to eq(2)
    end
  end
end
