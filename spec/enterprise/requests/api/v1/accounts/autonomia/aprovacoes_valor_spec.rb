require 'rails_helper'

# #2931 (decisão 9 do épico #2414): no pedido de aprovação, o valor de venda (`card.valor`) só aparece para quem vê
# valores (Crm::ValorDeVenda: `sales_value_view`). Para os outros, a pergunta diz "valor oculto" e o card ao lado vem
# sem `value_cents`. O mesmo pedido, para duas pessoas do time que aprova, uma com a chave e outra sem. Fica em
# spec/enterprise: a função personalizada é EE.
RSpec.describe 'Pedidos de aprovação: o valor de venda pela permissão de quem olha (#2931)', :automacao_motor, type: :request do
  include ActiveJob::TestHelper

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:sem_chave) { pessoa_com(base) }
  let(:com_chave) { pessoa_com(base + %w[sales_value_view]) }
  let(:time) { create(:team, account: account) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:inbox) { create_crm_inbox(account: account, members: [sem_chave, com_chave]) }
  let(:contato) { account.contacts.create!(name: 'Cliente', phone_number: '+5511955556666') }
  let(:card) do
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, inbox: inbox, contact: contato, owner: admin, title: 'Carro',
                              value_cents: 500_000, currency: 'BRL')
  end
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/aprovacoes" }

  let(:passo) do
    { 'id' => 'aprova', 'tipo' => 'pedir_aprovacao', 'quem' => { 'de' => 'time', 'id' => time.id },
      'pergunta' => ['Posso dar desconto no card de ', { '$valor' => 'card.valor' }, '?'], 'prazo' => { 'valor' => 1, 'unidade' => 'dias' } }
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_passos_novos')
    [sem_chave, com_chave].each { |pessoa| create(:team_member, team: time, user: pessoa) }
  end

  def base = %w[crm_view crm_manage_cards crm_view_reports contact_view]

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def pedir
    definicao = automacao_ligada(account, admin, [passo])
    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, card) }
    Autonomia::Automacao::Registro.find_by!(execucao: execucao, motivo: 'esperando_resposta')
  end

  def visto_por(pessoa, pedido)
    get "#{base_url}/#{pedido.id}", headers: pessoa.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it 'sem sales_value_view: "valor oculto" na pergunta e o card sem value_cents, na lista e no pedido', :aggregate_failures do
    pedido = pedir
    expect(pedido.dados['para']).to contain_exactly(sem_chave.id, com_chave.id)

    lido = visto_por(sem_chave, pedido)
    expect(lido['pergunta']).to eq("Posso dar desconto no card de #{I18n.t('autonomia.automacao.pedido.valor_oculto', locale: :pt_BR)}?")
    expect(lido['card']).to include('id' => card.id, 'title' => 'Carro')
    expect(lido['card']).not_to have_key('value_cents')
    expect(lido.to_json).not_to include('5000')

    get base_url, headers: sem_chave.create_new_auth_token, as: :json
    item = response.parsed_body['pedidos'].sole
    expect(item['pergunta']).to eq(lido['pergunta'])
    expect(item['card']).not_to have_key('value_cents')
  end

  it 'com sales_value_view: o valor na pergunta e no card', :aggregate_failures do
    pedido = pedir

    lido = visto_por(com_chave, pedido)
    expect(lido['pergunta']).not_to include(I18n.t('autonomia.automacao.pedido.valor_oculto', locale: :pt_BR))
    expect(lido['pergunta']).to include('5000')
    expect(lido['card']).to include('value_cents' => 500_000)
  end
end
