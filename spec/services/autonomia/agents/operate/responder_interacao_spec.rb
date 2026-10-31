require 'rails_helper'

# #1479 F1: a interação pedida pelo modelo sai na ÚLTIMA mensagem da resposta. Clássico: a resposta e a pergunta no
# corpo. Em pedaços: a pergunta é o último pedaço, e só ele leva o formato. Em áudio: o áudio e, depois que ele sai
# para o canal, a lista (`InteracaoDepoisDoAudio`, pelo `EnviarCartoesJob`).
# Caixa que não leva o formato (e-mail, chat do site): texto, sem `rich_message`.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:opcoes) do
    Autonomia::Agents::Interacao.do_modelo(
      { 'tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?',
        'opcoes' => [{ 'id' => 'manha', 'titulo' => 'Manhã' }, { 'id' => 'tarde', 'titulo' => 'Tarde' }] }, enderecos: Set.new
    )
  end
  let(:url) { 'https://loja.exemplo.com/pedido/42' }
  let(:link) do
    Autonomia::Agents::Interacao.do_modelo({ 'tipo' => 'link', 'link' => { 'rotulo' => 'Ver pedido', 'url' => url } }, enderecos: Set[url])
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: 'quero agendar')
  end

  def responde(reply, interacao)
    resultado = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil },
                                                    interacao: interacao)
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: resultado))
  end

  def perform
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform
  end

  def enviadas
    conversation.messages.outgoing.order(:id).to_a
  end

  describe 'entrega clássica' do
    it 'WhatsApp oficial com a janela aberta: a resposta e a pergunta no corpo, com as opções' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      expect(enviadas.size).to eq(1)
      expect(enviadas.last.content).to eq("Temos vaga amanhã.\n\nQual período?")
      expect(enviadas.last.content_attributes['rich_message']).to include('type' => 'options', 'header' => 'Agendamento')
      expect(enviadas.last.content_attributes['autonomia_agent_id']).to eq(agent.id)
    end

    it 'link: o botão vai na resposta' do
      responde('Seu pedido saiu.', link)
      perform
      expect(enviadas.last.content).to eq('Seu pedido saiu.')
      expect(enviadas.last.content_attributes['rich_message']).to eq('type' => 'link_button', 'label' => 'Ver pedido', 'url' => url)
    end

    it 'sem interação: a mensagem de sempre, sem a chave' do
      responde('Temos vaga amanhã.', nil)
      perform
      expect(enviadas.last.content).to eq('Temos vaga amanhã.')
      expect(enviadas.last.content_attributes.keys).to contain_exactly('autonomia_agent_id', 'autonomia_reply_to_message_id')
    end

    context 'when the inbox is e-mail' do
      let(:inbox) { create(:channel_email, account: account).inbox }
      let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

      it 'sai em texto, com as opções numeradas, sem rich_message' do
        responde('Temos vaga amanhã.', opcoes)
        perform
        expect(enviadas.last.content).to eq("Temos vaga amanhã.\n\nQual período?\n\n1. Manhã\n2. Tarde")
        expect(enviadas.last.content_attributes).not_to have_key('rich_message')
      end
    end

    context 'when the inbox is the site chat' do
      let(:inbox) { create(:inbox, account: account) }
      let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

      it 'sai em texto, com o link escrito, sem rich_message' do
        responde('Seu pedido saiu.', link)
        perform
        expect(enviadas.last.content).to eq("Seu pedido saiu.\n\nVer pedido: #{url}")
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

    it 'a pergunta é o último pedaço e só ele leva o formato; o job o posta com o rich_message' do
      responde("Temos vaga amanhã.\n\nO atendimento dura uma hora.", opcoes)
      perform
      pedacos = pedacos_agendados
      expect(pedacos.last).to include('corpo' => 'Qual período?', 'rich_message' => hash_including('type' => 'options'))
      expect(pedacos[0...-1]).to all(satisfy { |pedaco| !pedaco.key?('rich_message') })

      pedacos.each_index do |indice|
        Autonomia::Agents::Operate::ChunkedDeliveryJob.new.perform(conversation.id, agent_inbox.id, nil, pedacos, indice, {})
      end
      expect(enviadas.map(&:content).last).to eq('Qual período?')
      expect(enviadas.map { |mensagem| mensagem.content_attributes.key?('rich_message') }).to eq(([false] * (pedacos.size - 1)) + [true])
      expect(enviadas.last.content_attributes['rich_message']).to include('type' => 'options')
    end

    it 'link: o formato vai no último pedaço da resposta' do
      responde('Seu pedido saiu.', link)
      perform
      expect(pedacos_agendados.size).to eq(1)
      expect(pedacos_agendados.last).to include('corpo' => 'Seu pedido saiu.', 'rich_message' => hash_including('url' => url))
    end

    # Deploy com as stacks misturadas: o worker antigo só lê `text` (não conhece `rich_message` nem `corpo`). O pedaço
    # que ele recebe manda a versão em texto inteira, e nunca a pergunta sem as opções.
    it 'o worker que ainda não conhece o formato manda as opções numeradas' do
      responde('Temos vaga amanhã.', opcoes)
      perform
      como_o_antigo_le = pedacos_agendados.map { |pedaco| pedaco.except('rich_message', 'corpo') }
      como_o_antigo_le.each_index do |indice|
        Autonomia::Agents::Operate::ChunkedDeliveryJob.new.perform(conversation.id, agent_inbox.id, nil, como_o_antigo_le, indice, {})
      end
      expect(enviadas.last.content).to eq("Qual período?\n\n1. Manhã\n2. Tarde")
      expect(enviadas.last.content_attributes).not_to have_key('rich_message')
    end
  end

  describe 'resposta em áudio' do
    before do
      allow_any_instance_of(described_class).to receive(:voice_reply_applies?).and_return(true) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return('OggS-bytes') # rubocop:disable RSpec/AnyInstance
    end

    # O canal confirma o áudio (o `source_id` da Meta) e o job da âncora roda.
    def depois_do_audio
      enviadas.first.update_column(:source_id, 'wamid.AUDIO') # rubocop:disable Rails/SkipsModelValidations
      Autonomia::Agents::Operate::EnviarCartoesJob.perform_now(enviadas.first.id)
    end

    it 'o áudio e, depois que ele sai, a lista numa mensagem própria' do
      responde('Temos vaga amanhã.', opcoes)
      resultado = perform
      expect(enviadas.size).to eq(1)
      depois_do_audio
      expect(enviadas.size).to eq(2)
      expect(enviadas.first.content_attributes['autonomia_voice']).to be(true)
      expect(resultado.message).to eq(enviadas.first)
      expect(enviadas.last.content).to eq('Qual período?')
      expect(enviadas.last.content_attributes['rich_message']).to include('type' => 'options')
    end

    it 'link depois do áudio: o rótulo no corpo' do
      responde('Seu pedido saiu.', link)
      perform
      depois_do_audio
      expect(enviadas.last.content).to eq('Ver pedido')
      expect(enviadas.last.content_attributes['rich_message']).to include('type' => 'link_button')
    end

    it 'sem interação: só o áudio, como antes' do
      responde('Temos vaga amanhã.', nil)
      perform
      expect(enviadas.size).to eq(1)
    end

    it 'síntese falhou: cai no texto, com a interação' do
      allow_any_instance_of(described_class).to receive(:synthesize_audio).and_return(nil) # rubocop:disable RSpec/AnyInstance
      responde('Temos vaga amanhã.', opcoes)
      perform
      expect(enviadas.size).to eq(1)
      expect(enviadas.last.content).to eq("Temos vaga amanhã.\n\nQual período?")
    end

    context 'when the inbox does not take the format (site chat)' do
      let(:inbox) { create(:inbox, account: account) }
      let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

      it 'link depois do áudio: só a versão em texto do link, sem repetir o rótulo' do
        responde('Seu pedido saiu.', link)
        perform
        depois_do_audio
        expect(enviadas.last.content).to eq("Ver pedido: #{url}")
        expect(enviadas.last.content_attributes).not_to have_key('rich_message')
      end
    end
  end

  it 'só a pergunta das opções, sem texto antes, ainda é resposta' do
    responde('', opcoes)
    perform
    expect(enviadas.last.content).to eq('Qual período?')
    expect(enviadas.last.content_attributes['rich_message']).to include('type' => 'options')
  end

  it 'sem texto e sem interação continua silêncio' do
    responde('', nil)
    expect(perform.status).to eq(:silenced)
    expect(enviadas).to be_empty
  end

  def vazias(pergunta)
    Autonomia::Agents::Interacao.do_modelo({ 'tipo' => 'opcoes', 'header' => 'A', 'pergunta' => pergunta, 'opcoes' => [] }, enderecos: Set.new)
  end

  it 'opções sem nenhuma opção e sem pergunta, com texto vazio: silêncio "vazio"' do
    responde('', vazias(''))
    expect(perform.status).to eq(:silenced)
    expect(enviadas).to be_empty
  end

  it 'opções sem nenhuma opção, com pergunta: a resposta e a pergunta em texto, sem rich_message' do
    responde('Temos vaga amanhã.', vazias('Qual período?'))
    perform
    expect(enviadas.sole.content).to eq("Temos vaga amanhã.\n\nQual período?")
    expect(enviadas.sole.content_attributes).not_to have_key('rich_message')
  end

  it 'opções sem nenhuma opção, só a pergunta: ainda é resposta' do
    responde('', vazias('Qual período?'))
    perform
    expect(enviadas.sole.content).to eq('Qual período?')
  end

  describe 'histórico do modelo' do
    let(:historicos) { [] }
    let(:formato_das_opcoes) do
      { 'type' => 'options', 'header' => 'Agendamento', 'button' => 'Ver opções',
        'options' => [{ 'id' => 'manha', 'title' => 'Manhã' }, { 'id' => 'tarde', 'title' => 'Tarde' }] }
    end

    before do
      resultado = Autonomia::Agents::AnswerResult.new(reply: 'Certo.', confidence: 0.9, handoff: { should: false, reason: nil })
      allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
        historicos << kwargs[:history]
        instance_double(Autonomia::Agents::Answerer, answer: resultado)
      end
    end

    def enviada_com(formato, agente_id: agent.id, sender: agent_inbox.agent_bot)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: sender,
                       content: 'Temos vaga.', content_attributes: { 'autonomia_agent_id' => agente_id, 'rich_message' => formato })
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'a segunda')
    end

    def conteudos
      historicos.last.map { |item| item[:content] }
    end

    it 'as opções e o link que o agente mandou entram com a versão em texto' do
      enviada_com(formato_das_opcoes)
      enviada_com({ 'type' => 'link_button', 'label' => 'Ver pedido', 'url' => url })
      perform
      expect(conteudos).to include("Temos vaga.\n\n1. Manhã\n2. Tarde", "Temos vaga.\n\nVer pedido: #{url}")
    end

    it 'mensagem de outro agente ou de outro remetente fica como está' do
      outro = criar_principal(account, nome: 'Outro')
      enviada_com(formato_das_opcoes, agente_id: outro.id)
      enviada_com(formato_das_opcoes, sender: create(:user, account: account))
      perform
      expect(conteudos.count { |conteudo| conteudo.to_s.include?('Temos vaga.') }).to eq(2)
      expect(conteudos.join).not_to include('1. Manhã')
    end

    it 'robô que não é o espelho de um vínculo deste agente, mesmo com a marca dele, fica como está' do
      enviada_com(formato_das_opcoes, sender: create(:agent_bot, account: account))
      outro = criar_principal(account, nome: 'Outro')
      vinculo_do_outro = { agent: outro, inbox: create(:inbox, account: account), account: account, agent_bot: create(:agent_bot, account: account) }
      espelho_do_outro = Autonomia::Agents::AgentInbox.create!(vinculo_do_outro).agent_bot
      enviada_com(formato_das_opcoes, sender: espelho_do_outro)
      perform
      expect(conteudos.count('Temos vaga.')).to eq(2)
      expect(conteudos.join).not_to include('1. Manhã')
    end

    it 'na Lia o histórico fica como está' do
      enviada_com(formato_das_opcoes)
      enviada = conversation.messages.outgoing.last
      itens = [{ role: 'assistant', content: 'Temos vaga.' }]
      lia = instance_double(Autonomia::Agents::Agent, agent_type: 'insurance_quote', id: agent.id)
      expect(Autonomia::Agents::Interacao.no_historico(itens, [enviada], agent: lia)).to eq(itens)
      expect(Autonomia::Agents::Interacao.no_historico(itens, [enviada], agent: agent).sole[:content]).to include('1. Manhã')
    end
  end

  it 'a limpeza da marca da equipe e da linha de contexto mantém a interação' do
    nota = Autonomia::Agents::Operate::RecoveredHeaderNote::NOTES['image']
    responde("Temos vaga. #{nota}", opcoes)
    perform
    expect(enviadas.last.content).to eq("Temos vaga.\n\nQual período?")
    expect(enviadas.last.content_attributes['rich_message']).to include('type' => 'options')
  end

  it '#1489: a linha de contexto sai também do cabeçalho, da pergunta, dos títulos e do rótulo' do
    nota = Autonomia::Agents::Operate::RecoveredHeaderNote::NOTES['image']
    suja = opcoes.merge('header' => "Agendamento #{nota}", 'pergunta' => "Qual período?\n#{nota}",
                        'opcoes' => [{ 'id' => 'manha', 'title' => "Manhã #{nota}" }, { 'id' => 'tarde', 'title' => 'Tarde' }])
    responde('', suja)
    perform
    expect(enviadas.last.content).to eq('Qual período?')
    expect(enviadas.last.content_attributes['rich_message']).to include('header' => 'Agendamento')
    expect(enviadas.last.content_attributes['rich_message']['options'].pluck('title')).to eq(%w[Manhã Tarde])

    rotulo = Autonomia::Agents::Operate::RecoveredHeaderNote.without_notes(
      Autonomia::Agents::AnswerResult.new(reply: 'ok', confidence: 1, handoff: {}, interacao: link.merge('rotulo' => "Ver #{nota}"))
    )
    expect(rotulo.interacao).to eq(link.merge('rotulo' => 'Ver'))
  end

  it '#1669: a marca da equipe sai também dos textos da interação' do
    equipe = instance_double(Autonomia::Agents::Operate::HistoricoDaEquipe, aplica?: true)
    allow(equipe).to receive(:resposta) { |texto| texto.delete_prefix('[EQUIPE] ') }
    allow(Autonomia::Agents::Operate::HistoricoDaEquipe).to receive(:new).and_return(equipe)
    suja = opcoes.merge('header' => '[EQUIPE] Agendamento', 'pergunta' => '[EQUIPE] Qual período?')
    resultado = Autonomia::Agents::AnswerResult.new(reply: 'Temos vaga.', confidence: 1, handoff: {}, interacao: suja)

    limpo = described_class.new(conversation: conversation, agent_inbox: agent_inbox).send(:sem_marca_da_equipe, resultado)

    expect(limpo.reply).to eq('Temos vaga.')
    expect(limpo.interacao).to include('header' => 'Agendamento', 'pergunta' => 'Qual período?')
  end

  # O `classic_deliver` passa a interação ao `post_reply!`: uma subclasse que o sobrescreve com um argumento só faria
  # o turno falhar em silêncio (ArgumentError resgatado). Pega também as subclasses que vierem depois.
  it 'toda subclasse do Responder aceita a interação no post_reply!' do
    Rails.root.glob('app/services/autonomia/agents/operate/responder_*.rb').each do |arquivo|
      "Autonomia::Agents::Operate::#{arquivo.basename('.rb').to_s.camelize}".safe_constantize
    end
    expect(described_class.descendants).to include(Autonomia::Agents::Operate::ResponderAoEvento, Autonomia::Agents::Operate::ResponderAPassagem)
    expect(([described_class] + described_class.descendants).map { |classe| classe.instance_method(:post_reply!).arity }).to all(eq(-2))
  end
end
