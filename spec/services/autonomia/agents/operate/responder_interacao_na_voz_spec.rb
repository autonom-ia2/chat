require 'rails_helper'

# #1479: na resposta em voz, a interação (opções, link, pedido de localização) sai DEPOIS do áudio. O áudio vai com
# anexo e o `SendReplyJob` dele espera 2 s; a interação postada logo depois saía antes. Agora ela fica gravada no áudio
# (a âncora) e sai pelo `EnviarInteracaoJob`, quando o áudio saiu para o canal, antes dos cartões. Áudio que falhou: a
# pergunta sai degradada. Pessoa da equipe que respondeu, cliente que escreveu de novo ou Fase 2 desligada: nada sai,
# com registro. O retry do turno nunca duplica a interação.
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
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |item| jobs_da_ancora.include?(item[:job]) }
    ActiveJob::Base.queue_adapter.enqueued_jobs.delete_if { |item| jobs.include?(item) }
    jobs.each { |item| item[:job].perform_now(*ActiveJob::Arguments.deserialize(item[:args])) }
  end

  def jobs_da_ancora
    [Autonomia::Agents::Operate::EnviarCartoesJob, Autonomia::Agents::Operate::EnviarInteracaoJob]
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

  # O cliente manda a localização sem citar (WAHA e Híbrido, pelo clipe): vale quando a última fala do agente é o pedido.
  # O mapa do mesmo turno sai depois do pedido e não é fala: não tira o pedido do lugar (`LocalizacaoRecebida#pedida?`).
  describe 'pedido de localização seguido do mapa do mesmo turno' do
    def localizacao_sem_citar
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil,
                       content_attributes: { 'shared_location' => { 'latitude' => -23.5505, 'longitude' => -46.6333 } })
    end

    def turno_seguinte_le_a_localizacao
      local = localizacao_sem_citar
      responde('Certo.', nil)
      perform(local)
      pedidos.last[:contexto_do_turno].to_s
    end

    it 'voz: áudio, pedido, mapa; a localização sem citar vai ao turno' do
      responde('Vou ver a unidade mais perto.', pedido_de_localizacao, cartoes: [mapa])
      perform
      ate_o_fim
      expect(tipos).to eq(%w[audio location_request location])
      expect(turno_seguinte_le_a_localizacao).to include('"localizacao_recebida"')
    end

    it 'clássico: o texto com o pedido, depois o mapa; a localização sem citar vai ao turno' do
      allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(false) # rubocop:disable RSpec/AnyInstance
      responde('Vou ver a unidade mais perto.', pedido_de_localizacao, cartoes: [mapa])
      perform
      ate_o_fim
      expect(enviadas.map { |mensagem| mensagem.content_attributes.dig('rich_message', 'type') }).to eq(%w[location_request location])
      expect(turno_seguinte_le_a_localizacao).to include('"localizacao_recebida"')
    end
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

  it 'o áudio falhou: a pergunta sai assim mesmo (interacao_degradada), o cartão não, com registro (só ids)' do
    responde('Temos vaga amanhã.', opcoes, cartoes: [mapa])
    perform
    audio.update!(status: :failed)
    rodar_jobs

    expect(tipos).to eq(%w[audio options])
    expect(logs.join).to include('interacao_degradada', "msg=#{audio.id}", 'motivo=anterior_falhou')
    expect(logs.join).to include('cartao_nao_enviado', 'motivo=anterior_falhou')
    expect(logs.join).not_to include('interacao_nao_enviada', 'Qual período')
    expect(audio.reload.content_attributes['autonomia_cartoes_encerrados']).to eq('anterior_falhou')
    ate_o_fim
    expect(tipos).to eq(%w[audio options])
  end

  describe 'erro ao postar a interação' do
    def falha_ao_postar
      allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::Deadlocked)
    end

    it 'antes do teto: reagenda sem desistir, e na próxima vez a pergunta sai' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      canal_confirma
      falha_ao_postar
      rodar_jobs

      expect(interacoes).to be_empty
      expect(logs.join).not_to include('interacao_nao_enviada')
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |item| item[:job] }).to include(Autonomia::Agents::Operate::EnviarInteracaoJob)
      allow(Messages::MessageBuilder).to receive(:new).and_call_original
      rodar_jobs
      expect(tipos).to eq(%w[audio options])
    end

    it 'áudio que falhou e erro ao postar: reagenda sem registrar degradada; ela só aparece uma vez, quando a pergunta sai' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      audio.update!(status: :failed)
      falha_ao_postar
      2.times { rodar_jobs }
      expect(logs.join).not_to include('interacao_degradada')

      allow(Messages::MessageBuilder).to receive(:new).and_call_original
      rodar_jobs
      expect(tipos).to eq(%w[audio options])
      expect(logs.join.scan('interacao_degradada').size).to eq(1)
    end

    it 'depois do teto: desiste com interacao_nao_enviada motivo=erro_ao_postar' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      canal_confirma
      falha_ao_postar
      travel(Autonomia::Agents::Operate::EnviarCartoesJob::TETO + 1.second) { rodar_jobs }

      expect(interacoes).to be_empty
      expect(logs.join).to include('interacao_nao_enviada', 'motivo=erro_ao_postar')
    end
  end

  it 'o cliente escreveu de novo depois do áudio, antes da pergunta sair: nada sai, motivo=turno_superado' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'de manhã')
    ate_o_fim

    expect(interacoes).to be_empty
    expect(logs.join).to include('interacao_nao_enviada', 'motivo=turno_superado')
  end

  it 'job repetido depois da pergunta sair, com o cliente já tendo respondido: nenhuma desistência falsa' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    ate_o_fim
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Tarde')
    Autonomia::Agents::Operate::EnviarInteracaoJob.perform_now(audio.id)

    expect(tipos).to eq(%w[audio options])
    expect(logs.join).not_to include('interacao_nao_enviada')
    expect(audio.reload.content_attributes).not_to have_key('autonomia_cartoes_encerrados')
  end

  it 'a voz desligada entre o áudio e o retry do turno: o retry ainda enfileira a pergunta gravada' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Autonomia::Agents::Config).to receive(:voice_reply_enabled?).and_return(false)
    allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(false) # rubocop:disable RSpec/AnyInstance
    perform
    ate_o_fim

    expect(tipos).to eq(%w[audio options])
  end

  it 'erro ao enfileirar o job do áudio: registra interacao_nao_enviada motivo=erro_ao_enfileirar' do
    responde('Temos vaga amanhã.', opcoes)
    allow(Autonomia::Agents::Operate::EnviarInteracaoJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
    perform

    expect(logs.join).to include('interacao_nao_enviada', 'motivo=erro_ao_enfileirar')
    expect(logs.join).not_to include('cartao_nao_enviado')
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
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |item| item[:job] }).not_to include(*jobs_da_ancora)
  end

  it 'a EnviarInteracaoJob leva 6 tentativas no próprio job (cobre a sobreposição do deploy, além do max_retries: 3)' do
    expect(Autonomia::Agents::Operate::EnviarInteracaoJob.get_sidekiq_options['retry']).to eq(6)
  end

  it 'o áudio vai pela EnviarInteracaoJob (o worker antigo não a conhece), com só o id do áudio nos argumentos' do
    responde('Temos vaga amanhã.', opcoes, cartoes: [mapa])
    perform
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |item| jobs_da_ancora.include?(item[:job]) }
    expect(jobs.map { |item| item[:job] }).to eq([Autonomia::Agents::Operate::EnviarInteracaoJob])
    expect(jobs.sole[:args]).to eq([audio.id])
  end

  # r2 da revisão: o teto, as guardas de turno e de dono, o formato reconferido e os destinatários do e-mail na hora.
  describe 'o áudio passou do teto ainda pendente' do
    def teto = Autonomia::Agents::Operate::EnviarCartoesJob::TETO + 1.second

    it 'a interação sai assim mesmo (a pergunta nunca se perde), com interacao_degradada; o mapa desiste e a âncora encerra' do
      responde('Temos vaga amanhã.', opcoes, cartoes: [mapa])
      perform
      travel(teto) { rodar_jobs }

      expect(tipos).to eq(%w[audio options])
      expect(logs.join).to include('interacao_degradada', "msg=#{audio.id}", 'motivo=anterior_pendente')
      expect(logs.join).to include('cartao_nao_enviado', 'motivo=anterior_pendente')
      expect(audio.reload.content_attributes['autonomia_cartoes_encerrados']).to eq('anterior_pendente')
      travel(teto) { ate_o_fim }
      expect(tipos).to eq(%w[audio options])
    end

    it 'o áudio que falhou depois do teto: a pergunta sai uma vez, motivo=anterior_falhou' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      audio.update!(status: :failed)
      travel(teto) { rodar_jobs }

      expect(tipos).to eq(%w[audio options])
      expect(logs.join).to include('interacao_degradada', 'motivo=anterior_falhou')
    end
  end

  it 'turno superado: o robô já respondeu outra mensagem do cliente depois do áudio; nada sai, motivo=turno_superado' do
    responde('Temos vaga amanhã.', opcoes, cartoes: [mapa])
    perform
    outra = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'e sábado?')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Sábado não.',
                     sender: agent_bot, content_attributes: { 'autonomia_agent_id' => agent.id, 'autonomia_reply_to_message_id' => outra.id })
    ate_o_fim

    expect(interacoes).to be_empty
    expect(tipos.count('location')).to eq(0)
    expect(logs.join).to include('interacao_nao_enviada', 'motivo=turno_superado')
    expect(audio.reload.content_attributes['autonomia_cartoes_encerrados']).to eq('turno_superado')
  end

  it 'a conversa passou a uma pessoa (o robô não está mais no comando): nada sai, motivo=dono_mudou' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    conversation.update!(assignee: create(:user, account: account, role: :agent))
    ate_o_fim

    expect(interacoes).to be_empty
    expect(logs.join).to include('interacao_nao_enviada', 'motivo=dono_mudou')
  end

  it 'o formato que a caixa recusa agora: sai a versão em texto, sem rich_message' do
    responde('Temos vaga amanhã.', opcoes)
    perform
    allow(Autonomia::Agents::Interacao).to receive(:sai_o_formato?).and_return(false)
    ate_o_fim

    expect(interacoes.sole.content).to eq("Qual período?\n\n1. Manhã\n2. Tarde")
    expect(interacoes.sole.content_attributes).not_to have_key('rich_message')
  end

  context 'when the inbox is e-mail' do
    let(:inbox) { create(:channel_email, account: account).inbox }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

    before do
      account.enable_features!(Crm::Email::Autoria::FLAG)
      conversation.contact.update!(email: 'joao@empresa.com.br')
      email = { 'from' => ['joao@empresa.com.br'], 'cc' => ['ana@familia.com.br', 'rh@empresa.com.br'] }
      pergunta.update!(content_attributes: pergunta.content_attributes.merge('email' => email))
    end

    it 'a cópia é a da mensagem do cliente (calculada com o áudio), não a do áudio, que não tem Cc' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      ate_o_fim

      expect(interacoes.sole.content_attributes['cc_emails']).to contain_exactly('ana@familia.com.br', 'rh@empresa.com.br')
      expect(interacoes.sole.content_attributes['to_emails']).to eq(['joao@empresa.com.br'])
    end

    it 'quem pediu para sair da cópia depois do áudio sai da pergunta' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      Crm::Email::Destinatarios.registrar_saida!(conversation, 'ana@familia.com.br')
      ate_o_fim

      expect(interacoes.sole.content_attributes['cc_emails']).to eq(['rh@empresa.com.br'])
    end
  end
end
