require 'rails_helper'

# #1920: o raio-x roda o classificador de etapa com as frases salvas e com as da tela nos cards em que uma pessoa
# escolheu a etapa, sem mover nem gravar nada no card.
RSpec.describe Crm::Ai::RaioXDasFrases do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:novo) { pipeline_and_stage.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:tela) do
    [{ id: novo.id, name: 'Novo Lead', description: 'Primeiro contato.' },
     { id: proposta.id, name: 'Proposta', description: 'Valor enviado ao cliente.' }]
  end
  let(:credencial) { { api_key: 'synthetic-test-key', source: :hook } }

  before do
    proposta.update!(metadata: { 'ai_criteria' => 'Cliente falou de preço.' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
  end

  def conversa_com(texto, quando)
    contact = create(:contact, account: account)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :incoming, content: texto,
                                  sender: contact, created_at: quando)
    conversation
  end

  def card_escolhido_por_pessoa(texto, quando: 1.hour.ago, ator: 'user', lado: :prova)
    conversation = conversa_com(texto, quando - 1.minute)
    card = create_crm_card_do_lado(account: account, lado: lado, pipeline: pipeline, stage: proposta, title: texto,
                                   conversation_id: conversation.id)
    Crm::Activity.create!(account: account, card: card, actor_type: ator, actor_id: admin.id, event_type: 'move', created_at: quando,
                          payload: { from_pipeline_id: pipeline.id, to_pipeline_id: pipeline.id, from_stage_id: novo.id, to_stage_id: proposta.id })
    card
  end

  # O classificador falso: com a frase nova da Proposta vai à Proposta; com a salva fica onde estava. US$ 0,01 por chamada.
  def classificador_falso(chamadas = [])
    allow(Crm::Ai::StageClassifier).to receive(:new) do |args|
      chamadas << args
      criterio = Crm::Ai::Config.stage_ai_criteria(args[:stages].find { |etapa| etapa.id == proposta.id })
      escolha = criterio == 'Valor enviado ao cliente.' ? proposta.id : args[:context][:current_stage][:id]
      resposta = { suggested_stage_id: escolha, model_used: 'gpt-6-luna', usage: { 'input_tokens' => 100_000 } }
      instance_double(Crm::Ai::StageClassifier, perform: resposta)
    end
    chamadas
  end

  it 'conta os acertos com a frase atual e a nova, vendo o card como estava na decisão, sem mexer em nada' do
    card = card_escolhido_por_pessoa('Me manda o valor', quando: 3.days.ago)
    # Gravado depois da decisão: não pode chegar ao classificador.
    card.update!(metadata: { 'ai' => { 'summary' => 'Cliente fechou.' } })
    chamadas = classificador_falso

    resultado = nil
    expect { resultado = described_class.new(pipeline: pipeline, stages: tela).perform }
      .not_to(change { [card.reload.stage_id, card.metadata, Crm::AiStageSuggestion.count, Crm::Activity.count] })

    expect(resultado).to include(total: 1, acertos_atual: 0, acertos_nova: 1, custo_usd: 0.02, parou_no_teto: false)
    expect(resultado[:casos]).to eq([{ card_id: card.id, certa: 'Proposta', atual: 'Novo Lead', nova: 'Proposta' }])
    expect(chamadas.size).to eq(2)
    contexto = chamadas.first[:context]
    expect(contexto).to include(summary: '', conversation_state: {}, other_subjects: [], current_stage: { id: novo.id, name: 'Novo Lead' })
    expect(contexto[:temporal][:now_local]).to eq(3.days.ago.in_time_zone(contexto[:temporal][:timezone]).strftime('%Y-%m-%dT%H:%M'))
    expect(chamadas.first[:attribute_schema]).to eq(contact: [], conversation: [], card: [])
  end

  it 'casa as etapas da tela pelo id, mesmo com a ordem trocada' do
    card_escolhido_por_pessoa('Me manda o valor')
    chamadas = classificador_falso

    resultado = described_class.new(pipeline: pipeline, stages: tela.reverse).perform

    expect(resultado).to include(total: 1, acertos_nova: 1)
    expect(chamadas.last[:stages].map(&:id)).to eq([proposta.id, novo.id])
    expect(chamadas.last[:stages].first.name).to eq('Proposta')
  end

  it 'roda uma vez só por card quando a tela não mudou nenhuma frase' do
    card_escolhido_por_pessoa('Me manda o valor')
    chamadas = classificador_falso
    iguais = [{ id: novo.id, name: 'Novo Lead', description: '' }, { id: proposta.id, name: 'Proposta', description: 'Cliente falou de preço.' }]

    resultado = described_class.new(pipeline: pipeline, stages: iguais).perform

    expect(chamadas.size).to eq(1)
    expect(resultado).to include(acertos_atual: 0, acertos_nova: 0)
  end

  it 'confere o teto antes de cada chamada e deixa fora do placar o caso que não coube inteiro' do
    stub_const("#{described_class}::TETO_USD", 0.015)
    2.times { |index| card_escolhido_por_pessoa("Pedido #{index}", quando: (index + 1).hours.ago) }
    chamadas = classificador_falso

    resultado = described_class.new(pipeline: pipeline, stages: tela).perform

    expect(chamadas.size).to eq(1)
    expect(resultado).to include(total: 0, custo_usd: 0.01, parou_no_teto: true)
  end

  it 'para no teto de custo e diz que parou' do
    stub_const("#{described_class}::TETO_USD", 0.02)
    3.times { |index| card_escolhido_por_pessoa("Pedido #{index}", quando: (index + 1).hours.ago) }
    classificador_falso

    expect(described_class.new(pipeline: pipeline, stages: tela).perform).to include(total: 1, parou_no_teto: true)
  end

  it 'ignora card que saiu da escolha, movimento que não foi de pessoa, automação, card de evidência e card escondido' do
    saiu = card_escolhido_por_pessoa('Me manda o valor')
    saiu.update!(stage: novo)
    card_escolhido_por_pessoa('Outro pedido', ator: 'system')
    automacao = card_escolhido_por_pessoa('Automação')
    Crm::Activity.where(card: automacao).find_each { |movimento| movimento.update!(payload: movimento.payload.merge('automation_depth' => 1)) }
    card_escolhido_por_pessoa('Ensina', lado: :ensina)
    escondido = card_escolhido_por_pessoa('Escondido')
    chamadas = classificador_falso

    resultado = described_class.new(pipeline: pipeline, stages: tela, cards: account.crm_cards.where.not(id: escondido.id)).perform

    expect(resultado).to include(total: 0)
    expect(chamadas).to be_empty
  end

  it 'recusa quando a tela não traz exatamente as etapas salvas pelo id' do
    expect(described_class.new(pipeline: pipeline, stages: tela.first(1)).perform).to eq(error: 'stages_changed')
    sem_id = tela.map { |etapa| etapa.except(:id) }
    expect(described_class.new(pipeline: pipeline, stages: sem_id).perform).to eq(error: 'stages_changed')
    repetida = [tela.first, tela.first]
    expect(described_class.new(pipeline: pipeline, stages: repetida).perform).to eq(error: 'stages_changed')
  end

  it 'dá uma vaga por funil a cada intervalo' do
    Redis::Alfred.delete("#{described_class::VAGA}funil:#{pipeline.id}")

    expect(described_class.vaga?(pipeline)).to be(true)
    expect(described_class.vaga?(pipeline)).to be(false)
  ensure
    Redis::Alfred.delete("#{described_class::VAGA}funil:#{pipeline.id}")
  end
end
