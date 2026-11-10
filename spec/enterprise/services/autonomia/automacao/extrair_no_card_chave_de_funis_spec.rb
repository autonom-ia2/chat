require 'rails_helper'

# G70 (#2880, decisão 20): o extrair que grava num campo do card da conversa conta como ler o card (CardDaConversa.le?) e
# pede a chave de funis de quem ligou (crm_manage_pipelines ou crm_admin). Sem ela, a automação para no começo e o card
# não recebe nada; a mesma pessoa, gravando na conversa, roda. Fica em spec/enterprise: a função personalizada é EE.
RSpec.describe 'Automação livre · extrair no card sem a chave de funis (G70)', :aggregate_failures, :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  # O card na caixa da conversa: quem atende a caixa vê os cards dela (Crm::Cards::VisibleScopeQuery).
  let!(:card) do
    Crm::Cards::Creator.new(account: account, user: admin, params: { pipeline_id: funil.first.id, stage_id: funil.last.id,
                                                                     contact_id: conversa.contact_id, conversation_id: conversa.id,
                                                                     inbox_id: conversa.inbox_id, title: 'Pedido' }).perform
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia', 'automacao_gatilhos')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    %w[card_attribute conversation_attribute].each do |modelo|
      create(:custom_attribute_definition, account: account, attribute_key: 'peca', attribute_model: modelo, attribute_display_type: 'text')
    end
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Quero uma peça')
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'r1', output_text: { 'peca' => 'casaco-9182' }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }.to_json
    )
  end

  after { Current.reset }

  def base = %w[automation_manage crm_view crm_manage_cards conversation_manage]

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: conversa.inbox)
    user
  end

  def extrair(destino)
    { 'id' => 'p1', 'tipo' => 'extrair', 'le' => %w[mensagens_recentes],
      'campos' => [{ 'chave' => 'peca', 'descricao' => 'a peça', 'destino' => destino }] }
  end

  def rodar(definicao)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'mensagem.criada').call
    end
    definicao.execucoes.order(:id).last
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  def ligada(por, destino) = automacao_ligada(account, por, [extrair(destino)], gatilho: { 'tipo' => 'mensagem.criada' })

  it 'sem a chave: para no começo e o card não recebe nada; a mesma pessoa grava na conversa' do
    pessoa = pessoa_com(base)

    parada = rodar(ligada(pessoa, 'card.atributos.peca'))
    rodou = rodar(ligada(pessoa, 'conversa.atributos.peca'))

    expect(registros(parada)).to eq([%w[inicio pulado sem_permissao_funil]])
    expect(card.reload.custom_attributes).not_to have_key('peca')
    expect(registros(rodou)).to eq([['p1', 'ok', nil]])
    expect(conversa.reload.custom_attributes).to include('peca' => 'casaco-9182')
  end

  it 'com a chave de funis, grava no card da conversa' do
    pessoa = pessoa_com(base + %w[crm_manage_pipelines])

    execucao = rodar(ligada(pessoa, 'card.atributos.peca'))

    expect(registros(execucao)).to eq([['p1', 'ok', nil]])
    expect(card.reload.custom_attributes).to include('peca' => 'casaco-9182')
  end
end
