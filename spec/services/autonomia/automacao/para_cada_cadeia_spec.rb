require 'rails_helper'

# G24 (#2771): duas automações encadeadas, em que a primeira cria N cards e a segunda roda em cada um. Cada item do
# "para cada item" abre o card numa raiz própria da cadeia (Cadeia.em_raiz_nova): na raiz da rodada, a segunda automação
# rodaria só no 1º card e seria recusada como `:repetida` nos outros. O laço continua recusado.
RSpec.describe 'Automação livre: o "para cada item" encadeia a automação de card criado', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Inclusões') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:rh) { create(:contact, account: account, name: 'Rita do RH', phone_number: '+5511900000001') }
  let(:conversa) { create(:conversation, account: account, contact: rh, status: :open) }
  let(:execucoes) { Autonomia::Automacao::Execucao }
  let(:cadeia) { Autonomia::Automacao::Cadeia }
  let(:itens) { [{ 'nome' => 'João Lima' }, { 'nome' => 'Maria Souza' }, { 'nome' => 'Pedro Alves' }] }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia', 'automacao_gatilhos')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Inclusões: João, Maria e Pedro')
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'resp_1', output_text: { 'itens' => itens }.to_json, usage: { input_tokens: 900, output_tokens: 150 } }.to_json
    )
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job de cada vez, na ordem da fila: o job enfileirado dentro de outro só roda depois dele.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    80.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 80 jobs'
  end

  def para_cada
    { 'id' => 'lista', 'tipo' => 'para_cada', 'le' => %w[mensagens_recentes], 'descricao' => 'Cada funcionário novo da lista',
      'campos' => [{ 'chave' => 'nome', 'descricao' => 'Nome completo' }], 'etapa_id' => etapa.id, 'maximo' => 20 }
  end

  def de_card_criado(passos) = automacao_ligada(account, admin, passos, gatilho: { 'tipo' => 'card.criado', 'funil_id' => funil.id })

  it 'a automação de card criado roda em cada um dos 3 cards que o "para cada item" abriu', :aggregate_failures do
    lista = automacao_ligada(account, admin, [para_cada])
    em_cada_card = de_card_criado([{ 'id' => 'fim', 'tipo' => 'parar' }])

    comecar(lista, conversa)
    drenar

    cards = funil.cards.order(:id).to_a
    expect(cards.size).to eq(3)
    expect(execucoes.where(automacao: em_cada_card).map(&:alvo)).to match_array(cards)
    # A cadeia de cada uma começa pela automação da lista: o laço e a profundidade continuam contando.
    expect(execucoes.where(automacao: em_cada_card).pluck(:cadeia).uniq).to eq([["automacao:#{lista.id}", "automacao:#{em_cada_card.id}"]])
    expect(execucoes.where(automacao: em_cada_card).pluck(:estado).uniq).to eq(['concluida'])
  end

  it 'a automação que se dispara com os próprios cards continua recusada (laço)', :aggregate_failures do
    allow(cadeia).to receive(:registrar_recusa).and_call_original
    se_dispara = de_card_criado([para_cada])
    primeiro = Crm::Cards::Creator.new(account: account, user: admin, conversation: conversa,
                                       params: { pipeline_id: funil.id, stage_id: etapa.id }).perform

    drenar

    expect(funil.cards.count).to eq(4)
    expect(execucoes.where(automacao: se_dispara).map(&:alvo)).to eq([primeiro])
    expect(cadeia).to have_received(:registrar_recusa).with(having_attributes(motivo: :auto_disparo), any_args).exactly(3).times
  end

  it 'sem a flag da fundação, os itens rodam sem cadeia, como antes da F1' do
    expect(cadeia.em_raiz_nova { cadeia.ativa? }).to be(false)
  end
end
