require 'rails_helper'

# #1479 F3: o mapa e o cartão de contato que as ferramentas marcaram no turno ficam gravados na mensagem âncora do turno
# (`autonomia_cartoes`): o texto no clássico, o áudio na voz, o último pedaço na entrega em pedaços (que nos argumentos
# do job leva só as referências e resolve o cartão pela página ao postar). Eles saem DEPOIS, pelo `EnviarCartoesJob`,
# quando a âncora já saiu para o canal. O retry do turno usa os cartões gravados na âncora, nunca os do novo run, e nunca
# repete um cartão. Turno sem texto, cadeia que parou antes do último pedaço: o cartão é descartado com registro.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato') } }
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
  let(:linhas) { [] }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  # Os cartões como as ferramentas os marcam: do dado da página.
  let(:mapa) do
    local = Autonomia::Agents::Tools::Native::CartaoDaPagina.locais(pagina.reload).sole
    Autonomia::Agents::Tools::Native::CartaoDaPagina.cartao('location', local['id'], local['rich_message'])
  end
  let(:cartao_de_contato) do
    Autonomia::Agents::Tools::Native::CartaoDaPagina.cartao('contact', 'pagina',
                                                            Autonomia::Agents::Tools::Native::CartaoDaPagina.contato(pagina.reload))
  end
  let(:opcoes) do
    Autonomia::Agents::Interacao.do_modelo(
      { 'tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?',
        'opcoes' => [{ 'id' => 'manha', 'titulo' => 'Manhã' }, { 'id' => 'tarde', 'titulo' => 'Tarde' }] }, enderecos: Set.new
    )
  end
  let!(:pergunta) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: 'onde fica?')
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  # O modelo chama as ferramentas durante a resposta: aqui, os cartões são marcados no contexto do turno que o Responder
  # passou ao Answerer, como a ferramenta faria.
  def responde(reply, cartoes, interacao: nil)
    resultado = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil },
                                                    interacao: interacao)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      answerer = instance_double(Autonomia::Agents::Answerer)
      allow(answerer).to receive(:answer) do
        cartoes.each { |cartao| kwargs[:delivery].marcar_cartao(cartao) }
        resultado
      end
      answerer
    end
  end

  def perform
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: pergunta.id).perform
  end

  def enviadas
    conversation.messages.outgoing.order(:id).to_a
  end

  def cartoes_enviados
    enviadas.select { |mensagem| mensagem.content_attributes.key?('autonomia_cartao_token') }
  end

  def tipos
    enviadas.map do |mensagem|
      mensagem.content_attributes.key?('autonomia_cartao_token') ? mensagem.content_attributes.dig('rich_message', 'type') : 'texto'
    end
  end

  def jobs_dos_cartoes
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |item| item[:job] == Autonomia::Agents::Operate::EnviarCartoesJob }
  end

  # O canal confirma o envio do que o robô postou (o `source_id` da Meta) e os jobs dos cartões rodam, como o Sidekiq
  # faria, rodada a rodada (o 2º cartão espera o 1º sair).
  def rodar_cartoes
    3.times do
      enviadas.each { |mensagem| mensagem.update_column(:source_id, "wamid.#{mensagem.id}") if mensagem.source_id.blank? } # rubocop:disable Rails/SkipsModelValidations
      jobs = jobs_dos_cartoes
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete_if { |item| jobs.include?(item) }
      jobs.each { |item| Autonomia::Agents::Operate::EnviarCartoesJob.perform_now(*ActiveJob::Arguments.deserialize(item[:args])) }
    end
  end

  def gravados(mensagem)
    Array(mensagem.reload.content_attributes['autonomia_cartoes'])
  end

  def limpar_redis
    Redis::Alfred.scan_each(match: 'crm:booking_v2:geocodificar:*') { |chave| Redis::Alfred.delete(chave) }
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_including('cartao_descartado')) { |linha| linhas << linha }
  end

  after { limpar_redis }

  describe 'entrega clássica' do
    it 'o texto leva os cartões; nada sai junto, e o job da âncora é enfileirado' do
      responde('Fica no Centro.', [mapa])
      perform

      texto = enviadas.sole
      expect(gravados(texto)).to eq([mapa.merge('token' => "mensagem:#{pergunta.id}:cartao:location:#{mapa['chave']}")])
      expect(jobs_dos_cartoes.map { |item| item[:args] }).to eq([[texto.id]])
    end

    it 'o texto, depois o mapa: conteúdo vazio e o rich_message do cartão' do
      responde('Fica no Centro.', [mapa])
      perform
      rodar_cartoes

      expect(enviadas.map(&:content)).to eq(['Fica no Centro.', ''])
      expect(enviadas.last.content_attributes['rich_message']).to eq(mapa['rich_message'])
      expect(enviadas.last.content_attributes['autonomia_agent_id']).to eq(agent.id)
      expect(enviadas.last.content_attributes).not_to have_key('autonomia_reply_to_message_id')
      expect(enviadas.last.sender).to eq(agent_bot)
    end

    it 'dois cartões, depois do texto, na ordem em que foram marcados' do
      responde('Aqui estão.', [mapa, cartao_de_contato])
      perform
      rodar_cartoes
      expect(tipos).to eq(%w[texto location contact])
    end

    it 'perform repetido (retry): um texto e um cartão' do
      responde('Fica no Centro.', [mapa])
      2.times { perform }
      rodar_cartoes
      expect(tipos).to eq(%w[texto location])
    end

    it 'o retry com outro cartão marcado: só sai o gravado na âncora' do
      responde('Fica no Centro.', [mapa])
      perform
      responde('Fica no Centro.', [cartao_de_contato])
      perform
      rodar_cartoes
      expect(tipos).to eq(%w[texto location])
    end

    it 'o retry depois do texto sem cartão (o modelo só o marcou na 2ª vez): nada a mais sai, e o descarte fica registrado' do
      responde('Fica no Centro.', [])
      perform
      responde('Fica no Centro.', [mapa])
      perform
      rodar_cartoes
      expect(tipos).to eq(%w[texto])
      expect(linhas.sole).to include("msg=#{pergunta.id}", 'motivo=ja_respondido')
    end

    it 'falha no turno depois do texto postado, antes de enfileirar: o descarte fica registrado' do
      allow(Autonomia::Agents::Operate::EventLogger).to receive(:replied).and_raise(StandardError)
      responde('Fica no Centro.', [mapa])
      perform
      expect(jobs_dos_cartoes).to be_empty
      expect(linhas.sole).to include('motivo=falha')
    end

    it 'o cartão já enviado não faz o retry pular o texto, nem sai de novo' do
      responde('Fica no Centro.', [mapa])
      perform
      rodar_cartoes
      enviadas.first.destroy!
      perform
      rodar_cartoes
      expect(enviadas.map(&:content)).to eq(['', 'Fica no Centro.'])
      expect(cartoes_enviados.size).to eq(1)
    end

    it 'sem cartão marcado: as mesmas mensagens de antes, sem job' do
      responde('Fica no Centro.', [])
      perform
      expect(enviadas.sole.content).to eq('Fica no Centro.')
      expect(enviadas.sole.content_attributes.keys).to contain_exactly('autonomia_agent_id', 'autonomia_reply_to_message_id')
      expect(jobs_dos_cartoes).to be_empty
    end

    it 'turno sem texto: o cartão não sai, e o descarte fica registrado (só ids)' do
      responde('', [mapa])

      expect(perform.status).to eq(:silenced)
      expect(enviadas).to be_empty
      expect(jobs_dos_cartoes).to be_empty
      expect(linhas.sole).to include("conv=#{conversation.id}", "msg=#{pergunta.id}", 'motivo=vazio')
      expect(linhas.sole).not_to include('Rua Direita')
    end

    it 'erro ao enfileirar o job: o texto fica postado e o turno respondido' do
      allow(Autonomia::Agents::Operate::EnviarCartoesJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
      responde('Fica no Centro.', [mapa])
      expect(perform.status).to eq(:replied)
      expect(enviadas.sole.content).to eq('Fica no Centro.')
    end
  end

  describe 'entrega em pedaços' do
    around { |example| with_modified_env(AI_HUMANIZE_DELIVERY: 'true') { example.run } }

    before do
      digitando = instance_double(Autonomia::Agents::Operate::TypingIndicator, on: nil, off: nil)
      allow(Autonomia::Agents::Operate::TypingIndicator).to receive(:new).and_return(digitando)
    end

    def pedacos_agendados
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.reverse.find { |item| item[:job] == Autonomia::Agents::Operate::ChunkedDeliveryJob }
      ActiveJob::Arguments.deserialize(job[:args])[3]
    end

    def entregar(pedacos)
      pedacos.each_index do |indice|
        Autonomia::Agents::Operate::ChunkedDeliveryJob.new.perform(conversation.id, agent_inbox.id, pergunta.id, pedacos, indice, {})
      end
    end

    it 'os cartões vão na marca do último pedaço (sem pedaço próprio) e saem pelo job, depois de todos' do
      responde("Temos duas unidades.\n\nA do Centro abre às 8h.", [mapa], interacao: opcoes)
      perform
      pedacos = pedacos_agendados
      expect(pedacos.last['marca']['autonomia_cartoes']).to eq(
        [{ 'tipo' => 'location', 'chave' => mapa['chave'], 'token' => "mensagem:#{pergunta.id}:cartao:location:#{mapa['chave']}" }]
      )
      expect(pedacos.last).to include('rich_message' => hash_including('type' => 'options'))
      expect(pedacos[0...-1]).to all(satisfy { |pedaco| pedaco['marca'].to_h.exclude?('autonomia_cartoes') })
      expect(jobs_dos_cartoes).to be_empty

      entregar(pedacos)
      expect(jobs_dos_cartoes.map { |item| item[:args] }).to eq([[enviadas.last.id]])
      expect(gravados(enviadas.last).sole).to include('rich_message' => mapa['rich_message'])
      rodar_cartoes
      expect(enviadas.map { |mensagem| mensagem.content_attributes.dig('rich_message', 'type') }.last(2)).to eq(%w[options location])
    end

    it 'o pedaço repetido (retry do job) não duplica o cartão' do
      responde('Fica no Centro.', [mapa])
      perform
      pedacos = pedacos_agendados
      entregar(pedacos)
      entregar(pedacos)
      rodar_cartoes
      expect(cartoes_enviados.size).to eq(1)
    end

    it 'o retry do turno com outro número de pedaços e outro cartão: só o cartão gravado, uma vez' do
      responde('Fica no Centro.', [mapa])
      perform
      entregar(pedacos_agendados)
      responde("Fica no Centro.\n\nPerto do metrô.\n\nAbre às 8h.", [cartao_de_contato])
      perform
      rodar_cartoes
      expect(cartoes_enviados.map { |cartao| cartao.content_attributes.dig('rich_message', 'type') }).to eq(%w[location])
    end

    it 'os argumentos do job de pedaços não levam endereço, coordenada nem telefone' do
      responde('Fica no Centro.', [mapa, cartao_de_contato])
      perform
      argumentos = pedacos_agendados.to_json
      ['Rua Direita', '-23.5489', '-46.6388', '551140000473'].each { |dado| expect(argumentos).not_to include(dado) }
    end

    it 'a página mudou antes do último pedaço: o cartão que não resolve mais fica fora, com registro' do
      responde('Fica no Centro.', [mapa, cartao_de_contato])
      perform
      pagina.update_column(:contact_phone, nil) # rubocop:disable Rails/SkipsModelValidations
      entregar(pedacos_agendados)
      expect(gravados(enviadas.last).map { |cartao| cartao['tipo'] }).to eq(%w[location])
      expect(linhas.sole).to include("conv=#{conversation.id}", 'motivo=pagina_mudou')
      rodar_cartoes
      expect(tipos).to eq(%w[texto location])
    end

    it 'a cadeia parou antes do último pedaço (a pessoa respondeu): o cartão não sai, com registro' do
      responde("Fica no Centro.\n\nPerto do metrô.", [mapa])
      perform
      pedacos = pedacos_agendados
      entregar(pedacos[0...-1])
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Sigo eu.',
                       sender: create(:user, account: account, role: :agent))
      Autonomia::Agents::Operate::ChunkedDeliveryJob.new.perform(conversation.id, agent_inbox.id, pergunta.id, pedacos,
                                                                 pedacos.size - 1, {})

      expect(jobs_dos_cartoes).to be_empty
      expect(linhas.sole).to include('motivo=pessoa_respondeu')
    end

    # O ChunkedDeliveryJob morreu depois de postar o último pedaço e antes de enfileirar os cartões: o retry do mesmo
    # pedaço cai em `ja_postado` e enfileira mesmo assim (o job dos cartões é idempotente).
    it 'o job morreu entre o último pedaço e o enfileirar: o retry enfileira, e o cartão sai uma vez' do
      responde('Fica no Centro.', [mapa])
      perform
      pedacos = pedacos_agendados
      chamadas = 0
      allow(Autonomia::Agents::Operate::CartoesDoTurno).to receive(:enfileirar).and_wrap_original do |original, *args|
        chamadas += 1
        raise 'o worker morreu' if chamadas == 1

        original.call(*args)
      end
      expect { entregar(pedacos) }.to raise_error(RuntimeError)
      expect(jobs_dos_cartoes).to be_empty

      2.times { entregar(pedacos) }
      expect(jobs_dos_cartoes.map { |item| item[:args] }).to eq([[enviadas.sole.id]] * 2)
      rodar_cartoes
      expect(tipos).to eq(%w[texto location])
    end

    it 'sem cartão marcado: os mesmos pedaços de antes' do
      responde('Fica no Centro.', [])
      perform
      expect(pedacos_agendados.size).to eq(1)
      expect(pedacos_agendados.sole).not_to have_key('rich_message')
      expect(pedacos_agendados.sole).not_to have_key('marca')
    end
  end

  # #1479 (LOW a da F3): a guarda "já respondido" só procura a âncora quando o turno pode ter cartão ou interação pendente.
  describe 'a guarda "já respondido" e a busca da âncora' do
    before { allow(Autonomia::Agents::Operate::CartoesDoTurno).to receive(:ancora_do_turno).and_call_original }

    context 'without the cards flag and without voice' do
      let(:account) { conta_da_fase2 }

      it 'o retry não consulta a âncora' do
        responde('Fica no Centro.', [])
        2.times { perform }
        expect(enviadas.size).to eq(1)
        expect(Autonomia::Agents::Operate::CartoesDoTurno).not_to have_received(:ancora_do_turno)
      end
    end

    context 'without the cards flag, with voice on the agent' do
      let(:account) { conta_da_fase2 }
      let(:agent) { criar_principal(account, config: { 'with_knowledge' => false, 'voice_reply' => true }) }

      it 'o retry consulta a âncora (pode haver interação depois do áudio)' do
        responde('Fica no Centro.', [])
        2.times { perform }
        expect(Autonomia::Agents::Operate::CartoesDoTurno).to have_received(:ancora_do_turno).once
      end
    end

    it 'com a flag dos cartões, o retry consulta a âncora' do
      responde('Fica no Centro.', [])
      2.times { perform }
      expect(Autonomia::Agents::Operate::CartoesDoTurno).to have_received(:ancora_do_turno).once
    end
  end

  describe 'resposta em áudio' do
    before do
      allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(true) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return('OggS-bytes') # rubocop:disable RSpec/AnyInstance
    end

    it 'o áudio é a âncora: o job espera o áudio sair' do
      responde('Temos vaga amanhã.', [mapa])
      resultado = perform
      audio = enviadas.sole
      expect(resultado.message).to eq(audio)
      expect(gravados(audio).sole).to include('tipo' => 'location')

      Autonomia::Agents::Operate::EnviarCartoesJob.perform_now(audio.id)
      expect(cartoes_enviados).to be_empty

      rodar_cartoes
      expect(tipos).to eq(%w[texto location])
      expect(enviadas.first.content_attributes['autonomia_voice']).to be(true)
    end

    it 'com a interação, a âncora continua o áudio: áudio, interação, depois o cartão' do
      responde('Temos vaga amanhã.', [mapa], interacao: opcoes)
      perform
      expect(enviadas.size).to eq(1)
      expect(gravados(enviadas.first)).not_to be_empty
      rodar_cartoes
      expect(gravados(enviadas.second)).to be_empty
      expect(enviadas.size).to eq(3)
      expect(enviadas.second.content_attributes['rich_message']).to include('type' => 'options')
      expect(enviadas.last.content_attributes['rich_message']).to eq(mapa['rich_message'])
    end

    it 'perform repetido: um áudio e um cartão' do
      responde('Temos vaga amanhã.', [mapa])
      2.times { perform }
      rodar_cartoes
      expect(enviadas.size).to eq(2)
      expect(cartoes_enviados.size).to eq(1)
    end
  end
end
