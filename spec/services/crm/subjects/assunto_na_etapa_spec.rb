require 'rails_helper'

# #1910: com a flag `crm_assunto_na_etapa`, a IA de assunto cria o card direto na coluna certa do funil. O modelo maior,
# que já dá o nome ao pedido novo, escolhe também a etapa pela frase de cada uma, ou "nenhuma etapa clara" (1ª etapa).
# O Jev e o modelo maior são simulados: nenhuma IA paga.
RSpec.describe 'IA de assunto cria o card na coluna certa' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:mode) { :auto }
  # Atender, com colunas por assunto. A 1ª é a chegada; "Resolvido" é de fechamento e nunca recebe card novo.
  let(:pos_venda) do
    funil('Pós-venda', vender: false, etapas: [%w[Chegada novo], %w[Sinistros andamento], %w[Financeiro andamento],
                                               %w[Resolvido resolvido]])
  end
  # Vender: só etapas de categoria novo/andamento. "Negociação" não tem categoria e "Fechado" é de ganho: ficam de fora.
  let(:vendas) do
    funil('Vendas', vender: true, etapas: [['Novo lead', 'novo'], %w[Proposta andamento], ['Negociação', nil], ['Fechado', 'novo']],
                    ganho: 'Fechado')
  end

  before do
    pos_venda
    vendas
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: mode)
    account.enable_features!(Crm::Subjects::Etapa::FLAG)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(Crm::StageAutomations::Runner).to receive(:new).and_wrap_original do |original, **args|
      entradas_de_etapa << args.slice(:from_stage_id, :to_stage_id, :automation_context)
      original.call(**args)
    end
  end

  # Um funil ligado à caixa. etapas: [nome, categoria], todas com frase; ganho: o nome da etapa de ganho.
  def funil(nome, vender:, etapas:, ganho: nil)
    pipeline, primeira = create_crm_pipeline(account: account, user: admin, name: nome)
    pipeline.update!(counts_as_sale: vender)
    etapas.each_with_index do |(etapa, categoria), posicao|
      stage = posicao.zero? ? primeira : create_crm_stage(account: account, pipeline: pipeline, name: etapa, position: posicao)
      stage.update!(name: etapa, is_won_stage: etapa == ganho,
                    metadata: { 'ai_criteria' => "Cliente fala de #{etapa}", 'category' => categoria }.compact)
    end
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: primeira, auto_create_card: false,
                                         created_by: admin)
    pipeline
  end

  def etapa(pipeline, nome) = pipeline.stages.find_by!(name: nome)
  def primeira(pipeline) = pipeline.stages.order(:position, :id).first
  def chave(pipeline, nome) = "etapa_#{etapa(pipeline, nome).id}"

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def stub_jev(choice)
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(
      status: 200,
      body: { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
              answers: { decisao: { type: 'choice', choice: choice, confidence: 0.95 } } }.to_json
    )
  end

  # Serve às duas perguntas (um assunto e vários assuntos). assuntos: [[resposta, titulo, etapa]]; o principal é o último.
  def stub_review(*assuntos)
    resposta, titulo, etapa = assuntos.last
    itens = assuntos.map { |item| { resposta: item[0], titulo: item[1], seguro: true, etapa: item[2] }.compact }
    corpo = { resposta: resposta, titulo: titulo, seguro: true, motivo: 'ok', etapa: etapa, assuntos: itens,
              principal: itens.size - 1 }.compact
    allow(cliente).to receive(:create).and_return(text: corpo.to_json)
  end

  def pedido(pipeline, titulo, etapa_chave)
    stub_jev("novo_#{pipeline.id}")
    stub_review(["novo_#{pipeline.id}", titulo, etapa_chave])
  end

  def identify(message)
    Crm::Subjects::Identifier.new(conversation: conversation, message: message).perform
  end

  def chamada_ao_modelo
    argumentos = nil
    expect(cliente).to have_received(:create) { |**args| argumentos = args }
    argumentos.merge(input: JSON.parse(argumentos[:input]))
  end

  # As automações de etapa que rodaram (Crm::StageAutomations::Runner), na ordem.
  def entradas_de_etapa
    @entradas_de_etapa ||= []
  end

  it 'manda ao modelo maior só as etapas que podem receber card novo, com a frase, e a opção "nenhuma etapa clara"' do
    pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

    identify(incoming('Bati o carro ontem, como abro o sinistro?'))

    chamada = chamada_ao_modelo
    etapas = chamada[:input]['stages'].to_h { |funil| [funil['pipeline'], funil['stages'].pluck('name')] }
    expect(etapas).to eq("novo_#{pos_venda.id}" => %w[Chegada Sinistros Financeiro],
                         "novo_#{vendas.id}" => ['Novo lead', 'Proposta'])
    expect(chamada[:input]['stages'].first).to include('kind' => 'serve')
    expect(chamada[:input]['stages'].first['stages'].second).to include('key' => chave(pos_venda, 'Sinistros'),
                                                                        'criteria' => 'Cliente fala de Sinistros')
    expect(chamada[:instructions]).to eq(Crm::Subjects::Reviewer::INSTRUCOES + Crm::Subjects::Reviewer::INSTRUCOES_ETAPA)
    enum = chamada[:schema][:schema][:properties][:etapa][:enum]
    expect(enum).to contain_exactly(Crm::Subjects::Etapa::NENHUMA, *%w[Chegada Sinistros Financeiro].map { |nome| chave(pos_venda, nome) },
                                    chave(vendas, 'Novo lead'), chave(vendas, 'Proposta'))
    expect(chamada[:schema][:schema][:required]).to include('etapa')
  end

  it 'cria o card na etapa escolhida e roda só as automações de entrada dela' do
    pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

    decision = identify(incoming('Bati o carro ontem, como abro o sinistro?'))

    card = account.crm_cards.order(:id).last
    expect(decision).to have_attributes(action: 'create', state: 'applied', card_id: card.id)
    expect(card).to have_attributes(pipeline_id: pos_venda.id, stage_id: etapa(pos_venda, 'Sinistros').id, title: 'Sinistro do Onix')
    expect(entradas_de_etapa).to eq([{ from_stage_id: nil, to_stage_id: etapa(pos_venda, 'Sinistros').id,
                                       automation_context: { source: 'crm_subjects' } }])
  end

  it '"nenhuma etapa clara": o card nasce na 1ª etapa, como antes, sem automação' do
    pedido(pos_venda, 'Dúvida da apólice', Crm::Subjects::Etapa::NENHUMA)

    identify(incoming('Tenho uma dúvida'))

    expect(account.crm_cards.order(:id).last.stage_id).to eq(primeira(pos_venda).id)
    expect(entradas_de_etapa).to be_empty
  end

  it 'etapa de outro funil vale como nenhuma: 1ª etapa do funil escolhido' do
    pedido(pos_venda, 'Sinistro do Onix', chave(vendas, 'Proposta'))

    identify(incoming('Bati o carro ontem'))

    expect(account.crm_cards.order(:id).last).to have_attributes(pipeline_id: pos_venda.id, stage_id: primeira(pos_venda).id)
    expect(entradas_de_etapa).to be_empty
  end

  it 'no funil de Vender, a etapa de andamento escolhida vale' do
    pedido(vendas, 'Seguro do Onix', chave(vendas, 'Proposta'))

    identify(incoming('Recebi a proposta do seguro do Onix, podemos seguir'))

    expect(account.crm_cards.order(:id).last.stage_id).to eq(etapa(vendas, 'Proposta').id)
  end

  it 'falha na automação de entrada não desfaz a decisão nem cria o card de novo' do
    allow(Crm::StageAutomations::Runner).to receive(:new).and_raise(StandardError, 'automação quebrou')
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

    decision = identify(incoming('Bati o carro ontem'))

    expect(decision).to have_attributes(action: 'create', state: 'applied')
    expect(account.crm_cards.count).to eq(1)
    expect(ChatwootExceptionTracker).to have_received(:new)
  end

  it 'mensagem mais nova já na fila: nada nasce e nenhuma automação roda' do
    pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))
    message = incoming('Bati o carro ontem')
    mais_nova = incoming('Esquece, é outra coisa')
    Crm::SubjectDecision.create!(account: account, conversation: conversation, message: mais_nova, mode: 'auto', action: 'none',
                                 state: 'pending')

    decision = identify(message)

    expect(decision.state).to eq('superseded')
    expect(account.crm_cards.count).to eq(0)
    expect(entradas_de_etapa).to be_empty
  end

  context 'with the flag off' do
    before { account.disable_features!(Crm::Subjects::Etapa::FLAG) }

    it 'a pergunta ao modelo maior é a de sempre, palavra por palavra, e o card nasce na 1ª etapa' do
      pedido(pos_venda, 'Sinistro do Onix', nil)

      identify(incoming('Bati o carro ontem'))

      chamada = chamada_ao_modelo
      expect(chamada[:instructions]).to eq(Crm::Subjects::Reviewer::INSTRUCOES)
      expect(chamada[:input].keys).to eq(%w[question options classifier conversation])
      expect(chamada[:schema]).to eq(
        name: 'assunto_revisao',
        schema: { type: 'object', additionalProperties: false, required: %w[resposta titulo seguro motivo],
                  properties: { resposta: { type: 'string', enum: ['sem_assunto', "novo_#{pos_venda.id}", "novo_#{vendas.id}"] },
                                titulo: { type: 'string' }, seguro: { type: 'boolean' }, motivo: { type: 'string' } } }
      )
      expect(account.crm_cards.order(:id).last.stage_id).to eq(primeira(pos_venda).id)
    end
  end

  context 'with the inbox in Suggest mode' do
    let(:mode) { :suggest }

    it 'só sugere, como antes: nenhum card nasce' do
      pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

      decision = identify(incoming('Bati o carro ontem'))

      expect(decision).to have_attributes(action: 'create', state: 'suggested')
      expect(account.crm_cards.count).to eq(0)
    end
  end

  # O card que a caixa cria ao chegar, no mesmo funil do pedido, sem nome: ganha o nome e vai para a coluna escolhida.
  context 'when the inbox creates the card on arrival in the same pipeline' do
    before do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true)
      account.crm_pipeline_inboxes.find_by(pipeline: pos_venda).update!(auto_create_card: true)
    end

    def chega(texto)
      message = incoming(texto)
      [message, Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: message).perform]
    end

    it 'dá o nome e leva o card para a coluna, com as automações de entrada dela' do
      message, chegada = chega('Bati o carro ontem, como abro o sinistro?')
      expect(chegada).to have_attributes(pipeline_id: pos_venda.id, stage_id: primeira(pos_venda).id)
      pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

      decision = identify(message)

      expect(decision).to have_attributes(action: 'rename', state: 'applied', card_id: chegada.id)
      expect(chegada.reload).to have_attributes(title: 'Sinistro do Onix', stage_id: etapa(pos_venda, 'Sinistros').id)
      expect(account.crm_cards.count).to eq(1)
      expect(entradas_de_etapa).to include(from_stage_id: nil, to_stage_id: etapa(pos_venda, 'Sinistros').id,
                                           automation_context: { source: 'crm_subjects' })
    end

    it 'card que já mudou de etapa só ganha o nome: fica onde está' do
      message, chegada = chega('Bati o carro ontem')
      Crm::Cards::Mover.new(card: chegada, actor: nil, target_stage: etapa(pos_venda, 'Financeiro'),
                            automation_context: { skip_automations: true }).perform
      pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

      identify(message)

      expect(chegada.reload).to have_attributes(title: 'Sinistro do Onix', stage_id: etapa(pos_venda, 'Financeiro').id)
    end

    it 'falha ao levar o card para a coluna desfaz o nome e a reserva: o retry do job decide de novo' do
      message, chegada = chega('Bati o carro ontem')
      allow(Crm::Cards::Mover).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
      pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

      expect { identify(message) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(chegada.reload).to have_attributes(title: 'Joana Lima', stage_id: primeira(pos_venda).id)
      expect(Crm::SubjectDecision.count).to eq(0)
      expect(entradas_de_etapa).to be_empty
    end

    it 'card em que uma pessoa mexeu só ganha o nome' do
      message, chegada = chega('Bati o carro ontem')
      Crm::ActivityLogger.new(card: chegada, actor: admin, event_type: 'update', payload: { owner_id: admin.id }).perform
      pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

      identify(message)

      expect(chegada.reload).to have_attributes(title: 'Sinistro do Onix', stage_id: primeira(pos_venda).id)
    end
  end

  # C36 (#1711) e vários assuntos (#1693) vivem atrás da flag `crm_avaliar_toda_mensagem`.
  context 'with crm_avaliar_toda_mensagem on' do
    let(:comercial) do
      funil('Comercial', vender: true, etapas: [%w[Entrada novo]])
    end

    before { account.enable_features!(Crm::Conversations::CardEmFoco::FLAG) }

    it 'C36: o card da chegada em outro funil vai para a coluna escolhida do funil do pedido' do
      comercial
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true)
      account.crm_pipeline_inboxes.find_by(pipeline: comercial).update!(auto_create_card: true)
      account.crm_pipeline_inboxes.where.not(pipeline: comercial).update_all(auto_create_card: false) # rubocop:disable Rails/SkipsModelValidations
      message = incoming('Bati o carro ontem, como abro o sinistro?')
      chegada = Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: message).perform
      expect(chegada.pipeline_id).to eq(comercial.id)
      pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

      decision = identify(message)

      expect(decision).to have_attributes(action: 'rename', state: 'applied', card_id: chegada.id)
      expect(chegada.reload).to have_attributes(pipeline_id: pos_venda.id, stage_id: etapa(pos_venda, 'Sinistros').id)
      expect(entradas_de_etapa).to include(from_stage_id: nil, to_stage_id: etapa(pos_venda, 'Sinistros').id,
                                           automation_context: { source: 'crm_subjects' })
    end

    it 'C36: o card da chegada mudou enquanto a IA pensava: nasce outro card, já na coluna escolhida' do
      comercial
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true)
      account.crm_pipeline_inboxes.find_by(pipeline: comercial).update!(auto_create_card: true)
      account.crm_pipeline_inboxes.where.not(pipeline: comercial).update_all(auto_create_card: false) # rubocop:disable Rails/SkipsModelValidations
      message = incoming('Bati o carro ontem')
      chegada = Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: message).perform
      allow(Crm::Subjects::CardDaChegada).to receive(:de).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap do
          Crm::ActivityLogger.new(card: chegada, actor: admin, event_type: 'update', payload: { owner_id: admin.id }).perform
        end
      end
      pedido(pos_venda, 'Sinistro do Onix', chave(pos_venda, 'Sinistros'))

      decision = identify(message)

      novo = account.crm_cards.where(pipeline: pos_venda).sole
      expect(decision).to have_attributes(action: 'create', state: 'applied', card_id: novo.id)
      expect(novo.stage_id).to eq(etapa(pos_venda, 'Sinistros').id)
      expect(chegada.reload.pipeline_id).to eq(comercial.id)
    end

    it 'vários assuntos: dois pedidos novos no mesmo funil nascem em colunas diferentes' do
      stub_jev(Crm::Subjects::Question::VARIOS)
      stub_review(["novo_#{pos_venda.id}", 'Sinistro do Onix', chave(pos_venda, 'Sinistros')],
                  ["novo_#{pos_venda.id}", 'Boleto atrasado', chave(pos_venda, 'Financeiro')])

      identify(incoming('Bati o carro ontem, e o meu boleto veio errado'))

      cards = account.crm_cards.where(pipeline: pos_venda).index_by(&:title)
      expect(cards.transform_values(&:stage_id)).to eq('Sinistro do Onix' => etapa(pos_venda, 'Sinistros').id,
                                                       'Boleto atrasado' => etapa(pos_venda, 'Financeiro').id)
      schema = chamada_ao_modelo[:schema][:schema]
      expect(schema[:properties][:assuntos][:items][:required]).to include('etapa')
    end
  end
end
