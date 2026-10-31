require 'rails_helper'

# #1479 F3: o mapa e o cartão de contato que as ferramentas marcaram no turno saem DEPOIS do texto, numa mensagem
# própria, com conteúdo vazio e o `rich_message` do cartão, nos três caminhos (clássico, em pedaços e em áudio). O
# turno refeito não manda o cartão de novo, e o cartão não faz o retry pular o texto. Sem cartão, nada muda.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:mapa) do
    { 'tipo' => 'location', 'chave' => 'a1b2c3d4',
      'rich_message' => { 'type' => 'location', 'latitude' => -23.5489, 'longitude' => -46.6388, 'name' => 'Unidade Centro',
                          'address' => 'Rua Direita, 100' } }
  end
  let(:cartao_de_contato) do
    { 'tipo' => 'contact', 'chave' => 'pagina', 'rich_message' => { 'type' => 'contact', 'name' => 'Clínica', 'phone' => '+551140000473' } }
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

  describe 'entrega clássica' do
    it 'o texto, depois o mapa: conteúdo vazio e o rich_message do cartão' do
      responde('Fica no Centro.', [mapa])
      perform

      expect(enviadas.map(&:content)).to eq(['Fica no Centro.', ''])
      expect(enviadas.last.content_attributes['rich_message']).to eq(mapa['rich_message'])
      expect(enviadas.last.content_attributes['autonomia_agent_id']).to eq(agent.id)
      expect(enviadas.last.content_attributes).not_to have_key('autonomia_reply_to_message_id')
      expect(enviadas.last.sender).to eq(agent_bot)
    end

    it 'dois cartões, na ordem em que foram marcados' do
      responde('Aqui estão.', [mapa, cartao_de_contato])
      perform
      expect(enviadas.map { |mensagem| mensagem.content_attributes.dig('rich_message', 'type') }).to eq([nil, 'location', 'contact'])
    end

    it 'perform repetido (retry): um texto e um cartão' do
      responde('Fica no Centro.', [mapa])
      2.times { perform }
      expect(enviadas.size).to eq(2)
      expect(cartoes_enviados.size).to eq(1)
    end

    it 'o retry depois do texto sem o cartão (o modelo só o marcou na 2ª vez): o cartão sai, o texto não repete' do
      responde('Fica no Centro.', [])
      perform
      responde('Fica no Centro.', [mapa])
      perform
      expect(enviadas.map(&:content)).to eq(['Fica no Centro.', ''])
    end

    it 'o cartão já enviado não faz o retry pular o texto' do
      responde('Fica no Centro.', [mapa])
      perform
      enviadas.first.destroy!
      perform
      expect(enviadas.map(&:content)).to eq(['', 'Fica no Centro.'])
      expect(cartoes_enviados.size).to eq(1)
    end

    it 'sem cartão marcado: as mesmas mensagens de antes' do
      responde('Fica no Centro.', [])
      perform
      expect(enviadas.sole.content).to eq('Fica no Centro.')
      expect(enviadas.sole.content_attributes.keys).to contain_exactly('autonomia_agent_id', 'autonomia_reply_to_message_id')
    end

    it 'turno em silêncio: o cartão não sai' do
      responde('', [mapa])
      expect(perform.status).to eq(:silenced)
      expect(enviadas).to be_empty
    end

    context 'when the inbox does not take the format (site chat)' do
      let(:inbox) { create(:inbox, account: account) }
      let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

      it 'o cartão sai em texto, sem rich_message' do
        responde('Fica no Centro.', [mapa])
        perform
        expect(enviadas.last.content).to eq("Unidade Centro\nRua Direita, 100\nhttps://maps.google.com/?q=-23.5489,-46.6388")
        expect(enviadas.last.content_attributes).not_to have_key('rich_message')
      end
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

    it 'o cartão é o último pedaço, depois do texto e da interação de opções' do
      responde("Temos duas unidades.\n\nA do Centro abre às 8h.", [mapa], interacao: opcoes)
      perform
      pedacos = pedacos_agendados
      expect(pedacos.last).to include('corpo' => '', 'rich_message' => mapa['rich_message'])
      expect(pedacos.last['text']).to include('maps.google.com')
      expect(pedacos[-2]).to include('rich_message' => hash_including('type' => 'options'))

      entregar(pedacos)
      expect(enviadas.map { |mensagem| mensagem.content_attributes.dig('rich_message', 'type') }.last(2)).to eq(%w[options location])
      expect(enviadas.last.content).to eq('')
    end

    it 'o worker antigo (só `text`) manda a versão em texto do cartão' do
      responde('Fica no Centro.', [mapa])
      perform
      entregar(pedacos_agendados.map { |pedaco| pedaco.except('rich_message', 'corpo') })
      expect(enviadas.last.content).to include('Unidade Centro', 'maps.google.com')
    end

    it 'o pedaço repetido (retry do job) não duplica o cartão' do
      responde('Fica no Centro.', [mapa])
      perform
      pedacos = pedacos_agendados
      entregar(pedacos)
      entregar(pedacos)
      expect(enviadas.count { |mensagem| mensagem.content_attributes.key?('rich_message') }).to eq(1)
    end

    it 'sem cartão marcado: os mesmos pedaços de antes' do
      responde('Fica no Centro.', [])
      perform
      expect(pedacos_agendados.size).to eq(1)
      expect(pedacos_agendados.sole).not_to have_key('rich_message')
    end
  end

  describe 'resposta em áudio' do
    before do
      allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(true) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return('OggS-bytes') # rubocop:disable RSpec/AnyInstance
    end

    it 'o áudio, a interação, depois o cartão' do
      responde('Temos vaga amanhã.', [mapa], interacao: opcoes)
      resultado = perform
      expect(enviadas.size).to eq(3)
      expect(enviadas.first.content_attributes['autonomia_voice']).to be(true)
      expect(enviadas.second.content_attributes['rich_message']).to include('type' => 'options')
      expect(enviadas.last.content_attributes['rich_message']).to eq(mapa['rich_message'])
      expect(resultado.message).to eq(enviadas.first)
    end

    it 'perform repetido: um áudio e um cartão' do
      responde('Temos vaga amanhã.', [mapa])
      2.times { perform }
      expect(enviadas.size).to eq(2)
      expect(cartoes_enviados.size).to eq(1)
    end
  end
end
