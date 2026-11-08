require 'rails_helper'

# #1925: card que renasce. O contato já teve neste funil um card ENCERRADO antes de este nascer; a IA de etapa recebe o
# que veio antes ("previous_card") e decide, ela mesma, se é o mesmo pedido retomado.
RSpec.describe Crm::Ai::PedidoAnterior do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversa_antiga) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:conversa_nova) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  def card!(titulo, conversa, status: :open, **extra)
    account.crm_cards.create!({ pipeline: pipeline, stage: stage, contact: contact }.merge(extra)
                                .merge(title: titulo, primary_conversation: conversa, currency: 'BRL', status: status))
  end

  def mensagem!(conversa, texto, tipo: :incoming, quando: Time.current)
    conversa.messages.create!(account: account, inbox: inbox, message_type: tipo, content: texto, created_at: quando,
                              sender: tipo == :incoming ? contact : admin)
  end

  def contexto(card, **opcoes) = Crm::Ai::ContextBuilder.new(card: card, pedido_anterior: true, **opcoes).perform

  describe 'card novo em outra conversa, depois de um card perdido no mesmo funil' do
    before do
      travel_to(3.days.ago) do
        card!('Cotação do carro', conversa_antiga, value_cents: 120_000).tap do |card|
          mensagem!(conversa_antiga, 'Quero cotar o seguro do carro')
          mensagem!(conversa_antiga, 'A cotação ficou em R$ 1.200 por ano', tipo: :outgoing)
          card.update!(status: :lost)
        end
      end
      mensagem!(conversa_nova, 'Oi, ainda vale aquela cotação?')
    end

    let(:novo) { card!('Oi', conversa_nova) }

    # Pega: a IA de etapa do card novo não enxergar a cotação enviada antes (o recorte por conversa do card).
    it 'traz o card anterior com as mensagens dele, marcadas como antes deste card', :aggregate_failures do
      anterior_payload = contexto(novo)[:previous_card]

      expect(anterior_payload).to include(title: 'Cotação do carro', status: 'lost', stage: stage.name,
                                          value: { amount_cents: 120_000, currency: 'BRL' })
      expect(anterior_payload[:closed_at]).to be_present
      expect(anterior_payload[:messages].pluck(:content)).to eq(['Quero cotar o seguro do carro', 'A cotação ficou em R$ 1.200 por ano'])
      expect(anterior_payload[:messages].pluck(:role)).to eq(%w[customer human_agent])
    end

    # Pega: as mensagens de outro pedido ganharem id local da memória e virarem prova de fato deste card.
    it 'as mensagens de antes não ganham id local da memória' do
      anterior_payload = contexto(novo, memoria: true)[:previous_card]

      expect(anterior_payload[:messages]).to all(satisfy { |mensagem| !mensagem.key?(:ref) })
    end

    # Pega: o custo subir para quem não lê o bloco (follow-up, resumo, sugestões usam o mesmo ContextBuilder).
    it 'só entra quando quem chama pede' do
      expect(Crm::Ai::ContextBuilder.new(card: novo).perform).not_to have_key(:previous_card)
    end

    # Pega: um pedido de outro funil ser lido como o mesmo pedido deste.
    it 'ignora card de outro funil' do
      outro_funil, outra_etapa = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
      novo_em_outro = card!('Oi', conversa_nova, pipeline: outro_funil, stage: outra_etapa)

      expect(contexto(novo_em_outro)).not_to have_key(:previous_card)
    end

    # Pega: o card de outra pessoa (mesma conta) vazar para este.
    it 'ignora card de outro contato' do
      outra_pessoa = create(:contact, account: account)
      conversa_dela = create_crm_conversation(account: account, inbox: inbox, contact: outra_pessoa)

      expect(contexto(card!('Oi', conversa_dela, contact: outra_pessoa))).not_to have_key(:previous_card)
    end
  end

  # Pega: um card aberto (que já está em other_subjects) ou arquivado (descartado) ser tratado como pedido encerrado.
  it 'ignora card aberto e card arquivado' do
    travel_to(2.days.ago) do
      card!('Aberto', conversa_antiga)
      card!('Arquivado', conversa_antiga, status: :archived)
    end

    expect(contexto(card!('Novo', conversa_nova))).not_to have_key(:previous_card)
  end

  # Pega: um card que nasceu DEPOIS deste ser tomado como o que veio antes.
  it 'ignora card que nasceu depois deste' do
    novo = card!('Novo', conversa_nova)
    travel_to(1.minute.from_now) { card!('Depois', conversa_antiga).update!(status: :lost) }

    expect(contexto(novo)).not_to have_key(:previous_card)
  end

  # Pega: card irmão (outro assunto vivo quando este nasceu) e encerrado depois ser tomado como pedido anterior (#1925
  # revisão): o prompt afirmaria um fato falso e a etapa/valor de outro assunto contaria como evidência deste.
  it 'ignora card que estava aberto quando este nasceu e foi encerrado depois' do
    irmao = travel_to(2.days.ago) { card!('Seguro da moto', conversa_antiga) }
    novo = card!('Seguro do carro', conversa_nova)
    travel_to(1.minute.from_now) { irmao.update!(status: :lost) }

    expect(contexto(novo)).not_to have_key(:previous_card)
  end

  # Pega: entre dois pedidos encerrados, ir o mais velho.
  it 'pega o encerrado mais recente' do
    travel_to(10.days.ago) { card!('Velho', conversa_antiga).update!(status: :lost) }
    travel_to(2.days.ago) { card!('Recente', conversa_antiga).update!(status: :lost) }

    expect(contexto(card!('Novo', conversa_nova))[:previous_card]).to include(title: 'Recente', status: 'lost')
  end

  # Pega: a venda ganha voltar como "mesmo pedido" e o card novo herdar etapa e valor (a venda contaria duas vezes); e,
  # com o último encerrado ganho, cair num perdido mais velho que já não é o pedido de antes.
  it 'sem pedido anterior quando o último encerrado deu certo' do
    travel_to(10.days.ago) { card!('Velho', conversa_antiga).update!(status: :lost) }
    travel_to(2.days.ago) { card!('Ganho', conversa_antiga, value_cents: 50_000).update!(status: :won) }

    expect(contexto(card!('Novo', conversa_nova))).not_to have_key(:previous_card)
  end

  describe 'as mensagens são da vida do card anterior' do
    let(:conversa_email) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

    # Pega: o assunto de antes na mesma conversa, ou a volta depois do encerramento, irem como mensagens do anterior; e a
    # mensagem que abriu o card (chega antes do nascimento dele) ficar de fora.
    it 'do fim do pedido de antes até o encerramento dele, sem cortar a mensagem que o abriu', :aggregate_failures do
      travel_to(6.days.ago) do
        mensagem!(conversa_antiga, 'assunto velho', quando: 1.minute.ago)
        card!('Antes', conversa_antiga).update!(status: :lost)
      end
      anterior = travel_to(3.days.ago) do
        mensagem!(conversa_antiga, 'quero cotar o carro', quando: 1.minute.ago)
        card!('Carro', conversa_antiga).tap { mensagem!(conversa_antiga, 'R$ 1.200 por ano', tipo: :outgoing) }
      end
      travel_to(2.days.ago) { anterior.update!(status: :lost) }
      mensagem!(conversa_antiga, 'oi, voltei', quando: 1.day.ago)

      expect(described_class.do_card(card!('Novo', conversa_nova))).to eq(anterior)
      expect(described_class.mensagens(anterior.reload, fora: []).map(&:content)).to eq(['quero cotar o carro', 'R$ 1.200 por ano'])
    end

    # Pega: a proposta enviada numa conversa VINCULADA ao card anterior (outro canal) não chegar ao modelo.
    it 'lê também as conversas vinculadas ao card anterior' do
      anterior = travel_to(3.days.ago) do
        card!('Carro', conversa_antiga).tap do |card|
          account.crm_card_conversations.create!(card: card, conversation: conversa_email, linked_by: admin)
          mensagem!(conversa_antiga, 'quero cotar o carro')
          mensagem!(conversa_email, 'proposta em anexo: R$ 1.200', tipo: :outgoing)
          card.update!(status: :lost)
        end
      end

      expect(described_class.mensagens(anterior, fora: []).map(&:content)).to contain_exactly('quero cotar o carro', 'proposta em anexo: R$ 1.200')
    end
  end

  describe 'card novo na MESMA conversa do card encerrado' do
    # Pega: repetir no bloco o que já está em recent_messages, ou trazer o que veio depois do encerramento.
    it 'leva só o que veio na vida do anterior e ainda não está nas mensagens recentes', :aggregate_failures do
      anterior = travel_to(2.days.ago) { card!('Cotação', conversa_antiga) }
      antigas = Array.new(14) { |i| mensagem!(conversa_antiga, "antiga #{i}", quando: 2.days.ago + (i + 1).minutes) }
      travel_to(2.days.ago + 15.minutes) { anterior.update!(status: :lost) }
      novo = card!('Novo', conversa_antiga)
      mensagem!(conversa_antiga, 'depois do card')

      resultado = contexto(novo)
      recentes = resultado[:recent_messages].pluck(:content)
      anteriores = resultado[:previous_card][:messages].pluck(:content)

      expect(recentes.size).to eq(Crm::Ai::ContextBuilder::MAX_RECENT_MESSAGES)
      expect(anteriores).to eq(antigas.first(14 - (Crm::Ai::ContextBuilder::MAX_RECENT_MESSAGES - 1)).map(&:content))
      expect(anteriores & recentes).to be_empty
      expect(anteriores).not_to include('depois do card')
    end
  end

  # Pega: conversa antiga longa inflar o prompt.
  it 'leva no máximo MAX_MENSAGENS mensagens, as mais recentes' do
    travel_to(2.days.ago) do
      anterior = card!('Cotação', conversa_antiga)
      Array.new(12) { |i| mensagem!(conversa_antiga, "m#{i}", quando: (12 - i).minutes.ago) }
      anterior.update!(status: :lost)
    end

    anteriores = contexto(card!('Novo', conversa_nova))[:previous_card][:messages].pluck(:content)

    expect(anteriores).to eq(((12 - described_class::MAX_MENSAGENS)...12).map { |i| "m#{i}" })
  end

  # Pega: tirar `pedido_anterior: true` do Evaluator e o eval (desligado por padrão) ser o único a perceber.
  it 'a avaliação de card (Evaluator) manda o pedido anterior ao classificador' do
    travel_to(3.days.ago) { card!('Cotação', conversa_antiga).update!(status: :lost) }

    pacote = Crm::Ai::Evaluator.new(card: card!('Novo', conversa_nova), trigger: 'manual').stage_classifier(client: nil).pacote

    expect(pacote[:previous_card]).to include(title: 'Cotação', status: 'lost')
  end

  describe Crm::Ai::StageClassifier do
    let(:anterior) { { title: 'Cotação', status: 'lost', messages: [{ role: 'customer', content: 'oi' }] } }
    let(:card) { card!('Novo', conversa_nova) }

    def classificador(contexto)
      base = { summary: '', recent_messages: [], current_stage: { id: stage.id, name: stage.name }, known_attributes: {},
               conversation_state: {}, temporal: {}, other_subjects: [] }
      described_class.new(card: card, client: nil, stages: [stage], context: base.merge(contexto))
    end

    # Pega: o bloco montado não chegar ao modelo, ou chegar fora do pacote do card na avaliação conjunta.
    it 'manda previous_card no pacote do card e o parágrafo dele no prefixo', :aggregate_failures do
      com = classificador(previous_card: anterior)

      expect(JSON.parse(com.send(:user_input))['previous_card']).to eq(anterior.deep_stringify_keys)
      expect(com.pacote[:previous_card]).to eq(anterior)
      expect(com.send(:instructions)).to end_with(Crm::Ai::ClassifierPrompt::PEDIDO_ANTERIOR)
    end

    # Pega: na avaliação conjunta, o card com pedido anterior ir sem o parágrafo que explica o bloco.
    it 'a avaliação conjunta leva o parágrafo quando algum card tem pedido anterior', :aggregate_failures do
      classificadores = [classificador(previous_card: anterior), classificador({})]
      cliente = instance_double(Crm::Ai::ResponsesClient)
      allow(cliente).to receive(:create).and_return(text: { cards: [] }.to_json)
      allow(Crm::Ai::OutrasConversas).to receive(:por_card).and_return({})

      Crm::Ai::ClassificacaoConjunta.new(client: cliente, classificadores: classificadores, model: 'gpt-6-luna').perform

      expect(cliente).to have_received(:create).with(hash_including(instructions: end_with(Crm::Ai::ClassifierPrompt::PEDIDO_ANTERIOR)))
      expect(Crm::Ai::ClassifierPrompt.para_varios([], pedido_anterior: true)).to start_with(Crm::Ai::ClassifierPrompt::TEXT_VARIOS)
    end

    # Pega: o prefixo em cache mudar para todas as avaliações sem card anterior.
    it 'sem card anterior, a entrada e o prefixo ficam como antes', :aggregate_failures do
      sem = classificador({})

      expect(JSON.parse(sem.send(:user_input))).not_to have_key('previous_card')
      expect(sem.send(:instructions)).to equal(Crm::Ai::ClassifierPrompt::TEXT)
    end
  end
end
