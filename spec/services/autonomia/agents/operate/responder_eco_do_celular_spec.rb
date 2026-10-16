require 'rails_helper'

# #1669, decisão do Rodrigo (opção c): no WhatsApp, o que a equipe manda pelo app do celular volta como eco
# (`external_echo`, sem remetente). Com a Fase 2, entra no histórico com a moldura da equipe, sem nome, e NÃO cala a IA.
# O eco da própria mensagem da IA, reconciliado na bolha que já existe (WhatsappHybrid::EchoReconcilerExtension), segue
# como fala dela. Na corrida em que o eco da IA vira mensagem nova, o texto aparece de novo, como da equipe (efeito aceito).
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:historicos) { [] }
  let(:moldura) { Autonomia::Agents::Operate::PessoaDaEquipe::MOLDURA_DO_ECO }
  # O reconciliador de verdade, como no spec dele: liga o wamid do eco à bolha que já existe.
  let(:reconciliador) do
    Class.new do
      include WhatsappHybrid::EchoReconcilerExtension

      attr_reader :inbox, :messages_data

      def initialize(inbox, wamid)
        @inbox = inbox
        @messages_data = [{ id: wamid }]
      end

      public :reconcile_hybrid_echo
    end
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    conversation.update!(ai_assignee: agent_bot)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |history:, **|
      historicos << history
      resultado = Autonomia::Agents::AnswerResult.new(reply: 'Certo!', confidence: 0.9, handoff: { should: false, reason: nil },
                                                      used_knowledge: [], answered_from_knowledge: false)
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  def escreve(tipo, texto, sender: nil, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: tipo, content: texto,
                     sender: sender, **extras)
  end

  def eco(texto)
    create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox, content: texto,
                                   status: :delivered, content_attributes: { external_echo: true })
  end

  def responder(ultima)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  it 'o eco do celular entra no histórico com a moldura da equipe, sem nome' do
    escreve(:incoming, 'Oi, meu boleto venceu')
    eco('Te mando a segunda via já já')
    responder(escreve(:incoming, 'Obrigado'))

    expect(historicos.sole.second).to eq(role: 'user', content: "#{moldura}\nTe mando a segunda via já já")
  end

  it 'o eco do celular depois da mensagem do cliente NÃO cala a IA' do
    ultima = escreve(:incoming, 'Oi, meu boleto venceu')
    eco('Já vejo para você')

    resultado = responder(ultima)

    expect(resultado.message.content).to eq('Certo!')
  end

  it 'o eco da própria mensagem da IA, reconciliado na bolha dela, segue como fala dela (sem moldura)' do
    escreve(:incoming, 'Oi')
    da_ia = escreve(:outgoing, 'Olá, sou a Clara!', sender: agent_bot, source_id: '3EB0AAAA')
    reconciliador.new(inbox, 'wamid.ECO123').reconcile_hybrid_echo(da_ia)
    expect(da_ia.reload.content_attributes).not_to have_key('external_echo')

    responder(escreve(:incoming, 'Tudo bem?'))

    expect(historicos.sole.second).to eq(role: 'assistant', content: 'Olá, sou a Clara!')
  end

  it 'corrida: o eco da IA que virou mensagem nova aparece de novo, como da equipe pelo celular (efeito aceito)' do
    escreve(:incoming, 'Oi')
    escreve(:outgoing, 'Olá, sou a Clara!', sender: agent_bot)
    eco('Olá, sou a Clara!')

    responder(escreve(:incoming, 'Tudo bem?'))

    expect(historicos.sole[1..2]).to eq([{ role: 'assistant', content: 'Olá, sou a Clara!' },
                                         { role: 'user', content: "#{moldura}\nOlá, sou a Clara!" }])
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'igual à main: o eco do celular vai como assistant, sem moldura' do
      escreve(:incoming, 'Oi')
      eco('Te mando a segunda via')
      responder(escreve(:incoming, 'Obrigado'))

      expect(historicos.sole.second).to eq(role: 'assistant', content: 'Te mando a segunda via')
    end
  end

  describe 'fora do WhatsApp' do
    let(:inbox) { create(:inbox, account: account) }

    it 'o eco (de outro canal) segue como hoje, sem moldura' do
      escreve(:incoming, 'Oi')
      eco('Mensagem do app nativo')
      responder(escreve(:incoming, 'Obrigado'))

      expect(historicos.sole.second).to eq(role: 'assistant', content: 'Mensagem do app nativo')
    end
  end
end
