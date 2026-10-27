require 'rails_helper'

# #2277: the planner on the account's own key only; a question waits for the person, a plan shows count and cost.
RSpec.describe ConversationAudience::PlanJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:search) { ConversationAudienceSearch.create!(account: account, user: admin, request: 'quem cota muito', period: '30d') }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:plan) do
    { entendi: 'Quem pediu cotação 3 vezes ou mais', pergunta: nil, regra: 'Pediu cotação 3+ vezes', certeza: 'a',
      provavel: 'b', fora: 'c', nome_sugerido: 'Cotam muito' }
  end

  def own_key!
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
  end

  before do
    allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: BigDecimal('5.4'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(client).to receive(:create).and_return(text: plan.to_json, usage: { 'input_tokens' => 1000, 'output_tokens' => 200 })
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Quanto fica?')
  end

  it 'fails with no_key and never calls the AI when the account has no key of its own, even with the installation key' do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao')

    described_class.perform_now(search.id)

    expect(search.reload).to have_attributes(status: 'failed', error: 'no_key')
    expect(client).not_to have_received(:create)
  end

  it 'plans on the account key: batches, estimate, twice the estimate as ceiling and the planner cost spent' do
    own_key!

    described_class.perform_now(search.id)

    search.reload
    expect(search.status).to eq('planned')
    expect(search.plan).to include('understood' => 'Quem pediu cotação 3 vezes ou mais', 'name' => 'Cotam muito', 'question' => nil,
                                   'minutes' => 1)
    expect(search.conversations_total).to eq(1)
    expect(search.batches.count).to eq(1)
    expect(search.spent_usd).to be_positive
    expect(search.ceiling_usd).to eq(search.spent_usd + (search.estimate_usd * 2))
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(credential: include(api_key: 'chave-da-conta', source: :hook)))
  end

  it 'stops at the question, without batches, until the person answers' do
    own_key!
    allow(client).to receive(:create)
      .and_return(text: plan.merge(pergunta: { texto: 'Quantas vezes?', opcoes: ['2 ou mais', '3 ou mais'] }).to_json, usage: {})

    described_class.perform_now(search.id)

    expect(search.reload.status).to eq('question')
    expect(search.plan['question']).to eq('text' => 'Quantas vezes?', 'options' => ['2 ou mais', '3 ou mais'])
    expect(search.batches).to be_empty
  end

  it 'goes on after the answer even if the model would ask again' do
    own_key!
    search.update!(answer: '3 ou mais')
    allow(client).to receive(:create)
      .and_return(text: plan.merge(pergunta: { texto: 'De novo?', opcoes: %w[a b] }).to_json, usage: {})

    described_class.perform_now(search.id)

    expect(search.reload.status).to eq('planned')
    expect(client).to have_received(:create).with(hash_including(input: include('Resposta da pessoa à sua pergunta: "3 ou mais"')))
  end

  it 'fails with no_access and never calls the AI when the person left the account before the plan ran' do
    own_key!
    AccountUser.find_by(account: account, user: admin).destroy!

    described_class.perform_now(search.id)

    expect(search.reload).to have_attributes(status: 'failed', error: 'no_access')
    expect(client).not_to have_received(:create)
  end

  it 'fails with plan_error when the AI does not answer' do
    own_key!
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('down', status: 500))

    described_class.perform_now(search.id)

    expect(search.reload).to have_attributes(status: 'failed', error: 'plan_error')
  end
end
