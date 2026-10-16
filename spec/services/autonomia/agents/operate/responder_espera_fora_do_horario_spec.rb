require 'rails_helper'

# #1691 caso 1, ponta a ponta no Responder: conversa à espera de pessoa, fora do horário da caixa, agente em "Sempre". O
# contexto chega ao modelo como item `developer` logo antes da pergunta, nunca na instrução do dono, e só com a Fase 2.
# O Answerer e o PromptBuilder são os de verdade; só o cliente da IA é dublado, guardando o pedido.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo', working_hours_enabled: true) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.',
                                     config: { 'with_knowledge' => false, 'response_window' => 'always' })
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:pedidos) { [] }
  let(:instrucoes) { [] }
  let(:modelo) do
    { reply: 'Certo!', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
      answered_from_knowledge: false }.to_json
  end
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      # Quinta-feira, 22h em São Paulo: a caixa (seg a sex, 9h às 17h) está fechada.
      travel_to(Time.find_zone('America/Sao_Paulo').local(2026, 10, 15, 22, 0)) { example.run }
    end
  end

  before do
    conversation.update!(ai_assignee: agent_bot)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'x'))
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(cliente).to receive(:create_with_tool_executor) do |instructions:, input:, **|
      instrucoes << instructions
      pedidos << input
      { text: modelo }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def espera_pessoa!
    conversation.update!(additional_attributes: { 'bot_handoff_waiting_since' => Time.current.iso8601 })
  end

  # O relógio está parado (travel_to): cada mensagem ganha um segundo a mais, para a ordem da conversa ser a da escrita.
  def escreve(tipo, texto, sender: nil)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: tipo, content: texto, sender: sender,
                     created_at: Time.current - 60 + conversation.messages.count)
  end

  def responder(ultima)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  def developer(input)
    input.select { |item| item[:role] == 'developer' }.flat_map { |item| item[:content] }.pluck(:text)
  end

  def contexto_esperado
    Autonomia::Agents::Operate::EsperaForaDoHorario.new(conversation: conversation.reload).texto
  end

  it 'esperando pessoa e fora do horário: o contexto vai como developer logo antes da pergunta, e a IA responde' do
    espera_pessoa!
    escreve(:incoming, 'Oi')
    resultado = responder(escreve(:incoming, 'Alguém vai me atender?'))

    input = pedidos.sole
    expect(input[-2]).to eq(role: 'developer', content: [{ type: 'input_text', text: contexto_esperado }])
    expect(contexto_esperado).to include('A equipe volta amanhã (sexta-feira, 16/10) às 09:00.')
    expect(input.last[:content].first[:text]).to eq('Alguém vai me atender?')
    expect(instrucoes.sole).not_to include('esperando alguém da equipe')
    expect(resultado.status).to eq(:replied)
    expect(conversation.messages.outgoing.where(sender: agent_bot).pluck(:content)).to eq(['Certo!'])
  end

  it 'com mensagem da equipe na janela, a regra da equipe e a espera vão juntas no mesmo item' do
    espera_pessoa!
    escreve(:incoming, 'Oi')
    escreve(:outgoing, 'Já vejo isso para você.', sender: ana)
    responder(escreve(:incoming, 'E aí?'))

    regra = Autonomia::Agents::Operate::MolduraDaEquipe.regra(Autonomia::Agents::Operate::MolduraDaEquipe.marca(conversation))
    expect(developer(pedidos.sole)).to eq(["#{regra}\n\n#{contexto_esperado}"])
  end

  it 'sem espera de pessoa: nenhum contexto do turno' do
    responder(escreve(:incoming, 'Oi'))

    expect(developer(pedidos.sole)).to be_empty
  end

  it 'no horário da caixa: nenhum contexto do turno' do
    espera_pessoa!
    inbox.working_hours.find_by(day_of_week: 4).update!(open_all_day: true)
    responder(escreve(:incoming, 'Oi'))

    expect(inbox.reload.out_of_office?).to be(false)
    expect(developer(pedidos.sole)).to be_empty
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'igual à main: nenhum contexto do turno' do
      espera_pessoa!
      responder(escreve(:incoming, 'Alguém vai me atender?'))

      expect(developer(pedidos.sole)).to be_empty
    end
  end
end
