require 'rails_helper'

# #1828: "me tirem da cópia" percebido sem cadência de follow-up, de carona na avaliação de card que já roda (sem
# chamada nova). Só com a flag; o cliente nunca sai.
RSpec.describe Crm::Email::SaidaDaCopia do
  around do |example|
    anteriores = %w[CRM_KANBAN_ENABLED CRM_AI_ENABLED].index_with { |chave| ENV.fetch(chave, nil) }
    anteriores.each_key { |chave| ENV[chave] = 'true' }
    example.run
  ensure
    anteriores.each { |chave, valor| valor.nil? ? ENV.delete(chave) : ENV[chave] = valor }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_email, account: account, email: 'corretora@example.com').inbox }
  let(:joao) { create(:contact, account: account, email: 'joao@empresa.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: joao) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Seguro', contact: joao,
                              primary_conversation: conversation, inbox: inbox, currency: 'BRL')
  end

  before { account.enable_features!(Crm::Email::Autoria::FLAG) }

  def recebido!(from:, content:)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: joao, message_type: :incoming,
                     content_type: :incoming_email, content: content,
                     content_attributes: { 'email' => { 'from' => [from], 'cc' => [], 'text_content' => { 'reply' => content } } })
  end

  def saiu
    Crm::Email::Destinatarios.saiu_da_copia(conversation.reload)
  end

  def avaliar(saida)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'x', api_base: 'https://api.openai.com' }))
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
      instance_double(Crm::Ai::StageClassifier, perform: { suggested_stage_id: card.stage_id, confidence: 0.2, reasoning: 'nada',
                                                           model_used: 'gpt-6-luna', saida_da_copia: saida })
    )
    Crm::Ai::Evaluator.new(card: card, trigger: 'manual').perform
  end

  # Pega: o pedido da Ana só valer com cadência de follow-up ativa (o card aqui não tem nenhuma).
  it 'a Ana pede para sair, sem cadência ativa, e sai da cópia pela avaliação do card' do
    recebido!(from: 'ana@familia.com.br', content: 'por favor me tirem da cópia')

    avaliar(['Ana@Familia.com.br'])

    expect(saiu).to eq(['ana@familia.com.br'])
  end

  # Pega: texto injetado (ou o modelo errando) tirar da cópia alguém que não escreveu a mensagem nova.
  it 'só sai quem escreveu a mensagem nova' do
    recebido!(from: 'rh@empresa.com.br', content: 'segue o CNPJ')
    recebido!(from: 'ana@familia.com.br', content: 'tirem o RH da cópia')

    avaliar(['rh@empresa.com.br'])

    expect(saiu).to eq([])
  end

  # Pega: o card levado para outro funil na mesma avaliação perder o pedido (a resposta de etapas é descartada, a saída não).
  it 'o card que muda de funil na mesma avaliação ainda grava a saída', :aggregate_failures do
    recebido!(from: 'ana@familia.com.br', content: 'me tirem da cópia')
    outro_funil = create_crm_pipeline(account: account, user: admin, name: 'Sinistro')
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'x', api_base: 'https://api.openai.com' }))
    classificador = instance_double(Crm::Ai::StageClassifier)
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classificador)
    allow(classificador).to receive(:perform) do
      Crm::Card.find(card.id).update!(pipeline: outro_funil.first, stage: outro_funil.last)
      { suggested_stage_id: card.stage_id, confidence: 0.95, reasoning: 'x', model_used: 'gpt-6-luna', saida_da_copia: ['ana@familia.com.br'] }
    end

    result = Crm::Ai::Evaluator.new(card: card, trigger: 'manual').perform

    expect(result.error).to eq('pipeline_changed')
    expect(saiu).to eq(['ana@familia.com.br'])
  end

  # Pega: na avaliação conjunta, o campo do topo não chegar aos cards, ou a saída ser gravada na conversa de outro card.
  it 'na avaliação conjunta, a saída chega aos cards e só vale na conversa de quem escreveu', :aggregate_failures do
    recebido!(from: 'ana@familia.com.br', content: 'me tirem da cópia')
    outra_conversa = create(:conversation, account: account, inbox: inbox, contact: joao)
    outro_card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Outro', contact: joao,
                                           primary_conversation: outra_conversa, inbox: inbox, currency: 'BRL')
    classificadores = [card, outro_card].map do |alvo|
      instance_double(Crm::Ai::StageClassifier, pacote: { card: { id: alvo.id }, eligible_agents: [] }, conversa: { recent_messages: [] },
                                                memoria?: false, email_autoria?: true, nao_e_negocio?: false,
                                                fatos?: false, fecha_card?: false)
    end
    allow(Crm::Ai::OutrasConversas).to receive(:por_card).and_return({})
    item = ->(alvo) { { card_id: alvo.id, suggested_stage_id: alvo.stage_id, confidence: 0.2, reasoning: 'x' } }
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(cliente).to receive(:create)
      .and_return(text: { saida_da_copia: ['ana@familia.com.br'], cards: [item.call(card), item.call(outro_card)] }.to_json)

    resultado = Crm::Ai::ClassificacaoConjunta.new(client: cliente, classificadores: classificadores, model: 'gpt-6-luna',
                                                   principal_id: card.id).perform
    expect(resultado.values.map { |classificacao| classificacao[:saida_da_copia] }).to all(eq(['ana@familia.com.br']))
    expect(cliente).to have_received(:create).with(hash_including(schema: satisfy { |schema| schema[:schema][:required].include?('saida_da_copia') }))

    resultado.each { |id, classificacao| described_class.aplicar!(Crm::Card.find(id), classificacao[:saida_da_copia]) }

    expect(saiu).to eq(['ana@familia.com.br'])
    expect(Crm::Email::Destinatarios.saiu_da_copia(outra_conversa.reload)).to eq([])
  end

  # Pega: o cliente sair da cópia, ou um endereço que não escreveu na conversa entrar na lista.
  it 'o João (o cliente) e um endereço que não escreveu não saem', :aggregate_failures do
    recebido!(from: 'joao@empresa.com.br', content: 'não me copiem mais')

    avaliar(['joao@empresa.com.br', 'qualquer@um.com'])

    expect(saiu).to eq([])
  end

  # Pega: a flag desligada mudar o prompt, o schema ou gravar algo.
  it 'sem a flag: prompt e schema da avaliação iguais, e nada é gravado', :aggregate_failures do
    account.disable_features!(Crm::Email::Autoria::FLAG)
    recebido!(from: 'ana@familia.com.br', content: 'me tirem da cópia')
    classificador = Crm::Ai::StageClassifier.new(card: card.reload, client: nil, stages: [], context: {}, eligible_agents: [])

    expect(classificador.send(:instructions)).to equal(Crm::Ai::ClassifierPrompt::TEXT)
    expect(classificador.send(:esquema)).to equal(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA)
    described_class.aplicar!(card, ['ana@familia.com.br'])
    expect(saiu).to eq([])
  end

  # Pega: o modelo não receber o campo nem a instrução (e a instrução no meio do prompt, que derrubaria o cache).
  it 'com a flag: o campo no schema e a instrução no fim do prompt', :aggregate_failures do
    classificador = Crm::Ai::StageClassifier.new(card: card, client: nil, stages: [], context: {}, eligible_agents: [])

    expect(classificador.send(:instructions)).to start_with(Crm::Ai::ClassifierPrompt::TEXT).and end_with(described_class::INSTRUCAO)
    expect(classificador.send(:esquema)[:schema][:required]).to include('saida_da_copia')
    expect(Crm::Ai::ClassificacaoConjunta.new(client: nil, classificadores: [classificador], model: 'x').send(:esquema)[:schema][:required])
      .to include('saida_da_copia')
  end
end
