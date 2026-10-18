require 'rails_helper'

# #1479 PR-C, item 1: quando o cliente responde (in_reply_to) a opções ou link que ESTE agente mandou, a citação na
# query leva a versão em texto da oferta (as opções numeradas, "rótulo: endereço"), não só a pergunta. Mesma regra do
# histórico (`Interacao.oferecida?`): robô-espelho de um vínculo deste agente, com a marca dele. Fora da Lia e só com a
# Fase 2; fora disso a citação fica a de sempre.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:queries) { [] }
  let(:formato_das_opcoes) do
    { 'type' => 'options', 'header' => 'Agendamento', 'button' => 'Ver opções',
      'options' => [{ 'id' => 'manha', 'title' => 'Manhã' }, { 'id' => 'tarde', 'title' => 'Tarde' }] }
  end
  let(:url) { 'https://loja.exemplo.com/pedido/42' }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    resultado = Autonomia::Agents::AnswerResult.new(reply: 'Certo.', confidence: 0.9, handoff: { should: false, reason: nil })
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      queries << kwargs[:query]
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  def oferta(formato, agente_id: agent.id, sender: agent_inbox.agent_bot, content: 'Qual período?')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: sender,
                     content: content, content_attributes: { 'autonomia_agent_id' => agente_id, 'rich_message' => formato })
  end

  def responde_a(referenciada, content: 'Tarde')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content,
                     content_attributes: { 'in_reply_to' => referenciada.id })
  end

  def query
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform
    queries.last
  end

  it 'opções deste agente: a citação leva a pergunta e as opções numeradas' do
    responde_a(oferta(formato_das_opcoes))
    expect(query).to eq("[Em referência a sua mensagem: \"Qual período? 1. Manhã 2. Tarde\"]\nTarde")
  end

  it 'link deste agente: a citação leva o rótulo e o endereço' do
    responde_a(oferta({ 'type' => 'link_button', 'label' => 'Ver pedido', 'url' => url }, content: 'Seu pedido saiu.'), content: 'ok')
    expect(query).to eq("[Em referência a sua mensagem: \"Seu pedido saiu. Ver pedido: #{url}\"]\nok")
  end

  it 'oferta longa não é cortada nos 160 da citação comum' do
    opcoes = (1..10).map { |indice| { 'id' => "op#{indice}", 'title' => "Opção número #{indice}", 'description' => 'd' * 60 } }
    responde_a(oferta(formato_das_opcoes.merge('options' => opcoes)))
    expect(query).to include('10. Opção número 10')
  end

  it 'opções de outro agente: a citação de sempre, só o texto' do
    outro = criar_principal(account, nome: 'Outro')
    responde_a(oferta(formato_das_opcoes, agente_id: outro.id))
    expect(query).to eq("[Em referência a sua mensagem: \"Qual período?\"]\nTarde")
  end

  it 'mensagem de uma pessoa com o mesmo formato: a citação de sempre' do
    responde_a(oferta(formato_das_opcoes, sender: create(:user, account: account)))
    expect(query).not_to include('1. Manhã')
  end

  it 'robô que não é o espelho de um vínculo deste agente: a citação de sempre' do
    responde_a(oferta(formato_das_opcoes, sender: create(:agent_bot, account: account)))
    expect(query).not_to include('1. Manhã')
  end

  it 'mensagem do agente sem formato: a citação de sempre' do
    responde_a(oferta(nil))
    expect(query).to eq("[Em referência a sua mensagem: \"Qual período?\"]\nTarde")
  end

  context 'without Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'a citação de sempre' do
      responde_a(oferta(formato_das_opcoes))
      expect(query).to eq("[Em referência a sua mensagem: \"Qual período?\"]\nTarde")
    end
  end

  it 'na Lia a oferta não conta' do
    referenciada = oferta(formato_das_opcoes)
    lia = instance_double(Autonomia::Agents::Agent, agent_type: 'insurance_quote', id: agent.id, account_id: account.id)
    expect(Autonomia::Agents::Interacao.oferta_do_agente?(referenciada, agent: lia)).to be(false)
    expect(Autonomia::Agents::Interacao.oferta_do_agente?(referenciada, agent: agent)).to be(true)
  end
end
