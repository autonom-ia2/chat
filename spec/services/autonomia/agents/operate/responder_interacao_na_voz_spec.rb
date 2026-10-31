require 'rails_helper'

# #1479: na resposta em voz, a interação (opções, link, pedido de localização) sai DEPOIS do áudio. O áudio vai com
# anexo e o `SendReplyJob` dele espera 2 s; a interação postada logo depois saía antes. Agora ela fica gravada no áudio
# (a âncora) e sai pelo `EnviarCartoesJob`, quando o áudio saiu para o canal, antes dos cartões. Áudio que falhou, pessoa
# da equipe que respondeu ou Fase 2 desligada: nada sai, com registro. O retry do turno nunca duplica a interação.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) do
    conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato', 'agentes_pedir_localizacao') }
  end
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:pagina) do
    create_booking_profile(account: account, host: create(:user, account: account, role: :agent), title: 'Clínica',
                           locations: [{ 'type' => 'in_person', 'label' => 'Unidade Centro', 'address' => 'Rua Direita, 100' }],
                           contact_phone: '+551140000473').tap do |gravada|
      lista = gravada.locations.map { |item| item.merge('latitude' => -23.5489, 'longitude' => -46.6388) }
      gravada.update_column(:locations, lista) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  let(:agent) { criar_principal(account, config: { 'with_knowledge' => false, 'booking_page_id' => pagina.id }) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:mapa) do
    local = Autonomia::Agents::Tools::Native::CartaoDaPagina.locais(pagina.reload).sole
    Autonomia::Agents::Tools::Native::CartaoDaPagina.cartao('location', local['id'], local['rich_message'])
  end
  let(:opcoes) do
    Autonomia::Agents::Interacao.do_modelo(
      { 'tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?',
        'opcoes' => [{ 'id' => 'manha', 'titulo' => 'Manhã' }, { 'id' => 'tarde', 'titulo' => 'Tarde' }] }, enderecos: Set.new
    )
  end
  let(:pedidos) { [] }
  let(:logs) { [] }
  let!(:pergunta) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: 'quero agendar')
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(true) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return('OggS-bytes') # rubocop:disable RSpec/AnyInstance
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_including('[autonomia][turno]')) { |linha| logs << linha }
  end

  def pedido_de_localizacao
    Autonomia::Agents::Interacao.do_modelo({ 'tipo' => 'localizacao', 'pergunta' => 'Pode me mandar sua localização?' },
                                           enderecos: Set.new, localizacao: true)
  end

  def responde(reply, interacao, cartoes: [])
    resultado = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil },
                                                    interacao: interacao)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      pedidos << kwargs
      answerer = instance_double(Autonomia::Agents::Answerer)
      allow(answerer).to receive(:answer) do
        cartoes.each { |cartao| kwargs[:delivery].marcar_cartao(cartao) }
        resultado
      end
      answerer
    end
  end

  def perform(reply_to = pergunta)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: reply_to.id).perform
  end

  def enviadas
    conversation.messages.outgoing.order(:id).to_a
  end

  def audio
    enviadas.find { |mensagem| mensagem.content_attributes['autonomia_voice'] }
  end

  def interacoes
    enviadas.select { |mensagem| mensagem.content_attributes.key?('autonomia_interacao_token') }
  end

  def tipos
    enviadas.map do |mensagem|
      next 'audio' if mensagem.content_attributes['autonomia_voice']

      mensagem.content_attributes.dig('rich_message', 'type')
    end
  end

  # Os jobs da âncora enfileirados até agora rodam uma vez, como o Sidekiq faria (o reagendado fica na fila).
  def rodar_jobs
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |item| item[:job] == Autonomia::Agents::Operate::EnviarCartoesJob }
    ActiveJob::Base.queue_adapter.enqueued_jobs.delete_if { |item| jobs.include?(item) }
    jobs.each { |item| Autonomia::Agents::Operate::EnviarCartoesJob.perform_now(*ActiveJob::Arguments.deserialize(item[:args])) }
  end

  # O canal confirma o envio de tudo que o robô postou (o `source_id` da Meta).
  def canal_confirma
    enviadas.each { |mensagem| mensagem.update_column(:source_id, "wamid.#{mensagem.id}") if mensagem.source_id.blank? } # rubocop:disable Rails/SkipsModelValidations
  end

  def ate_o_fim
    3.times do
      canal_confirma
      rodar_jobs
    end
  end

  it 'opções: só o áudio sai no turno; a interação espera o áudio sair e então sai com o rich_message certo' do
    responde('Temos vaga amanhã.', opcoes)
    resultado = perform

    expect(enviadas.size).to eq(1)
    expect(resultado.message).to eq(audio)
    rodar_jobs
    expect(enviadas.size).to eq(1) # o áudio ainda não saiu para o canal: nada

    ate_o_fim
    expect(tipos).to eq(%w[audio options])
    interacao = interacoes.sole
    expect(interacao).to have_attributes(content: 'Qual período?', sender: agent_bot)
    expect(interacao.content_attributes).to include('rich_message' => hash_including('type' => 'options', 'header' => 'Agendamento'),
                                                    'autonomia_agent_id' => agent.id, 'autonomia_reply_to_message_id' => pergunta.id)
    expect(Autonomia::Agents::Interacao.oferta_do_agente?(interacao, agent: agent)).to be(true)
  end

  it 'pedido de localização: a marca vai na mensagem da interação, e a localização que volta é reconhecida' do
    responde('Vou ver a unidade mais perto.', pedido_de_localizacao)
    perform
    ate_o_fim

    pedido = interacoes.sole
    expect(pedido.content_attributes).to include('autonomia_pedido_localizacao' => true)
    expect(pedido.content_attributes.dig('rich_message', 'type')).to eq('location_request')

    local = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil,
                             content_attributes: { 'shared_location' => { 'latitude' => -23.5505, 'longitude' => -46.6333 } })
    responde('Certo.', nil)
    perform(local)
    expect(pedidos.last[:contexto_do_turno].to_s).to include('"localizacao_recebida"')
  end

  it 'interação e cartão: áudio, interação, mapa, cada um esperando o anterior sair' do
    responde('Temos vaga amanhã.', opcoes, cartoes: [mapa])
    perform
    canal_confirma
    rodar_jobs
    expect(tipos).to eq(%w[audio options]) # o mapa espera a interação sair

    ate_o_fim
    expect(tipos).to eq(%w[audio options location])
  end

  it 'o áudio falhou: nem a interação nem o cartão, com registro (só ids)' do
    responde('Temos vaga amanhã.', opcoes, cartoes: [mapa])
    perform
    audio.update!(status: :failed)
    rodar_jobs

    expect(tipos).to eq(%w[audio])
    expect(logs.join).to include('interacao_nao_enviada', "msg=#{audio.id}", 'motivo=anterior_falhou')
    expect(logs.join).to include('cartao_nao_enviado', 'motivo=anterior_falhou')
    expect(logs.join).not_to include('Qual período')
  end

  it 'uma pessoa da equipe respondeu entre o áudio e a interação: nada sai, com registro' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    pessoa = create(:user, account: account, role: :agent)
    create(:inbox_member, user: pessoa, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Sigo eu.', sender: pessoa)
    ate_o_fim

    expect(interacoes).to be_empty
    expect(logs.join).to include('interacao_nao_enviada', 'motivo=pessoa_respondeu')
  end

  it 'a Fase 2 desligada entre o áudio e a interação: nada sai, motivo=desligado' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    canal_confirma
    allow(Autonomia::Agents::Fase2).to receive(:ligada?).and_return(false)
    rodar_jobs

    expect(interacoes).to be_empty
    expect(logs.join).to include('interacao_nao_enviada', 'motivo=desligado')
  end

  it 'retry do turno de voz, antes e depois da interação sair: um áudio e uma interação' do
    responde('Temos vaga amanhã.', opcoes)
    2.times { perform }
    ate_o_fim
    perform
    ate_o_fim

    expect(tipos).to eq(%w[audio options])
  end

  it 'toque numa opção da interação postada pelo job: o turno seguinte lê opcao_tocada' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    ate_o_fim

    toque = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Tarde',
                             content_attributes: { 'in_reply_to' => interacoes.sole.id,
                                                   'selected_option' => { 'id' => 'tarde', 'title' => 'Tarde' } })
    responde('Certo.', nil)
    perform(toque)
    expect(pedidos.last[:contexto_do_turno].to_s).to include('{"opcao_tocada":{"id":"tarde","titulo":"Tarde"}}')
  end

  it 'síntese que falha: cai no texto, com a interação na própria mensagem, sem nada pendente' do
    allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return(nil) # rubocop:disable RSpec/AnyInstance
    responde('Temos vaga amanhã.', opcoes)
    perform

    expect(enviadas.sole.content).to eq("Temos vaga amanhã.\n\nQual período?")
    expect(enviadas.sole.content_attributes).not_to have_key('autonomia_interacao_depois')
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |item| item[:job] }).not_to include(Autonomia::Agents::Operate::EnviarCartoesJob)
  end

  it 'os argumentos do job levam só o id do áudio' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |item| item[:job] == Autonomia::Agents::Operate::EnviarCartoesJob }
    expect(job[:args]).to eq([audio.id])
  end
end
