require 'rails_helper'

# Metas do mês por pessoa (#1991, F4 do #1871) por HTTP: quem define (chave `crm_metas_manage`), a gaveta no formato do
# protótipo, a gravação tudo-ou-nada e a meta no topo de "Só eu" (Decisões 3 e 4).
RSpec.describe 'Api::V1::Accounts::Crm::Metas', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Marcos') }
  let!(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let!(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:sale) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').tap { |p, _| p.update!(counts_as_sale: true) } }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte').tap { |p, _| p.update!(counts_as_sale: false) } }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') do
      travel_to(Time.utc(2026, 10, 19, 15, 0)) { example.run }
    end
  end

  before do
    account.enable_features('crm_metas', 'crm_numeros_lentes')
    account.save!
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent, name: "Função #{permissions.join}")
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def call(verb, user, path, params = {})
    send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def won(owner:, value_cents:, closed_by: admin, pipeline: sale, closed_at: nil)
    funil, etapa = pipeline
    card = account.crm_cards.create!(pipeline: funil, stage: etapa, owner: owner, title: "Card #{SecureRandom.hex(3)}",
                                     value_cents: value_cents)
    Crm::Cards::Closer.new(card: card, actor: closed_by, result: 'won').perform
    card.update_columns(closed_at: closed_at) if closed_at # rubocop:disable Rails/SkipsModelValidations
  end

  def goal(user, reais, month: Date.new(2026, 10, 1))
    Crm::PersonGoal.create!(account: account, pipeline: sale.first, user: user, month: month, target_cents: reais * 100)
  end

  def pessoa(body, user)
    body['funis'].first['pessoas'].find { |linha| linha['id'] == user.id }
  end

  describe 'quem define' do
    # #2075: a meta é dinheiro, então metas e crm_admin também pedem os valores em R$ (sales_value_view).
    it 'administrador e função com crm_metas_manage ou crm_admin; nunca o agente sem função nem só relatórios' do
      sale
      quem = {
        admin => :ok, role_user('crm_view', 'crm_metas_manage', 'sales_value_view') => :ok,
        role_user('crm_admin', 'sales_value_view') => :ok, ana => :unauthorized,
        role_user('crm_view', 'crm_view_reports') => :unauthorized, role_user('crm_metas_manage') => :unauthorized,
        role_user('crm_view', 'crm_metas_manage') => :unauthorized, role_user('crm_admin') => :unauthorized
      }
      quem.each do |user, status|
        call(:get, user, "#{base}/metas")
        expect(response).to have_http_status(status), user.name
        call(:put, user, "#{base}/metas", funis: [])
        expect(response).to have_http_status(status), user.name
      end
    end

    it 'sem a flag a gaveta não existe e o topo não mostra meta' do
      account.disable_features('crm_metas')
      account.save!
      goal(ana, 8000)

      call(:get, admin, "#{base}/metas")
      expect(response).to have_http_status(:not_found)
      call(:get, ana, "#{base}/numeros")
      expect(response.parsed_body['topo']['meta']).to be_nil
    end
  end

  describe 'função personalizada (EE, parecer de acesso)' do
    it 'crm_metas_manage sem crm_view não lê nem grava as metas dos colegas' do
      goal(ana, 8000)
      so_metas = role_user('crm_metas_manage')

      call(:get, so_metas, "#{base}/metas")
      expect(response).to have_http_status(:unauthorized)
      call(:put, so_metas, "#{base}/metas", funis: [{ id: sale.first.id, metaFunil: 999, pessoas: [{ id: ana.id, meta: 1 }] }])
      expect(response).to have_http_status(:unauthorized)

      expect(Crm::PersonGoal.find_by(user: ana).target_cents).to eq(800_000)
      expect(sale.first.reload.metadata['goals']).to be_nil
    end

    it 'com crm_view, o funil de Vender fora do alcance dela não aparece na gaveta e não grava' do
      liberado = sale.first
      restrito, = create_crm_pipeline(account: account, user: admin, name: 'Restrito')
      restrito.update!(counts_as_sale: true)
      gestora = role_user('crm_view', 'crm_metas_manage', 'sales_value_view')
      inbox = create_crm_inbox(account: account, members: [gestora])
      [liberado, restrito].each { |funil| account.crm_pipeline_inboxes.create!(pipeline: funil, inbox: inbox, created_by: admin) }
      acesso = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: gestora, all_pipelines: false, triage: false)
      acesso.agent_pipelines.create!(account: account, pipeline: liberado)

      call(:get, admin, "#{base}/metas")
      expect(response.parsed_body['funis'].pluck('nome')).to eq(%w[Vendas Restrito])

      call(:get, gestora, "#{base}/metas")
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['funis'].pluck('nome')).to eq(['Vendas'])

      expect do
        call(:put, gestora, "#{base}/metas", funis: [{ id: restrito.id, metaFunil: 999, pessoas: [{ id: ana.id, meta: 100 }] }])
      end.not_to change(Crm::PersonGoal, :count)
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('crm.metas.fora_do_alcance')
      expect(restrito.reload.metadata['goals']).to be_nil
    end
  end

  describe 'a gaveta' do
    it 'traz só funis de Vender, a meta do funil, a de cada pessoa, a do mês anterior e a sugestão com o motivo' do
      sale.first.update!(metadata: { 'goals' => { 'monthly_target_cents' => 2_000_000, 'currency' => 'BRL' } })
      suporte
      { 7 => 720_000, 8 => 840_000, 9 => 790_000 }.each do |mes, cents|
        won(owner: ana, value_cents: cents, closed_at: Time.utc(2026, mes, 10, 15, 0))
      end
      goal(ana, 8000)
      goal(ana, 7500, month: Date.new(2026, 9, 1))

      call(:get, admin, "#{base}/metas")

      body = response.parsed_body
      expect(body).to include('mes' => '2026-10', 'mesAnterior' => '2026-09')
      expect(body['funis'].pluck('nome')).to eq(['Vendas'])
      expect(body['funis'].first).to include('medida' => 'valor', 'moeda' => 'BRL', 'metaFunil' => 20_000)
      expect(pessoa(body, ana)).to include('nome' => 'Ana', 'meta' => 8000, 'anterior' => 7500,
                                           'sugestao' => { 'valor' => 8000, 'historico' => [7200, 8400, 7900] })
      expect(pessoa(body, bruno)).to include('meta' => nil, 'anterior' => nil, 'sugestao' => { 'valor' => nil, 'historico' => [0, 0, 0] })
    end

    it 'lista quem vende, pela régua do "Só eu"; quem só atende sai, a não ser que já tenha meta' do
      sale
      funil_suporte, etapa_suporte = suporte
      carla = create(:user, account: account, role: :agent, name: 'Carla')
      dora = create(:user, account: account, role: :agent, name: 'Dora')
      [carla, dora].each do |atendente|
        account.crm_cards.create!(pipeline: funil_suporte, stage: etapa_suporte, owner: atendente, title: 'Caso')
      end
      goal(dora, 1000, month: Date.new(2026, 9, 1))

      call(:get, admin, "#{base}/metas")

      nomes = response.parsed_body['funis'].first['pessoas'].pluck('nome')
      expect(nomes).to include('Ana', 'Bruno', 'Marcos', 'Dora')
      expect(nomes).not_to include('Carla')

      call(:put, admin, "#{base}/metas", funis: [{ id: sale.first.id, pessoas: [{ id: carla.id, meta: 100 }] }])
      expect(response).to have_http_status(:not_found)
    end

    it 'credita a venda a quem era o responsável no fechamento, não a quem clicou (Decisão 3)' do
      sale
      won(owner: ana, value_cents: 300_000, closed_by: bruno, closed_at: Time.utc(2026, 9, 10, 15, 0))

      call(:get, admin, "#{base}/metas")

      expect(pessoa(response.parsed_body, ana)['sugestao']['historico']).to eq([0, 0, 3000])
      expect(pessoa(response.parsed_body, bruno)['sugestao']['historico']).to eq([0, 0, 0])
    end
  end

  describe 'a gravação' do
    it 'grava a meta do funil e a de cada pessoa no mês de hoje, e vazio tira a meta' do
      funil = sale.first
      goal(bruno, 5000)

      call(:put, admin, "#{base}/metas",
           funis: [{ id: funil.id, metaFunil: 21_000, pessoas: [{ id: ana.id, meta: 8000 }, { id: bruno.id, meta: nil }] }])

      expect(response).to have_http_status(:ok)
      expect(funil.reload.metadata['goals']).to eq('monthly_target_cents' => 2_100_000, 'currency' => 'BRL')
      expect(Crm::PersonGoal.where(user: ana).pluck(:month, :target_cents, :currency))
        .to eq([[Date.new(2026, 10, 1), 800_000, 'BRL']])
      expect(Crm::PersonGoal.where(user: bruno)).to be_empty
      expect(pessoa(response.parsed_body, ana)['meta']).to eq(8000)
    end

    it 'campo que não vem não muda: a meta do funil (com centavos) e a da pessoa ficam' do
      funil = sale.first
      funil.update!(metadata: { 'goals' => { 'monthly_target_cents' => 2_000_050, 'currency' => 'BRL' } })
      goal(bruno, 5000)

      call(:put, admin, "#{base}/metas", funis: [{ id: funil.id, pessoas: [{ id: ana.id, meta: 100 }, { id: bruno.id }] }])

      expect(response).to have_http_status(:ok)
      expect(funil.reload.metadata['goals']['monthly_target_cents']).to eq(2_000_050)
      expect(Crm::PersonGoal.find_by(user: bruno).target_cents).to eq(500_000)
    end

    it 'recusa quando o mês virou com a gaveta aberta, sem gravar nada' do
      call(:put, admin, "#{base}/metas", mes: '2026-09', funis: [{ id: sale.first.id, pessoas: [{ id: ana.id, meta: 100 }] }])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.metas.mes_mudou')
      expect(Crm::PersonGoal.count).to eq(0)

      call(:put, admin, "#{base}/metas", mes: '2026-10', funis: [{ id: sale.first.id, pessoas: [{ id: ana.id, meta: 100 }] }])
      expect(response).to have_http_status(:ok)
    end

    it 'guarda o resto do metadata do funil' do
      funil = sale.first
      funil.update!(metadata: { 'ai' => { 'enabled' => true } })

      call(:put, admin, "#{base}/metas", funis: [{ id: funil.id, metaFunil: 1000, pessoas: [] }])

      expect(funil.reload.metadata).to include('ai' => { 'enabled' => true })
    end

    it 'recusa tudo quando um valor não é inteiro de 0 a 1 bilhão' do
      funil = sale.first
      ['8000', 1.5, -1, 1_000_000_001].each do |valor|
        call(:put, admin, "#{base}/metas", funis: [{ id: funil.id, pessoas: [{ id: ana.id, meta: 100 }, { id: bruno.id, meta: valor }] }])

        expect(response).to have_http_status(:unprocessable_entity), valor.inspect
        expect(response.parsed_body['error']).to eq('crm.metas.valor_invalido')
      end
      expect(Crm::PersonGoal.count).to eq(0)
    end

    it 'recusa funil de Atender, funil de outra conta e pessoa de fora da conta, sem gravar nada' do
      funil = sale.first
      outra = create(:user, name: 'De fora')
      alvos = [
        { id: suporte.first.id, metaFunil: 10, pessoas: [] },
        { id: create(:account).crm_pipelines.create!(name: 'X', created_by: admin, counts_as_sale: true).id, pessoas: [] },
        { id: funil.id, pessoas: [{ id: outra.id, meta: 10 }] }
      ]
      alvos.each do |alvo|
        call(:put, admin, "#{base}/metas", funis: [{ id: funil.id, metaFunil: 999, pessoas: [{ id: ana.id, meta: 10 }] }, alvo])

        expect(response).to have_http_status(:not_found), alvo.inspect
        expect(response.parsed_body['error']).to eq('crm.metas.fora_do_alcance')
      end
      expect(Crm::PersonGoal.count).to eq(0)
      expect(funil.reload.metadata['goals']).to be_nil
    end
  end

  describe 'o topo de "Só eu"' do
    it 'mostra a meta da própria pessoa, nunca a dos colegas (Decisão 4)' do
      sale
      goal(ana, 8000)
      goal(bruno, 6000)
      won(owner: ana, value_cents: 620_000)

      call(:get, ana, "#{base}/numeros")

      topo = response.parsed_body['topo']
      expect(topo).to include('feito' => 6200.0, 'meta' => 8000.0)
      expect(topo['frase']).to include('tipo' => 'eu_vende', 'meta' => 8000.0)
      expect(response.body).not_to include('6000', 'Bruno')
    end

    it 'não soma a meta de funil arquivado' do
      sale
      goal(ana, 8000)
      # Funil arquivado sai dos Números: com outro de Vender ativo, o topo existe e não leva a meta do arquivado.
      create_crm_pipeline(account: account, user: admin, name: 'Vendas novo')
      sale.first.archived!

      call(:get, ana, "#{base}/numeros")
      expect(response.parsed_body['topo']['meta']).to be_nil
    end

    it 'mostra a meta do mês pedido' do
      sale
      goal(ana, 7000, month: Date.new(2026, 9, 1))

      call(:get, ana, "#{base}/numeros", mes: '2026-09')
      expect(response.parsed_body['topo']['meta']).to eq(7000.0)
      call(:get, ana, "#{base}/numeros")
      expect(response.parsed_body['topo']['meta']).to be_nil
    end
  end
end
