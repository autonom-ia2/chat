require 'rails_helper'

# Funções personalizadas, lote 13 (#2075): `sales_value_view` abre os valores de venda em R$ do CRM. Sem ela, a função
# vê as contagens, o valor dos cards de que é dona e trabalha normalmente; administrador e agente sem função continuam
# vendo tudo. Fica em spec/enterprise: a metade de função personalizada é EE.
RSpec.describe 'Valores de venda com sales_value_view (#2075)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:sem_chave) { pessoa_com(base) }
  let(:com_chave) { pessoa_com(base + %w[sales_value_view]) }
  let(:crm_admin) { pessoa_com(%w[crm_admin contact_view]) }
  let(:plain_agent) { create_crm_agent(account: account).first }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:inbox) { create_crm_inbox(account: account, members: [sem_chave, com_chave, crm_admin, plain_agent]) }
  let(:contato) { account.contacts.create!(name: 'Cliente', phone_number: '+5511955556666') }
  let!(:alheio) { criar_card('Alheio', 500_000, admin) }

  before { criar_card('Próprio', 120_000, sem_chave) }

  def base = %w[crm_view crm_manage_cards crm_view_reports contact_view]
  def crm = "/api/v1/accounts/#{account.id}/crm"

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def criar_card(titulo, cents, dono)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contato, owner: dono, title: titulo,
                              value_cents: cents, currency: 'BRL')
  end

  def ler(path, user, params = {})
    get "#{crm}/#{path}", params: params, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload']
  end

  def valores_da_lista(user, params = {})
    ler('cards', user, { pipeline_id: pipeline.id }.merge(params)).to_h { |card| [card['title'], card['value_cents']] }
  end

  it 'lista: sem a chave, o card alheio vem sem valor e o próprio com valor' do
    cards = ler('cards', sem_chave, pipeline_id: pipeline.id).index_by { |card| card['title'] }

    expect(cards['Alheio']).to include('value_cents' => nil, 'value_hidden' => true)
    expect(cards['Próprio']).to include('value_cents' => 120_000)
    expect(cards['Próprio']).not_to have_key('value_hidden')
  end

  it 'lista: com a chave, administrador e agente sem função veem todos os valores' do
    [com_chave, admin, plain_agent].each do |user|
      expect(valores_da_lista(user)).to eq('Alheio' => 500_000, 'Próprio' => 120_000)
    end
  end

  # Chave protegida: crm_admin, que quem cuida de Pessoas repassa, não abre os valores.
  it 'lista: crm_admin sem a chave não vê o valor' do
    expect(valores_da_lista(crm_admin)).to eq('Alheio' => nil, 'Próprio' => nil)
  end

  it 'editar sem ver o valor não muda o valor: a gaveta manda value_cents em toda edição' do
    patch "#{crm}/cards/#{alheio.id}", params: { card: { title: 'Novo título', value_cents: 0, currency: 'USD' } },
                                       headers: auth_headers(sem_chave), as: :json

    expect(response).to have_http_status(:ok)
    expect(alheio.reload).to have_attributes(title: 'Novo título', value_cents: 500_000, currency: 'BRL')
    expect(alheio.metadata.dig('ai', 'value_source')).to be_nil
  end

  it 'editar o próprio card muda o valor' do
    proprio = account.crm_cards.find_by!(title: 'Próprio')
    patch "#{crm}/cards/#{proprio.id}", params: { card: { value_cents: 130_000 } }, headers: auth_headers(sem_chave), as: :json

    expect(response).to have_http_status(:ok)
    expect(proprio.reload.value_cents).to eq(130_000)
  end

  it 'atualizar pelo external_id sem ver o valor não muda o valor' do
    alheio.update!(external_id: 'erp-1')
    post "#{crm}/cards", params: { card: { external_id: 'erp-1', title: 'Do ERP', value_cents: 1 } },
                         headers: auth_headers(sem_chave), as: :json

    expect(alheio.reload).to have_attributes(title: 'Do ERP', value_cents: 500_000)
  end

  it 'planilha: sem a chave, a coluna Valor vem vazia no card alheio e cheia no próprio' do
    exportador = pessoa_com(base + %w[crm_export])
    inbox.add_members([exportador.id])
    account.crm_cards.find_by!(title: 'Próprio').update!(owner: exportador)
    get "#{crm}/cards/export", params: { pipeline_id: pipeline.id }, headers: auth_headers(exportador)

    expect(response).to have_http_status(:ok)
    planilha = Roo::Excelx.new(StringIO.new(response.body)).sheet(0)
    coluna = Crm::Cards::XlsxExport::COLUMNS.index(:value) + 1
    linhas = ((Crm::Cards::XlsxExport::HEADER_ROW + 1)..planilha.last_row).to_h { |linha| [planilha.cell(linha, 1), planilha.cell(linha, coluna)] }
    expect(linhas).to eq('Alheio' => nil, 'Próprio' => 1200.0)
  end

  def cards_do_quadro(user)
    ler('kanban', user, pipeline_id: pipeline.id)['stages'].flat_map { |coluna| coluna['cards'] }.index_by { |card| card['title'] }
  end

  it 'quadro: a mesma regra do card' do
    cards = cards_do_quadro(sem_chave)
    expect(cards['Alheio']).to include('value_cents' => nil, 'value_hidden' => true)
    expect(cards['Próprio']).to include('value_cents' => 120_000)

    expect(cards_do_quadro(com_chave).values.pluck('value_cents')).to contain_exactly(500_000, 120_000)
  end

  it 'detalhe: o histórico não traz o valor gravado na edição nem no ganho' do
    Crm::ActivityLogger.new(card: alheio, actor: admin, event_type: 'update', payload: { value_cents: 500_000, title: 'Alheio' })
                       .perform

    detalhe = ler("cards/#{alheio.id}", sem_chave)
    edicao = detalhe['activities'].find { |atividade| atividade['event_type'] == 'update' }
    expect(detalhe).to include('value_cents' => nil, 'value_hidden' => true)
    expect(edicao['payload']).to eq('title' => 'Alheio')

    edicao = ler("cards/#{alheio.id}", com_chave)['activities'].find { |atividade| atividade['event_type'] == 'update' }
    expect(edicao['payload']).to include('value_cents' => 500_000)
  end

  it 'somas da lista: sem a chave, a contagem fica e a soma vem nil' do
    grupo = ler('cards/summaries', sem_chave, pipeline_id: pipeline.id, group_by: 'stage')['groups'].first
    expect(grupo).to include('count' => 2, 'sum_cents' => nil)

    grupo = ler('cards/summaries', com_chave, pipeline_id: pipeline.id, group_by: 'stage')['groups'].first
    expect(grupo).to include('count' => 2, 'sum_cents' => 620_000)
  end

  it 'filtro por valor: sem a chave, é ignorado (filtrar revelaria o valor)' do
    expect(valores_da_lista(sem_chave, value_min: 200_000).keys).to contain_exactly('Alheio', 'Próprio')
    expect(valores_da_lista(com_chave, value_min: 200_000).keys).to eq(['Alheio'])
  end

  it 'ordenar por valor: sem a chave, vale a ordem padrão' do
    alheio.update!(updated_at: 1.hour.ago)
    ordem = ler('cards', sem_chave, pipeline_id: pipeline.id, sort: 'value_cents', direction: 'desc').pluck('title')
    expect(ordem).to eq(%w[Próprio Alheio])

    ordem = ler('cards', com_chave, pipeline_id: pipeline.id, sort: 'value_cents', direction: 'desc').pluck('title')
    expect(ordem).to eq(%w[Alheio Próprio])
  end

  it 'oportunidades do contato: a mesma regra do card' do
    linhas = ler("contacts/#{contato.id}/opportunities", sem_chave, result: 'all').index_by { |card| card['title'] }

    expect(linhas['Alheio']).to include('value_cents' => nil, 'value_hidden' => true)
    expect(linhas['Próprio']).to include('value_cents' => 120_000)
  end

  it 'painel: sem a chave, contagens ficam; valores, taxa por valor e meta vêm nil' do
    pipeline.update!(metadata: { 'goals' => { 'monthly_target_cents' => 1_000_000, 'currency' => 'BRL' } })

    resumo = ler('reports/summary', sem_chave, pipeline_id: pipeline.id)
    expect(resumo).to include('value_hidden' => true, 'open_count' => 2, 'open_value_by_currency' => nil,
                              'won_value_by_currency' => nil, 'win_rate_by_value' => nil, 'goal' => nil)

    resumo = ler('reports/summary', com_chave, pipeline_id: pipeline.id)
    expect(resumo).to include('value_hidden' => false, 'open_value_by_currency' => [{ 'currency' => 'BRL', 'value_cents' => 620_000 }])
    expect(resumo['goal']).to include('target_cents' => 1_000_000)
  end

  it 'funil do painel: sem a chave, a contagem por etapa fica e o valor vem nil' do
    etapa = ler('reports/funnel', sem_chave, pipeline_id: pipeline.id)['stages'].first
    expect(etapa).to include('count' => 2, 'value_by_currency' => nil)

    etapa = ler('reports/funnel', com_chave, pipeline_id: pipeline.id)['stages'].first
    expect(etapa['value_by_currency']).to eq([{ 'currency' => 'BRL', 'value_cents' => 620_000 }])
  end

  describe 'meta do mês no funil' do
    def meta = { 'monthly_target_cents' => 1_000_000, 'currency' => 'BRL' }

    before { pipeline.update!(metadata: { 'goals' => meta, 'ai' => { 'enabled' => false } }) }

    it 'sem a chave, o funil vem sem a meta; com ela, com a meta' do
      funil = ler('pipelines', sem_chave).find { |item| item['id'] == pipeline.id }
      expect(funil['metadata']).to eq('ai' => { 'enabled' => false })

      funil = ler('pipelines', com_chave).find { |item| item['id'] == pipeline.id }
      expect(funil['metadata']).to include('goals' => meta)
    end

    it 'sem a chave, salvar o funil não apaga nem muda a meta' do
      patch "#{crm}/pipelines/#{pipeline.id}",
            params: { pipeline: { metadata: { 'ai' => { 'enabled' => true } }, goal: { monthly_target_cents: 1 } } },
            headers: auth_headers(pessoa_com(base + %w[crm_manage_pipelines])), as: :json

      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.metadata).to eq('ai' => { 'enabled' => true }, 'goals' => meta)
    end
  end

  it 'resumo das conversões da Meta: sem a chave, contagens ficam e o valor aceito vem nil' do
    get "#{crm}/meta_conversions/summary", headers: auth_headers(sem_chave)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('accepted_count' => 0, 'accepted_value_by_currency' => nil)

    get "#{crm}/meta_conversions/summary", headers: auth_headers(com_chave)
    expect(response.parsed_body['payload']['accepted_value_by_currency']).to eq({})
  end

  it 'metas do mês: crm_metas_manage sem a chave não abre a gaveta (a meta é dinheiro)' do
    sem = AccountUser.find_by(account: account, user: pessoa_com(%w[crm_view crm_metas_manage]))
    com = AccountUser.find_by(account: account, user: pessoa_com(%w[crm_view crm_metas_manage sales_value_view]))

    expect(Crm::MetasPolicy.new({ user: sem.user, account: account, account_user: sem }, :metas).manage?).to be(false)
    expect(Crm::MetasPolicy.new({ user: com.user, account: account, account_user: com }, :metas).manage?).to be(true)
  end

  describe 'tokens de integração' do
    def criar_token(user, scopes)
      post "#{crm}/integration_tokens", params: { name: 'n8n', scopes: scopes }, headers: auth_headers(user), as: :json
    end

    it 'não cria token com sales_value_view para quem não tem a chave (nunca acima da própria função)' do
      criar_token(pessoa_com(%w[crm_view token_manage]), %w[crm_view sales_value_view])
      expect(response).to have_http_status(:unauthorized)

      criar_token(pessoa_com(%w[crm_admin token_manage]), %w[crm_view sales_value_view])
      expect(response).to have_http_status(:unauthorized)

      criar_token(pessoa_com(%w[crm_view token_manage sales_value_view]), %w[crm_view sales_value_view])
      expect(response).to have_http_status(:created)
      expect(Crm::IntegrationToken.last.granted_scopes).to contain_exactly('crm_view', 'sales_value_view')
    end

    it 'o token sem o escopo lê o CRM sem os valores; com o escopo, com' do
      sem = Crm::IntegrationToken.create!(account: account, created_by: admin, name: 'sem', scopes: %w[crm_view])
      com = Crm::IntegrationToken.create!(account: account, created_by: admin, name: 'com', scopes: %w[crm_view sales_value_view])

      expect(Crm::ValorDeVenda.ve?(sem.account_user)).to be(false)
      expect(Crm::ValorDeVenda.ve?(com.account_user)).to be(true)
    end
  end

  describe 'tempo real' do
    it 'não manda o card a quem a função não dá o CRM, e esconde o valor de quem não tem a chave (menos o card próprio)' do
      sem_crm = pessoa_com(%w[conversation_manage])
      inbox.add_members([sem_crm.id])
      enviados = Hash.new { |hash, token| hash[token] = {} }
      allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _evento, dados|
        enviados[tokens.first][dados[:title]] = dados[:value_cents]
      end

      [alheio, account.crm_cards.find_by!(title: 'Próprio')].each do |card|
        Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
      end

      expect(enviados).not_to have_key(sem_crm.pubsub_token)
      expect(enviados[sem_chave.pubsub_token]).to eq('Alheio' => nil, 'Próprio' => 120_000)
      expect(enviados[com_chave.pubsub_token]).to eq('Alheio' => 500_000, 'Próprio' => 120_000)
      expect(enviados[plain_agent.pubsub_token]).to eq('Alheio' => 500_000, 'Próprio' => 120_000)
    end
  end
end
