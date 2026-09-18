require 'rails_helper'

# OS ANEXOS DO TURNO NO RESPONDER (fatia 2 do #420, desenho da rodada 8).
#
# Uma ferramenta SÍNCRONA escreve um texto pelo código e o anexa ao `Tools::Delivery`; o Responder o entrega logo
# depois da resposta do modelo, na mesma entrega, nos três caminhos (clássico, humanizado e voz). No turno mudo o
# anexo sai sozinho. O retry do `ReplyJob` não duplica nada.
#
# O Answerer e o executor de ferramentas NÃO são dublados: dublados são a credencial, o cliente de IA e o catálogo
# (uma ferramenta síncrona de teste que anexa a lista). O dublê do modelo devolve a chamada de função e a fala.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:lista) { "• *Porto Seguro*: R$ 2.119,18 no total\n\n• *Allianz*: R$ 2.402,55 no total" }
  let(:fala) do
    "Perfeito! Separei aqui o resultado da sua cotação com as seguradoras que responderam até agora.\n\n" \
      'A lista chega logo abaixo, com os valores de cada uma. Qualquer dúvida sobre as coberturas, é só me chamar.'
  end
  # A ferramenta síncrona de teste: anexa a lista ao turno e devolve ao modelo só o estado.
  let(:anexadora) do
    texto = lista
    Class.new(Autonomia::Agents::Tools::Native::Base) do
      define_singleton_method(:slug) { 'mostrar_lista' }
      define_singleton_method(:description) { 'Anexa a lista de teste ao turno.' }
      define_method(:call) do
        delivery.anexar('lista', texto)
        'A lista vai anexada depois da sua mensagem.'
      end
    end
  end
  let(:catalogo) { [anexadora] }
  let(:chamada) { { 'name' => 'mostrar_lista', 'call_id' => 'c1', 'arguments' => '{}' } }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    allow(Autonomia::Agents::Tools::Registry).to receive(:find) { |slug| catalogo.find { |tool| tool.slug == slug.to_s } }
    allow(Autonomia::Agents::Tools::Registry).to receive(:for_agent) { catalogo }
    conversation.update!(assignee_agent_bot_id: agent_bot.id)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'me manda os preços')
  end

  def model_reply(text)
    { reply: text, confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # O modelo dublado: chama as funções da rodada e devolve `texto` como resposta (ou `bruto`, a saída crua que não
  # segue o formato). `antes_da_fala` roda depois das ferramentas, no meio do turno.
  def stub_ai_turn(texto, chamadas: [chamada], antes_da_fala: nil, bruto: nil)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      executor&.call(chamadas) if chamadas.any?
      antes_da_fala&.call
      { text: bruto || model_reply(texto) }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def responder
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: conversation.messages.incoming.last.id)
  end

  def mensagens_do_bot
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
  end

  def cadeias
    enqueued_jobs.select { |item| item[:job] == Autonomia::Agents::Operate::ChunkedDeliveryJob }
  end

  # Roda a cadeia humanizada enfileirada pela `vez`-ésima entrega, pedaço a pedaço, como o job faria.
  def rodar_cadeia(vez = 0)
    args = ActiveJob::Arguments.deserialize(cadeias[vez][:args])
    args[3].each_index { |indice| Autonomia::Agents::Operate::ChunkedDeliveryJob.new.perform(*args.first(4), indice, args[5]) }
  end

  describe 'entrega clássica' do
    around do |example|
      with_modified_env(AI_HUMANIZE_DELIVERY: 'false') { example.run }
    end

    it 'a fala sai primeiro e a lista depois, cada uma uma mensagem da resposta do turno' do
      stub_ai_turn(fala)

      resultado = responder.perform

      expect(resultado.status).to eq(:replied)
      expect(mensagens_do_bot.map(&:content)).to eq([fala, lista])
      expect(mensagens_do_bot.map { |m| m.content_attributes.to_h['autonomia_reply_to_message_id'] }.uniq)
        .to eq([conversation.messages.incoming.last.id])
      expect(agent.events.replied.pluck(:message_id)).to eq([resultado.message.id])
    end

    it 'sem anexo, a entrega é a de sempre' do
      stub_ai_turn(fala, chamadas: [])

      responder.perform

      expect(mensagens_do_bot.map(&:content)).to eq([fala])
    end

    it 'o retry do ReplyJob não repete a fala nem a lista' do
      stub_ai_turn(fala)

      2.times { responder.perform }

      expect(mensagens_do_bot.map(&:content)).to eq([fala, lista])
    end

    # A MESMA TRANSAÇÃO: a lista que não entra desfaz a fala, e o retry não encontra meia entrega.
    it 'a lista que não entra desfaz a fala: saem as duas ou nenhuma' do
      stub_ai_turn(fala)
      criadas = 0
      allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, *args|
        raise ActiveRecord::StatementInvalid, 'banco fora' if (criadas += 1) == 2

        original.call(*args)
      end

      resultado = responder.perform

      expect(resultado.status).to eq(:silenced)
      expect(mensagens_do_bot).to be_empty
    end

    it 'o humano que assume durante a chamada ao modelo não recebe fala nem lista' do
      stub_ai_turn(fala, antes_da_fala: -> { conversation.update!(assignee: create(:user, account: account)) })

      resultado = responder.perform

      expect(resultado.status).to eq(:silenced)
      expect(mensagens_do_bot).to be_empty
    end
  end

  # TURNO MUDO (decisão 19 da fatia 2): a lista sai sozinha, pelo caminho clássico, sem evento `replied`.
  describe 'turno mudo' do
    [['a entrega clássica', 'false'], ['a entrega humanizada ligada', 'true']].each do |nome, humanizada|
      it "com #{nome}, a lista sai sozinha, uma vez, e o turno continua mudo" do
        with_modified_env(AI_HUMANIZE_DELIVERY: humanizada) do
          stub_ai_turn(described_class::SILENCE_TOKEN)

          resultados = Array.new(2) { responder.perform }

          expect(resultados.map(&:status)).to eq(%i[silenced silenced])
          expect(mensagens_do_bot.map(&:content)).to eq([lista])
          expect(cadeias).to be_empty
          expect(agent.events.replied).to be_empty
        end
      end
    end

    it 'a resposta ilegível do modelo também é turno mudo: a lista sai sozinha' do
      with_modified_env(AI_HUMANIZE_DELIVERY: 'false') do
        stub_ai_turn(nil, bruto: 'isto não é json')

        expect(responder.perform.status).to eq(:silenced)
        expect(mensagens_do_bot.map(&:content)).to eq([lista])
      end
    end

    # O ANEXO NÃO DERRUBA O DESPACHO: no turno mudo sem anexo a execução assíncrona aceita é despachada, e o aviso e o
    # resultado saem pelo job. A gravação da lista que falha não pode descartá-la.
    describe 'com uma ferramenta assíncrona aceita no mesmo turno e a gravação da lista falhando' do
      let(:assincrona) { build_async_tool(slug: 'consultar_cotacao') }
      let(:catalogo) { [anexadora, assincrona] }
      let(:chamada_assincrona) { { 'name' => 'consultar_cotacao', 'call_id' => 'c2', 'arguments' => '{}' } }

      [%w[clássica false], %w[humanizada true]].each do |nome, humanizada|
        it "com a entrega #{nome}, a assíncrona é despachada e o turno continua mudo" do
          with_modified_env(AI_HUMANIZE_DELIVERY: humanizada) do
            stub_ai_turn(described_class::SILENCE_TOKEN, chamadas: [chamada, chamada_assincrona])
            allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'banco fora')

            expect(responder.perform.status).to eq(:silenced)
            expect(Autonomia::Agents::ToolRun.sole).to have_attributes(status: 'running', notify_customer: true, expected_chunks: 0)
            expect(enqueued_jobs.count { |item| item[:job] == Autonomia::Agents::Tools::AsyncRunJob }).to eq(1)
            expect(mensagens_do_bot).to be_empty
          end
        end
      end
    end
  end

  describe 'entrega humanizada' do
    around do |example|
      with_modified_env(AI_HUMANIZE_DELIVERY: 'true') { example.run }
    end

    it 'a lista entra no fim da cadeia como um pedaço inteiro, sem passar pelo quebrador' do
      stub_ai_turn(fala)
      pedacos = Autonomia::Agents::Operate::ReplyChunker.call(fala)

      responder.perform

      chunks = ActiveJob::Arguments.deserialize(cadeias.sole[:args])[3]
      expect(pedacos.size).to be > 1
      expect(chunks.map { |chunk| chunk['text'] }).to eq(pedacos.map { |chunk| chunk['text'] } + [lista])
      expect(mensagens_do_bot).to be_empty
    end

    it 'a cadeia posta a fala e depois a lista' do
      stub_ai_turn(fala)

      responder.perform
      rodar_cadeia

      expect(mensagens_do_bot.map(&:content)).to eq(Autonomia::Agents::Operate::ReplyChunker.call(fala).map { |chunk| chunk['text'] } + [lista])
    end

    # O retry antes de o primeiro pedaço sair enfileira outra cadeia; a segunda para no pedaço que a primeira já postou.
    it 'o retry do ReplyJob não repete a lista' do
      stub_ai_turn(fala)

      2.times { responder.perform }
      rodar_cadeia(0)
      rodar_cadeia(1)

      expect(mensagens_do_bot.map(&:content).count(lista)).to eq(1)
      expect(mensagens_do_bot.size).to eq(Autonomia::Agents::Operate::ReplyChunker.call(fala).size + 1)
    end

    # A ENTREGA ASSÍNCRONA DO MESMO TURNO espera o último pedaço da cadeia: o número conta a lista.
    describe 'com uma ferramenta assíncrona aceita no mesmo turno' do
      let(:assincrona) { build_async_tool(slug: 'consultar_cotacao') }
      let(:catalogo) { [anexadora, assincrona] }

      it 'expected_chunks conta os pedaços da fala e a lista' do
        stub_ai_turn(fala, chamadas: [chamada, { 'name' => 'consultar_cotacao', 'call_id' => 'c2', 'arguments' => '{}' }])

        responder.perform

        run = Autonomia::Agents::ToolRun.sole
        expect(run.expected_chunks).to eq(Autonomia::Agents::Operate::ReplyChunker.call(fala).size + 1)
        expect(run.expected_chunks).to eq(ActiveJob::Arguments.deserialize(cadeias.sole[:args])[3].size)
      end
    end
  end

  describe 'entrega em voz' do
    around do |example|
      with_modified_env(AI_HUMANIZE_DELIVERY: 'false') { example.run }
    end

    def em_voz(audio)
      turno = responder
      allow(turno).to receive_messages(voice_reply_applies?: true, synthesize_audio: audio)
      turno
    end

    it 'o áudio sai primeiro e a lista depois, como texto' do
      stub_ai_turn(fala)

      em_voz("OggS\x00audio".b).perform

      expect(mensagens_do_bot.size).to eq(2)
      expect(mensagens_do_bot.first.attachments.map(&:file_type)).to eq(['audio'])
      expect(mensagens_do_bot.last).to have_attributes(content: lista)
      expect(mensagens_do_bot.last.attachments).to be_empty
    end

    it 'com a síntese falhando, a fala em texto e depois a lista' do
      stub_ai_turn(fala)

      em_voz(nil).perform

      expect(mensagens_do_bot.map(&:content)).to eq([fala, lista])
    end
  end
end
