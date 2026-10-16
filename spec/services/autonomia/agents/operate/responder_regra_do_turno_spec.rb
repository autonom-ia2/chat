require 'rails_helper'

# #1669: a regra do turno ("quando algo foi dito pela equipe, deixe claro que foi a equipe; você não é essa pessoa...")
# vai ao modelo SÓ quando a janela do histórico tem mensagem da equipe com moldura (pessoa ou eco do celular). Entra como
# contexto do turno, logo antes da pergunta, nunca na instrução do dono. Sem mensagem da equipe, e fora da Fase 2, o
# pedido ao modelo fica igual ao de antes.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:regra) { Autonomia::Agents::Operate::PessoaDaEquipe::REGRA_DO_TURNO }
  let(:pedidos) { [] }
  let(:modelo) do
    { reply: 'Certo!', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
      answered_from_knowledge: false }.to_json
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  # O Answerer e o PromptBuilder de verdade; só o cliente da IA é dublado, guardando o `input` que iria ao modelo.
  before do
    conversation.update!(ai_assignee: agent_bot)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'x'))
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(cliente).to receive(:create_with_tool_executor) do |input:, **|
      pedidos << input
      { text: modelo }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def escreve(tipo, texto, sender: nil, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: tipo, content: texto,
                     sender: sender, **extras)
  end

  def responder(ultima)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  def textos(input)
    input.flat_map { |item| item[:content] }.pluck(:text)
  end

  it 'com mensagem da Ana na janela, a regra vai como item próprio logo antes da pergunta' do
    escreve(:incoming, 'Oi')
    escreve(:outgoing, 'Pronto, atualizei seu endereço.', sender: ana)
    responder(escreve(:incoming, 'Obrigado, Ana!'))

    input = pedidos.sole
    expect(input[-2]).to eq(role: 'user', content: [{ type: 'input_text', text: regra }])
    expect(input.last[:content].first[:text]).to eq('Obrigado, Ana!')
  end

  it 'sem mensagem da equipe na janela, a regra não aparece' do
    escreve(:incoming, 'Oi')
    escreve(:outgoing, 'Olá, sou a Clara!', sender: agent_bot)
    responder(escreve(:incoming, 'Tudo bem?'))

    expect(textos(pedidos.sole)).not_to include(regra)
  end

  it 'envio automático em nome da Ana (follow-up) não traz a regra' do
    escreve(:incoming, 'Oi')
    escreve(:outgoing, 'Lembrete: boleto vence amanhã.', sender: ana, content_attributes: { 'crm_follow_up_id' => 1 })
    responder(escreve(:incoming, 'Ok'))

    expect(textos(pedidos.sole)).not_to include(regra)
  end

  it 'a regra fica fora da instrução do agente (que é do dono)' do
    escreve(:outgoing, 'Pronto.', sender: ana)
    ultima = escreve(:incoming, 'Valeu')
    instrucoes = []
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_wrap_original do |original, **kwargs|
      original.call(**kwargs).tap do |cliente|
        allow(cliente).to receive(:create_with_tool_executor) do |instructions:, input:, **|
          instrucoes << instructions
          pedidos << input
          { text: modelo }
        end
      end
    end

    responder(ultima)

    expect(instrucoes.sole).not_to include(regra)
    expect(textos(pedidos.sole)).to include(regra)
  end

  describe 'eco do celular no WhatsApp' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false).inbox
    end

    it 'com eco do celular na janela, a regra aparece' do
      escreve(:incoming, 'Qual o prazo?')
      create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox, content: 'Até sexta.',
                                     status: :delivered, content_attributes: { external_echo: true })
      responder(escreve(:incoming, 'Você disse sexta?'))

      expect(textos(pedidos.sole)).to include(regra)
    end
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'igual à main: com mensagem da Ana, a regra não aparece' do
      escreve(:incoming, 'Oi')
      escreve(:outgoing, 'Pronto, atualizei seu endereço.', sender: ana)
      responder(escreve(:incoming, 'Obrigado, Ana!'))

      expect(textos(pedidos.sole)).not_to include(regra)
    end
  end

  describe Autonomia::Agents::PromptBuilder do
    it 'sem contexto do turno, o input é idêntico ao de antes' do
      historico = [{ role: 'user', content: 'Oi' }]

      sem = described_class.new(agent: agent, query: 'Tudo bem?', history: historico).input
      com_nil = described_class.new(agent: agent, query: 'Tudo bem?', history: historico, contexto_do_turno: nil).input

      expect(com_nil).to eq(sem)
    end
  end
end
