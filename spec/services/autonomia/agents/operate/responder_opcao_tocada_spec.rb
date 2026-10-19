require 'rails_helper'

# #1479 PR-C, itens 2 e 3: o cliente tocou numa opção que ESTE agente ofereceu. Nos três caminhos (Cloud, caixa WAHA e
# Híbrido) o toque grava `content_attributes.selected_option` {id da opção, title} e `in_reply_to` = a oferta. O turno
# leva ao modelo, no contexto interno, o dado {"opcao_tocada": {"id", "titulo"}}; o modelo decide o que fazer. Nada de
# interpretar o texto digitado. A linha `opcao_tocada` da TelemetriaDoTurno leva só ids, nunca o título nem o texto.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:pedidos) { [] }
  let(:formato_das_opcoes) do
    { 'type' => 'options', 'header' => 'Agendamento', 'button' => 'Ver opções',
      'options' => [{ 'id' => 'manha', 'title' => 'Manhã' }, { 'id' => 'tarde', 'title' => 'Tarde' }] }
  end
  let(:dado) { '{"opcao_tocada":{"id":"tarde","titulo":"Tarde"}}' }

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

  def oferta(formato = formato_das_opcoes, agente_id: agent.id, sender: agent_inbox.agent_bot)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: sender,
                     content: 'Qual período?', content_attributes: { 'autonomia_agent_id' => agente_id, 'rich_message' => formato })
  end

  def toque(referenciada, opcao: { 'id' => 'tarde', 'title' => 'Tarde' }, content: 'Tarde')
    atributos = { 'in_reply_to' => referenciada&.id, 'selected_option' => opcao }.compact
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content,
                     content_attributes: atributos)
  end

  def contexto
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform
    pedidos.last[:contexto_do_turno].to_s
  end

  def linhas_do_log
    saida = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(saida)
    yield
    saida.string
  ensure
    Rails.logger = original
  end

  it 'toque numa opção deste agente: o dado vai no contexto interno do turno' do
    toque(oferta)
    expect(contexto).to include(dado)
  end

  it 'o título vem da opção oferecida; sem título no toque, também' do
    toque(oferta, opcao: { 'id' => 'tarde' }, content: 'qualquer coisa')
    expect(contexto).to include(dado)
  end

  it 'o título do toque nunca é usado: vale o da oferta' do
    toque(oferta, opcao: { 'id' => 'tarde', 'title' => 'Outro título' })
    expect(contexto).to include(dado)
    expect(contexto).not_to include('Outro título')
  end

  it 'id que a oferta não tem: nenhum dado e nenhuma linha' do
    toque(oferta, opcao: { 'id' => 'noite', 'title' => 'Noite' })
    log = linhas_do_log { expect(contexto).not_to include('opcao_tocada') }
    expect(log).not_to include('opcao_tocada')
  end

  it 'id maior que o da Meta: nenhum dado, mesmo se a oferta o tivesse' do
    longo = 'a' * (RichMessages::Types::Options::BUTTONS[:id] + 1)
    toque(oferta(formato_das_opcoes.merge('options' => [{ 'id' => longo, 'title' => 'Longa' }])), opcao: { 'id' => longo })
    expect(contexto).not_to include('opcao_tocada')
  end

  it 'aspas e quebra de linha no id e no título da oferta saem escapadas no JSON, numa linha' do
    id = "ta\"r\nde"
    toque(oferta(formato_das_opcoes.merge('options' => [{ 'id' => id, 'title' => "Tarde \"boa\"\nfim" }])), opcao: { 'id' => id })
    linha = contexto.lines.find { |texto| texto.include?('opcao_tocada') }
    expect(linha).to end_with('{"opcao_tocada":{"id":"ta\\"r\\nde","titulo":"Tarde \\"boa\\"\\nfim"}}')
    expect(JSON.parse(linha[linha.index('{')..])).to eq('opcao_tocada' => { 'id' => id, 'titulo' => "Tarde \"boa\"\nfim" })
  end

  it 'a mensagem recebida fica como está (conteúdo e in_reply_to)' do
    referenciada = oferta
    recebida = toque(referenciada)
    contexto
    expect(recebida.reload.content).to eq('Tarde')
    expect(recebida.content_attributes['in_reply_to']).to eq(referenciada.id)
  end

  it 'texto digitado sem toque: nenhum dado, o modelo lê o texto' do
    toque(oferta, opcao: nil, content: '2')
    expect(contexto).not_to include('opcao_tocada')
  end

  it 'toque sem in_reply_to: nenhum dado' do
    toque(nil)
    expect(contexto).not_to include('opcao_tocada')
  end

  it 'toque numa oferta de outro agente: nenhum dado' do
    toque(oferta(agente_id: criar_principal(account, nome: 'Outro').id))
    expect(contexto).not_to include('opcao_tocada')
  end

  it 'toque numa mensagem de outro robô com a marca deste agente: nenhum dado' do
    toque(oferta(sender: create(:agent_bot, account: account)))
    expect(contexto).not_to include('opcao_tocada')
  end

  it 'toque antigo, já respondido: o turno seguinte não o leva' do
    toque(oferta)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent_bot,
                     content: 'Anotado.')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'obrigado')
    expect(contexto).not_to include('opcao_tocada')
  end

  # O turno sem mensagem nova do cliente (ex.: o da passagem, #1630): o último toque, já respondido, não é deste turno.
  it 'toque já respondido e nenhuma mensagem nova: nenhum dado' do
    toque(oferta)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent_bot,
                     content: 'Anotado.')
    responder = described_class.new(conversation: conversation, agent_inbox: agent_inbox)
    expect(responder.send(:contexto_do_toque)).to be_nil
  end

  context 'without Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'nenhum dado e nenhuma linha' do
      toque(oferta)
      log = linhas_do_log { expect(contexto).not_to include('opcao_tocada') }
      expect(log).not_to include('opcao_tocada')
    end
  end

  it 'na Lia: nenhum dado' do
    agent.update_column(:agent_type, 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations
    toque(oferta)
    expect(contexto).not_to include('opcao_tocada')
  end

  it 'telemetria: só ids, nunca o título nem o texto do cliente' do
    referenciada = oferta
    recebida = toque(referenciada, opcao: { 'id' => 'tarde', 'title' => 'TituloSecreto' }, content: 'TextoDoCliente')
    log = linhas_do_log { contexto }
    linha = log.lines.find { |texto| texto.include?('opcao_tocada') }
    expect(linha.strip).to eq("[autonomia][turno] opcao_tocada conv=#{conversation.id} agent=#{agent.id} msg=#{recebida.id} " \
                              "oferta=#{referenciada.id} opcao=tarde")
    expect(log).not_to include('TituloSecreto', 'TextoDoCliente', 'Tarde')
  end

  # A citação e o toque leem a mesma oferta: uma busca dela e uma dos robôs do agente no turno.
  it 'a oferta e os robôs do agente são buscados uma vez no turno' do
    referenciada = oferta
    toque(referenciada)
    allow(Autonomia::Agents::Interacao).to receive(:robos).and_call_original
    buscas = 0
    contar = lambda do |*, payload|
      buscas += 1 if payload[:sql].include?('"messages"."id" =') && payload[:binds].to_a.map { |bind| bind.try(:value) }.include?(referenciada.id)
    end
    resultado = ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { contexto }

    expect(resultado).to include(dado)
    expect(pedidos.last[:query]).to include('1. Manhã')
    expect(buscas).to eq(1)
    expect(Autonomia::Agents::Interacao).to have_received(:robos).once
  end

  describe 'Interacao.opcao_tocada' do
    it 'lê selected_option: só o id' do
      expect(Autonomia::Agents::Interacao.opcao_tocada(toque(oferta))).to eq('tarde')
    end

    it 'sem selected_option, sem id ou id maior que o da Meta: nil' do
      longo = 'a' * (RichMessages::Types::Options::BUTTONS[:id] + 1)
      expect(Autonomia::Agents::Interacao.opcao_tocada(toque(oferta, opcao: nil))).to be_nil
      expect(Autonomia::Agents::Interacao.opcao_tocada(toque(oferta, opcao: { 'title' => 'Tarde' }))).to be_nil
      expect(Autonomia::Agents::Interacao.opcao_tocada(toque(oferta, opcao: { 'id' => longo }))).to be_nil
      expect(Autonomia::Agents::Interacao.opcao_tocada(toque(oferta, opcao: { 'id' => 'a' * 256 }))).to eq('a' * 256)
      expect(Autonomia::Agents::Interacao.opcao_tocada(nil)).to be_nil
    end
  end
end
