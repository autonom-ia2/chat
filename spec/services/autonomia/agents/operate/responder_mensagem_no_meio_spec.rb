require 'rails_helper'

# #3225, o caso real, de ponta a ponta: o turno A abre com os dados da viagem, `cotar_seguro_viagem` roda, e a mensagem B
# ("Conhece lá?") chega DEPOIS de a ferramenta voltar e antes de A postar. Com a flag: uma resposta só, uma chamada à
# Universal, um PDF, e o turno de B não posta. Nada é dublado entre o ReplyJob e a seguradora, salvo o HTTP: a OpenAI e a
# Universal respondem pelo WebMock (o laço é o do `ResponsesClient` de verdade, e a ferramenta é a de verdade).
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2(ligada: false) }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', status: :active, enabled: true,
                                     instruction: 'retrato', config: { 'contratado' => marca, 'with_knowledge' => false })
  end
  let!(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:corpos) { [] }
  let(:linhas) { [] }
  let!(:pergunta) { cliente_escreve('Portugal, ida e volta em dezembro, 45 anos') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    enable_test_encryption!
    marcar_corretora!(account)
    account.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas', 'agente_ferramentas_prontas_consultas',
                             Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta-teste' })
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste', source: :hook }))
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.6.192'])
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: agent, login: 'corretor.teste', senha: 's3nha-teste',
                                                  estado: 'ok', capacidades: { 'tarifa_acordo' => true })
    stub_request(:get, "#{universal}/v1/destinos").to_return(status: 200, body: file_fixture('../universal/destinos.json').read)
    stub_request(:post, "#{universal}/v1/Cotacao").to_return(status: 200, body: file_fixture('../universal/cotacao.json').read)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_including('[autonomia]')) { |linha| linhas << linha }
  end

  after do
    fala = Autonomia::Agents::Operate::FalaEmCurso
    [fala.chave_ocupada(conversation.id), fala.chave_do_fim(conversation.id)].each { |chave| Redis::Alfred.delete(chave) }
  end

  def universal = 'https://api-br.universal-assistance.com'

  def entrega = Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo

  def rascunho = resposta('Portugal, 5 dias: o Especial UA 100K sai por R$ 360,00. O PDF vai junto.')

  def final = resposta('Conheço sim! Portugal é lindo. E a cotação: o Especial UA 100K sai por R$ 360,00. O PDF vai junto.')

  def viagem
    { 'destinos' => ['pt'], 'data_saida' => 20.days.from_now.to_date.iso8601, 'data_retorno' => 25.days.from_now.to_date.iso8601,
      'idades' => [45], 'motivo' => nil }
  end

  def cliente_escreve(texto)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto)
  end

  def resposta(texto)
    { reply: texto, confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
      answered_from_knowledge: false }.to_json
  end

  def gatilho(mensagem)
    Autonomia::Agents::Operate::ReplyJob.perform_now(conversation.id, mensagem.id, 'trigger')
  end

  def settle(mensagem)
    Autonomia::Agents::Operate::ReplyJob.perform_now(conversation.id, mensagem.id, 'settle')
  end

  # 1ª ida: cota. 2ª (o fechamento, sem ferramenta): o rascunho; é durante ela que B chega (e o gatilho dela roda). 3ª:
  # a resposta única. `durante` roda na ida de número `na_ida`.
  def a_ia_responde(durante: nil, na_ida: 2)
    chamada = { output: [{ type: 'function_call', name: 'cotar_seguro_viagem', call_id: 'c1', arguments: viagem.to_json }] }
    respostas = [chamada, { output_text: rascunho }, { output_text: final }]
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      durante&.call if corpos.size == na_ida
      { status: 200, body: respostas[corpos.size - 1].to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def enviadas
    conversation.messages.outgoing.order(:id).to_a
  end

  def jobs_dos_cartoes
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |item| item[:job] == Autonomia::Agents::Operate::EnviarCartoesJob }
  end

  def rodar_cartoes
    2.times do
      enviadas.each { |m| m.update_column(:source_id, "wamid.#{m.id}") if m.source_id.blank? } # rubocop:disable Rails/SkipsModelValidations
      jobs = jobs_dos_cartoes
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete_if { |item| jobs.include?(item) }
      jobs.each { |item| item[:job].perform_now(*ActiveJob::Arguments.deserialize(item[:args])) }
    end
  end

  def pdfs
    enviadas.select { |mensagem| mensagem.content_attributes.key?(entrega::CHAVE) }
  end

  def textos_do_pedido(corpo)
    corpo['input'].map { |item| [item['role'] || item['type'], Array(item['content']).first.to_h['text']] }
  end

  it 'B chega depois da cotação: uma resposta só, uma chamada à Universal, um PDF, e o turno de B não posta', :aggregate_failures do
    segunda = nil
    a_ia_responde(durante: -> { segunda = cliente_escreve('Conhece lá?').tap { |b| gatilho(b) } })
    gatilho(pergunta)

    settle(pergunta)

    expect(a_request(:post, "#{universal}/v1/Cotacao")).to have_been_made.once
    expect(corpos.size).to eq(3)
    expect(corpos[1]).not_to have_key('tools') # o fechamento de sempre
    expect(corpos[2]['tools']).to be_present # a volta pode chamar ferramenta (D1)
    expect(textos_do_pedido(corpos[2]).last(3)).to match(
      [['assistant', rascunho], ['developer', a_string_including('ainda não foi enviada')], ['user', 'Conhece lá?']]
    )
    expect(corpos[2]['input'].map { |item| item['type'] }).not_to include('reasoning')

    resposta_unica = enviadas.sole
    expect(resposta_unica.content).to eq(JSON.parse(final)['reply'])
    expect(resposta_unica.content_attributes).to include('autonomia_reply_to_message_id' => pergunta.id,
                                                         'autonomia_lidas_no_turno' => [segunda.id])
    evento = agent.events.where(event_type: :replied).sole
    expect(evento.metadata).to include('lidas_no_turno' => [segunda.id], 'voltas' => 1)
    expect(Crm::AiUsageEvent.where(feature: 'agente_resposta_volta').count).to eq(1)

    # O turno de B: a resposta de A já leu B. Não chama a IA e não posta.
    settle(segunda)
    expect(corpos.size).to eq(3)
    expect(enviadas.size).to eq(1)
    expect(linhas.join).to include('respondida_junto', "msg=#{segunda.id}", 'etapa=settle')

    rodar_cartoes
    expect(pdfs.size).to eq(1)
    expect(enviadas.last).to eq(pdfs.sole)
  end

  it 'flag desligada: o caminho de hoje (A superado, sem leitura, sem volta), e o pedido não leva nada novo', :aggregate_failures do
    account.disable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
    allow(Autonomia::Agents::Operate::LeituraNoTurno).to receive(:new).and_call_original
    allow(Autonomia::Agents::Operate::LeituraNoTurno).to receive(:respondida_propria?).and_call_original
    segunda = nil
    a_ia_responde(durante: -> { segunda = cliente_escreve('Conhece lá?').tap { |b| gatilho(b) } })
    gatilho(pergunta)

    settle(pergunta)

    expect(corpos.size).to eq(2)
    expect(enviadas).to be_empty
    expect(linhas.join).to include('motivo=turno_superado')
    expect(linhas.join).not_to include('mensagem_lida_no_turno', 'leitura_no_silencio')
    expect(Autonomia::Agents::Operate::LeituraNoTurno).not_to have_received(:new)
    expect(Autonomia::Agents::Operate::LeituraNoTurno).not_to have_received(:respondida_propria?)
    expect(Crm::AiUsageEvent.where(feature: 'agente_resposta_volta')).to be_empty
    expect(segunda).to be_present
  end

  it 'B chega depois da última leitura (o caminho de hoje): A é superado e registra que B chegou depois', :aggregate_failures do
    segunda = nil
    # B chega logo depois de A ler pela última vez (antes de enviar, sem nada novo), e antes da hora de postar.
    allow(Autonomia::Agents::Operate::LeituraNoTurno).to receive(:new).and_wrap_original do |original, **kwargs, &bloco|
      original.call(**kwargs, &bloco).tap do |leitura|
        allow(leitura).to receive(:antes_de_enviar).and_wrap_original do |ler, *args, **opcoes|
          ler.call(*args, **opcoes).tap { segunda ||= cliente_escreve('Conhece lá?').tap { |b| gatilho(b) } }
        end
      end
    end
    a_ia_responde
    gatilho(pergunta)

    settle(pergunta)

    expect(corpos.size).to eq(2)
    expect(enviadas).to be_empty
    expect(linhas.join).to include('leitura_no_silencio', 'motivo=turno_superado', "superou=#{segunda.id}", 'depois_da_leitura=true')
  end

  describe 'em pedaços' do
    around { |example| with_modified_env(AI_HUMANIZE_DELIVERY: 'true') { example.run } }

    before do
      digitando = instance_double(Autonomia::Agents::Operate::TypingIndicator, on: nil, off: nil)
      allow(Autonomia::Agents::Operate::TypingIndicator).to receive(:new).and_return(digitando)
    end

    def cadeia
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.reverse.find { |item| item[:job] == Autonomia::Agents::Operate::ChunkedDeliveryJob }
      ActiveJob::Arguments.deserialize(job[:args])
    end

    it 'o 1º pedaço sai com a marca em B, grava B como lida; o PDF sai uma vez, no fim; B não posta', :aggregate_failures do
      segunda = nil
      a_ia_responde(durante: -> { segunda = cliente_escreve('Conhece lá?').tap { |b| gatilho(b) } })
      gatilho(pergunta)
      settle(pergunta)

      _conversa, _vinculo, reply_to, pedacos, _indice, meta = cadeia
      expect(meta).to include('lidas_no_turno' => [segunda.id], 'voltas' => 1)
      pedacos.each_index do |indice|
        Autonomia::Agents::Operate::ChunkedDeliveryJob.new.perform(conversation.id, agent_inbox.id, reply_to, pedacos, indice, meta)
      end

      expect(enviadas.size).to eq(pedacos.size)
      expect(enviadas.first.content_attributes['autonomia_lidas_no_turno']).to eq([segunda.id])
      expect(agent.events.where(event_type: :replied).sole.metadata).to include('lidas_no_turno' => [segunda.id])

      settle(segunda)
      expect(corpos.size).to eq(3)
      expect(enviadas.size).to eq(pedacos.size)

      rodar_cartoes
      expect(pdfs.size).to eq(1)
      expect(enviadas.last).to eq(pdfs.sole)
    end
  end
end
