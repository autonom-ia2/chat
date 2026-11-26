require 'rails_helper'

# #3223: o comparativo em PDF do Seguro Viagem é um cartão do turno. `cotar_seguro_viagem` só o marca; ele sai DEPOIS da
# resposta, pelo `EnviarCartoesJob`, e só quando ela saiu. O turno superado (o cliente escreveu durante a IA) não posta a
# resposta nem o PDF, e o descarte fica registrado. Não depende da flag do mapa e do contato.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2.tap { |conta| conta.disable_features!('agentes_enviar_local_e_contato') } }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:entrega) { Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo }
  let(:linhas) { [] }
  let(:nao_enviados) { [] }
  let!(:pergunta) { mensagem_do_cliente('França, 15 a 20/01, 40, 38 e 10 anos') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_including('cartao_descartado')) { |linha| linhas << linha }
    allow(Rails.logger).to receive(:info).with(a_string_including('cartao_nao_enviado')) { |linha| nao_enviados << linha }
  end

  it 'a conta destes exemplos está sem o envio do mapa e do contato' do
    expect(account.feature_enabled?('agentes_enviar_local_e_contato')).to be(false)
  end

  def mensagem_do_cliente(texto)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: texto)
  end

  def cotacao
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversation, agent: agent, id_cotacao: '0',
      pedido: { 'destinos' => ['FR'], 'destinos_nomes' => ['França'], 'data_saida' => '2027-01-15',
                'data_retorno' => '2027-01-20', 'idades' => [40], 'motivo' => nil, 'universal' => {} },
      planos: [{ 'codigo' => 'P1', 'nome' => 'Exemplo UA 80', 'preco_total' => '96.0', 'max_parcelas' => 12,
                 'idade_minima' => 0, 'idade_maxima' => 85, 'faixas' => [{ 'de' => 0, 'ate' => 85, 'valor' => '96.0' }],
                 'coberturas' => [{ 'id_beneficio' => 2899, 'nome' => 'Despesas Médicas', 'valor' => '$80.000', 'moeda' => 'USD' }] }]
    )
  end

  # O modelo chama `cotar_seguro_viagem` durante a resposta: o cartão é marcado no contexto do turno. `superada_por`: o
  # cliente escreve de novo durante a IA (a marca do debounce passa a apontar para a mensagem nova).
  def responde(reply, cartoes, superada_por: nil)
    resultado = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil })
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      answerer = instance_double(Autonomia::Agents::Answerer)
      allow(answerer).to receive(:answer) do
        cartoes.each { |cartao| kwargs[:delivery].marcar_cartao(cartao) }
        superar(superada_por) if superada_por
        resultado
      end
      answerer
    end
  end

  def superar(mensagem)
    conversation.update!(additional_attributes: conversation.additional_attributes.to_h.merge(
      Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => { 'pending_message_id' => mensagem.id }
    ))
  end

  def perform(mensagem = pergunta)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: mensagem.id).perform
  end

  def enviadas
    conversation.messages.outgoing.order(:id).to_a
  end

  def pdfs
    enviadas.select { |mensagem| mensagem.content_attributes.key?(entrega::CHAVE) }
  end

  def jobs_dos_cartoes
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |item| item[:job] == Autonomia::Agents::Operate::EnviarCartoesJob }
  end

  # O canal confirma o envio do que o robô postou e os jobs dos cartões rodam, como o Sidekiq faria.
  def rodar_cartoes
    2.times do
      enviadas.each { |mensagem| mensagem.update_column(:source_id, "wamid.#{mensagem.id}") if mensagem.source_id.blank? } # rubocop:disable Rails/SkipsModelValidations
      jobs = jobs_dos_cartoes
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete_if { |item| jobs.include?(item) }
      jobs.each { |item| item[:job].perform_now(*ActiveJob::Arguments.deserialize(item[:args])) }
    end
  end

  it 'o PDF sai depois da resposta, como anexo sem texto, sem a flag do mapa e do contato' do
    cotada = cotacao
    responde('França, de 15/01 a 20/01: 1. Exemplo UA 80...', [entrega.cartao(cotada)])
    perform
    expect(enviadas.map(&:content)).to eq(['França, de 15/01 a 20/01: 1. Exemplo UA 80...'])

    rodar_cartoes
    pdf = pdfs.sole
    expect(enviadas.last).to eq(pdf)
    expect(pdf.content).to be_blank
    expect(pdf.attachments.sole.file.content_type).to eq('application/pdf')
    expect(pdf.content_attributes).to include(entrega::CHAVE => cotada.id, 'autonomia_agent_id' => agent.id,
                                              'autonomia_cartao_token' => "mensagem:#{pergunta.id}:cartao:comparativo_viagem:#{cotada.id}")
    expect(pdf.private).to be(false)
  end

  it 'turno superado durante a IA: nem a resposta nem o PDF saem, e o descarte fica registrado' do
    responde('Segue a cotação.', [entrega.cartao(cotacao)], superada_por: mensagem_do_cliente('e o meu filho?'))

    expect(perform.status).to eq(:silenced)
    expect(enviadas).to be_empty
    expect(jobs_dos_cartoes).to be_empty
    expect(linhas.sole).to include("conv=#{conversation.id}", "msg=#{pergunta.id}", 'motivo=turno_superado')
  end

  it 'dois turnos, o 1º superado: um PDF só, o da cotação do turno que respondeu' do
    segunda_pergunta = mensagem_do_cliente('e o meu filho?')
    responde('Segue a cotação.', [entrega.cartao(cotacao)], superada_por: segunda_pergunta)
    perform

    segunda = cotacao
    responde('Com o seu filho, fica assim: ...', [entrega.cartao(segunda)])
    perform(segunda_pergunta)
    rodar_cartoes

    expect(pdfs.sole.content_attributes[entrega::CHAVE]).to eq(segunda.id)
    expect(enviadas.map(&:content).first).to eq('Com o seu filho, fica assim: ...')
  end

  it 'perform repetido (retry): o PDF sai uma vez' do
    responde('Segue a cotação.', [entrega.cartao(cotacao)])
    2.times { perform }
    rodar_cartoes
    expect(pdfs.size).to eq(1)
  end

  it 'retry: a 1ª rodada postou a resposta e morreu antes de enfileirar; a 2ª não cota e o PDF sai assim mesmo' do
    chamadas = 0
    allow(Autonomia::Agents::Operate::EnviarCartoesJob).to receive(:perform_later).and_wrap_original do |original, *args|
      chamadas += 1
      raise Redis::CannotConnectError if chamadas == 1

      original.call(*args)
    end
    responde('Segue a cotação.', [entrega.cartao(cotacao)])
    perform
    responde('Segue a cotação.', [])
    perform
    rodar_cartoes

    expect(pdfs.size).to eq(1)
    expect(enviadas.size).to eq(2)
  end

  it 'agentes desligados na conta antes de o PDF sair: ele não sai, e fica registrado' do
    responde('Segue a cotação.', [entrega.cartao(cotacao)])
    perform
    account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_enabled' => false))
    rodar_cartoes

    expect(pdfs).to be_empty
    expect(nao_enviados.sole).to include("conv=#{conversation.id}", 'motivo=desligado')
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

    it 'o último pedaço sai, depois o PDF' do
      responde("Segue a cotação.\n\nNo PDF estão todas as coberturas.", [entrega.cartao(cotacao)])
      perform
      pedacos = pedacos_agendados
      expect(pedacos.size).to be > 1

      entregar(pedacos)
      rodar_cartoes
      expect(enviadas.last).to eq(pdfs.sole)
      expect(enviadas.size).to eq(pedacos.size + 1)
    end

    it 'o turno mudou antes do último pedaço: o PDF não sai, e o descarte fica registrado' do
      responde("Segue a cotação.\n\nNo PDF estão todas as coberturas.", [entrega.cartao(cotacao)])
      perform
      pedacos = pedacos_agendados
      superar(mensagem_do_cliente('e o meu filho?'))
      # A cadeia para no 1º pedaço e não agenda os outros: o que leva o cartão (o último) nunca sai.
      Autonomia::Agents::Operate::ChunkedDeliveryJob.new.perform(conversation.id, agent_inbox.id, pergunta.id, pedacos, 0, {})
      rodar_cartoes

      expect(pdfs).to be_empty
      expect(jobs_dos_cartoes).to be_empty
      expect(linhas.sole).to include("conv=#{conversation.id}", "msg=#{pergunta.id}", 'motivo=turno_mudou')
    end
  end

  it 'nos pedaços, o comparativo resolve pela cotação, não pela página' do
    referencia = { 'tipo' => 'comparativo_viagem', 'chave' => '42', 'token' => 'mensagem:1:cartao:comparativo_viagem:42' }
    expect(Autonomia::Agents::Operate::CartoesDoTurno.resolver([referencia], agent)).to eq([[referencia.merge('rich_message' => nil)], 0])
  end
end
