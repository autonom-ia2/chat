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
  let(:tela) { [{ name: 'Novo Lead', description: 'Primeiro contato.' }, { name: 'Proposta', description: 'Valor enviado ao cliente.' }] }
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

  def card_escolhido_por_pessoa(texto, quando: 1.hour.ago, ator: 'user')
    conversation = conversa_com(texto, quando - 1.minute)
    card = account.crm_cards.create!(pipeline: pipeline, stage: proposta, title: texto, conversation_id: conversation.id)
    Crm::Activity.create!(account: account, card: card, actor_type: ator, actor_id: admin.id, event_type: 'move', created_at: quando,
                          payload: { from_pipeline_id: pipeline.id, to_pipeline_id: pipeline.id, from_stage_id: novo.id, to_stage_id: proposta.id })
    card
  end

  # O classificador falso: com a frase nova vai à Proposta; com a salva fica onde estava. Custo de US$ 0,01 por chamada.
  def classificador_falso(chamadas = [])
    allow(Crm::Ai::StageClassifier).to receive(:new) do |args|
      chamadas << args
      criterio = Crm::Ai::Config.stage_ai_criteria(args[:stages].last)
      escolha = criterio == 'Valor enviado ao cliente.' ? proposta.id : args[:context][:current_stage][:id]
      resposta = { suggested_stage_id: escolha, model_used: 'gpt-6-luna', usage: { 'input_tokens' => 100_000 } }
      instance_double(Crm::Ai::StageClassifier, perform: resposta)
    end
    chamadas
  end

  it 'conta os acertos com a frase atual e a nova, vendo o card como estava na decisão, sem mexer em nada' do
    card = card_escolhido_por_pessoa('Me manda o valor')
    chamadas = classificador_falso

    resultado = nil
    expect { resultado = described_class.new(pipeline: pipeline, stages: tela).perform }
      .not_to(change { [card.reload.stage_id, card.metadata, Crm::AiStageSuggestion.count, Crm::Activity.count] })

    expect(resultado).to include(total: 1, acertos_atual: 0, acertos_nova: 1, custo_usd: 0.02, parou_no_teto: false)
    expect(resultado[:casos]).to eq([{ card_id: card.id, certa: 'Proposta', atual: 'Novo Lead', nova: 'Proposta' }])
    expect(chamadas.size).to eq(2)
    expect(chamadas.first[:context][:current_stage]).to eq(id: novo.id, name: 'Novo Lead')
    expect(chamadas.first[:attribute_schema]).to eq(contact: [], conversation: [], card: [])
  end

  it 'roda uma vez só por card quando a tela não mudou nenhuma frase' do
    card_escolhido_por_pessoa('Me manda o valor')
    chamadas = classificador_falso
    iguais = [{ name: 'Novo Lead', description: '' }, { name: 'Proposta', description: 'Cliente falou de preço.' }]

    resultado = described_class.new(pipeline: pipeline, stages: iguais).perform

    expect(chamadas.size).to eq(1)
    expect(resultado).to include(acertos_atual: 0, acertos_nova: 0)
  end

  it 'para no teto de custo e diz que parou' do
    stub_const("#{described_class}::TETO_USD", 0.02)
    3.times { |index| card_escolhido_por_pessoa("Pedido #{index}", quando: (index + 1).hours.ago) }
    classificador_falso

    resultado = described_class.new(pipeline: pipeline, stages: tela).perform

    expect(resultado).to include(total: 1, parou_no_teto: true)
  end

  it 'ignora o card que saiu da etapa escolhida pela pessoa e o movimento que não foi de pessoa' do
    saiu = card_escolhido_por_pessoa('Me manda o valor')
    saiu.update!(stage: novo)
    card_escolhido_por_pessoa('Outro pedido', ator: 'system')
    chamadas = classificador_falso

    expect(described_class.new(pipeline: pipeline, stages: tela).perform).to include(total: 0)
    expect(chamadas).to be_empty
  end

  it 'recusa quando a tela tem outro número de etapas' do
    expect(described_class.new(pipeline: pipeline, stages: tela.first(1)).perform).to eq(error: 'stages_changed')
  end
end
