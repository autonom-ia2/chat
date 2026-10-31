require 'rails_helper'

# #1479 F2: a localização que o cliente manda depois do pedido DESTE agente vai ao turno como dado (latitude, longitude
# e, quando vêm, nome e endereço), no contexto interno. Vale com `in_reply_to` apontando o pedido (oficial) e sem citar
# (WAHA e Híbrido, pelo clipe), desde que a última mensagem do agente na conversa seja o pedido. O histórico continua
# sem coordenadas (decisão de 17/10). Só com a Fase 2 e a flag `agentes_pedir_localizacao`; a Lia fica fora.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_pedir_localizacao') } }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:pedidos) { [] }
  let(:sao_paulo) { { 'latitude' => -23.5505, 'longitude' => -46.6333 } }
  let(:dado) { '{"localizacao_recebida":[{"latitude":-23.5505,"longitude":-46.6333}]}' }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    resultado = Autonomia::Agents::AnswerResult.new(reply: 'Certo.', confidence: 0.9, handoff: { should: false, reason: nil })
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      pedidos << kwargs
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  def do_agente(formato = { 'type' => 'location_request' }, agente_id: agent.id, conteudo: 'Pode me mandar sua localização?')
    atributos = { 'autonomia_agent_id' => agente_id, 'rich_message' => formato }.compact
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent_inbox.agent_bot,
                     content: conteudo, content_attributes: atributos)
  end

  def localizacao(local = sao_paulo, citada: nil)
    atributos = { 'shared_location' => local, 'in_reply_to' => citada&.id }.compact
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil,
                     content_attributes: atributos)
  end

  def contexto
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform
    pedidos.last[:contexto_do_turno].to_s
  end

  it 'citando o pedido (oficial): o dado vai no contexto interno do turno' do
    localizacao(citada: do_agente)
    expect(contexto).to include(dado)
  end

  it 'sem citar (WAHA e Híbrido, pelo clipe), logo depois do pedido: o dado vai' do
    do_agente
    localizacao
    expect(contexto).to include(dado)
  end

  it 'nome e endereço, quando vêm, vão junto' do
    do_agente
    localizacao(sao_paulo.merge('name' => 'Praça da Sé', 'address' => 'Praça da Sé, São Paulo - SP'))
    expect(contexto).to include('"nome":"Praça da Sé","endereco":"Praça da Sé, São Paulo - SP"')
  end

  it 'duas localizações seguidas depois do pedido: as duas, na ordem' do
    do_agente
    localizacao
    localizacao({ 'latitude' => -22.9068, 'longitude' => -43.1729 })
    expect(contexto).to include('[{"latitude":-23.5505,"longitude":-46.6333},{"latitude":-22.9068,"longitude":-43.1729}]')
  end

  it 'localização sem pedido: fica como hoje, sem coordenadas' do
    do_agente({ 'type' => 'options', 'header' => 'X', 'button' => 'Ver', 'options' => [{ 'id' => 'a', 'title' => 'A' }] })
    localizacao
    expect(contexto).not_to include('localizacao_recebida')
  end

  it 'pedido antigo seguido de outra resposta do agente: sem o dado' do
    do_agente
    do_agente(nil, conteudo: 'Tudo bem, seguimos por aqui.')
    localizacao
    expect(contexto).not_to include('localizacao_recebida')
  end

  it 'citando o pedido antigo, mesmo com o agente tendo falado depois: o dado vai' do
    pedido = do_agente
    do_agente(nil, conteudo: 'Tudo bem, seguimos por aqui.')
    localizacao(citada: pedido)
    expect(contexto).to include(dado)
  end

  it 'pedido de OUTRO agente da conta: sem o dado' do
    outro = criar_principal(account, nome: 'Outro')
    do_agente(agente_id: outro.id)
    localizacao
    expect(contexto).not_to include('localizacao_recebida')
  end

  it 'sem a flag na conta: sem o dado' do
    account.disable_features!('agentes_pedir_localizacao')
    do_agente
    localizacao
    expect(contexto).not_to include('localizacao_recebida')
  end

  context 'when o agente é a Lia (insurance_quote)' do
    let(:agent) { criar_principal(account, agent_type: 'insurance_quote') }

    it 'sem o dado' do
      do_agente
      localizacao
      expect(contexto).not_to include('localizacao_recebida')
    end
  end

  it 'coordenada fora da faixa ou que não é número não vai' do
    do_agente
    localizacao({ 'latitude' => 'abc', 'longitude' => -46.6 })
    localizacao({ 'latitude' => 91, 'longitude' => -46.6 })
    expect(contexto).not_to include('localizacao_recebida')
  end

  it 'a linha de telemetria leva só ids e a contagem, nunca coordenada' do
    do_agente
    recebida = localizacao
    saida = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(saida)
    contexto
    Rails.logger = original
    expect(saida.string).to include("[autonomia][turno] localizacao_recebida conv=#{conversation.id} agent=#{agent.id} msg=#{recebida.id} total=1")
    expect(saida.string).not_to include('23.5505')
  end
end
