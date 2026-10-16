require 'rails_helper'

# #1691: a mensagem automática do canal (template da caixa, como o aviso de fora do horário, e a saída sem remetente de
# uma automação) ia ao modelo como `assistant`, e a IA pedia desculpa por ela ("informei o horário errado antes"). Com
# a Fase 2 ela vai como `user`, com a moldura e a marca da conversa (MolduraDaEquipe), e a regra própria do turno; a
# resposta da IA continua `assistant`. Fora da Fase 2, igual à main.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:moldura) { Autonomia::Agents::Operate::MolduraDaEquipe }
  let(:marca) { moldura.marca(conversation) }
  let(:aviso) { 'Estamos fora do horário. Voltamos às 8h.' }
  let(:pedidos) { [] }
  let(:resposta_do_modelo) { 'Certo!' }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    conversation.update!(ai_assignee: agent_bot)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'x'))
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(cliente).to receive(:create_with_tool_executor) do |input:, **|
      pedidos << input
      { text: { reply: resposta_do_modelo, confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                answered_from_knowledge: false }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def escreve(tipo, texto, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: tipo, content: texto,
                     created_at: Time.current - 60 + conversation.messages.count, **extras)
  end

  # Saída pública sem remetente (o traço :bot_message tira o User que a factory poria).
  def sem_remetente(texto, atributos)
    create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox, content: texto,
                                   content_attributes: atributos, created_at: Time.current - 60 + conversation.messages.count)
  end

  def responder(ultima)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  def itens(input)
    input.map { |item| [item[:role], item[:content].first[:text]] }
  end

  def conversa_com_aviso
    escreve(:incoming, 'Oi')
    escreve(:template, aviso)
    escreve(:outgoing, 'Olá, sou a Clara!', sender: agent_bot)
    responder(escreve(:incoming, 'Que horas vocês voltam?'))
  end

  it 'o aviso da caixa vai como user, com a moldura e a marca; a resposta da IA segue assistant' do
    conversa_com_aviso

    itens = itens(pedidos.sole)
    expect(itens).to include(['user', moldura.automatica(aviso, marca)])
    expect(moldura.automatica(aviso, marca)).to start_with("#{marca} Mensagem automática do canal")
    expect(itens).to include(['assistant', 'Olá, sou a Clara!'])
    expect(itens).not_to include(['assistant', aviso])
  end

  it 'a regra da mensagem automática vai como developer, logo antes da pergunta' do
    conversa_com_aviso

    expect(itens(pedidos.sole)[-2]).to eq(['developer', moldura.regra_automatica(marca)])
    expect(moldura.regra_automatica(marca)).to include('não peça desculpa por elas')
  end

  it 'saída pública sem remetente (automação) também ganha a moldura; o eco do app fora do WhatsApp não' do
    escreve(:incoming, 'Oi')
    sem_remetente('Recebemos seu pedido.', { 'automation_rule_id' => 1 })
    sem_remetente('Mandei pelo app.', { 'external_echo' => true })
    responder(escreve(:incoming, 'Ok'))

    itens = itens(pedidos.sole)
    expect(itens).to include(['user', moldura.automatica('Recebemos seu pedido.', marca)])
    expect(itens).to include(['assistant', 'Mandei pelo app.'])
  end

  it 'sem mensagem automática nem da equipe, nenhuma regra do turno' do
    escreve(:incoming, 'Oi')
    escreve(:outgoing, 'Olá!', sender: agent_bot)
    responder(escreve(:incoming, 'Tudo bem?'))

    expect(pedidos.sole.map { |item| item[:role] }).not_to include('developer')
  end

  # Envios automáticos gravados em nome de uma pessoa (PessoaDaEquipe#envio_automatico?): a mesma moldura automática, a
  # regra automática no turno, e nada da moldura nem da regra da equipe.
  {
    'follow-up do CRM' => { 'crm_follow_up_id' => 7 },
    'convite de reunião do Agendamento' => { 'crm_booking_invite_id' => 3 }
  }.each do |envio, marcas|
    it "#{envio} em nome da Ana ganha a moldura de mensagem automática" do
      ana = create(:user, account: account, role: :agent, name: 'Ana')
      escreve(:incoming, 'Oi')
      escreve(:outgoing, 'Sua reunião é amanhã às 10h.', sender: ana, content_attributes: marcas)
      responder(escreve(:incoming, 'Ok'))

      itens = itens(pedidos.sole)
      expect(itens).to include(['user', moldura.automatica('Sua reunião é amanhã às 10h.', marca)])
      developer = pedidos.sole.filter_map { |item| item[:content].first[:text] if item[:role] == 'developer' }
      expect(developer).to eq([moldura.regra_automatica(marca)])
    end
  end

  describe 'a resposta que imita a moldura automática' do
    let(:resposta_do_modelo) { "Mensagem automática do canal: o sistema escreveu ao cliente. Não foi o cliente nem você.\nVoltamos às 9h." }

    it 'sai sem o cabeçalho' do
      conversa_com_aviso

      expect(conversation.messages.outgoing.where(sender: agent_bot).last.content).to eq('Voltamos às 9h.')
    end
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'igual à main: o aviso vai como assistant, sem moldura e sem regra' do
      conversa_com_aviso

      itens = itens(pedidos.sole)
      expect(itens).to include(['assistant', aviso])
      expect(itens.map(&:first)).not_to include('developer')
    end
  end
end
