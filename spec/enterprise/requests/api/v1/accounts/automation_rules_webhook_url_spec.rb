require 'rails_helper'

# #2450: a URL do webhook costuma levar um token. Quem não é administrador nem tem integration_manage lê a regra e a
# automação inteiras, com a URL mascarada; admin e integration_manage veem a URL inteira. A parte de função só existe
# com o EE carregado.
RSpec.describe 'URL do webhook escondida de quem só vê', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { 'https://hooks.exemplo.com/entrada?token=segredo123' }
  let(:mascarada) { 'https://hooks.exemplo.com/•••' }
  let(:so_ve) { custom_role_user('automation_view') }
  let(:so_automacao) { custom_role_user('automation_manage') }
  let(:com_integracao) { custom_role_user('automation_view', 'integration_manage') }

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  describe 'regra automática' do
    let(:base) { "/api/v1/accounts/#{account.id}/automation_rules" }
    let(:condicoes) { [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
    let!(:regra) do
      create(:automation_rule, account: account, event_name: 'conversation_created', conditions: condicoes,
                               actions: [{ action_name: 'add_label', action_params: ['lead'] },
                                         { action_name: 'send_webhook_event', action_params: [url] }])
    end

    def acoes_vistas(user, caminho)
      get caminho, headers: user.create_new_auth_token, as: :json
      payload = response.parsed_body['payload']
      (payload.is_a?(Array) ? payload.first : payload)['actions']
    end

    it 'quem só vê lê a regra inteira, com a URL mascarada, na lista e na regra', :aggregate_failures do
      [base, "#{base}/#{regra.id}"].each do |caminho|
        acoes = acoes_vistas(so_ve, caminho)

        expect(response).to have_http_status(:ok)
        expect(acoes.pluck('action_name')).to eq(%w[add_label send_webhook_event])
        expect(acoes.last['action_params']).to eq([mascarada])
        expect(acoes.first['action_params']).to eq(['lead'])
        expect(response.body).not_to include('segredo123')
      end
    end

    it 'o administrador e a função com integration_manage veem a URL inteira', :aggregate_failures do
      [admin, com_integracao].each do |user|
        expect(acoes_vistas(user, "#{base}/#{regra.id}").last['action_params']).to eq([url])
      end
    end

    it 'salvar com a URL mascarada, sem integration_manage, não troca a URL gravada' do
      acoes = [{ action_name: 'add_label', action_params: ['lead'] }, { action_name: 'send_webhook_event', action_params: [mascarada] }]

      patch "#{base}/#{regra.id}", params: { name: 'Outro nome', actions: acoes }, headers: so_automacao.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(regra.reload.actions.last['action_params']).to eq([url])
    end
  end

  describe 'automação (passo webhook)' do
    let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
    let(:receita) do
      condicao = { 'campo' => { '$valor' => 'conversa.status' }, 'op' => 'igual', 'valor' => 'resolved' }
      webhook = { 'id' => 'w1', 'tipo' => 'webhook', 'descricao' => 'Mandar', 'url' => url }
      { 'gatilho' => { 'tipo' => 'conversa.resolvida' },
        'passos' => [{ 'id' => 's1', 'tipo' => 'se', 'condicao' => condicao, 'entao' => [webhook], 'senao' => [] }] }
    end
    let(:automacao) do
      create(:autonomia_automacao, account: account).tap do |automacao|
        versao = create(:autonomia_automacao_versao, automacao: automacao, numero: 1)
        automacao.update_columns(versao_ativa_id: versao.id) # rubocop:disable Rails/SkipsModelValidations
        Autonomia::Automacao::Versao.where(id: versao.id).update_all(receita: receita) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    before { account.enable_features!('automacao_editor') }

    def url_vista(user)
      get "#{base}/#{automacao.id}", headers: user.create_new_auth_token, as: :json
      response.parsed_body.dig('versao', 'receita', 'passos', 0, 'entao', 0, 'url')
    end

    it 'quem só vê lê o passo com a URL mascarada, também dentro de um ramo; a gravada não muda', :aggregate_failures do
      expect(url_vista(so_ve)).to eq(mascarada)
      expect(response.body).not_to include('segredo123')
      expect(automacao.versao_ativa.reload.receita.dig('passos', 0, 'entao', 0, 'url')).to eq(url)
    end

    it 'o administrador e a função com integration_manage veem a URL inteira', :aggregate_failures do
      expect(url_vista(admin)).to eq(url)
      expect(url_vista(com_integracao)).to eq(url)
    end

    it 'o histórico de quem só vê traz a receita com a URL mascarada', :aggregate_failures do
      create(:autonomia_automacao_execucao, versao: automacao.versao_ativa)

      get "#{base}/#{automacao.id}/historico", headers: so_ve.create_new_auth_token, as: :json

      expect(response.parsed_body['versoes'].values.first.dig('receita', 'passos', 0, 'entao', 0, 'url')).to eq(mascarada)
      expect(response.body).not_to include('segredo123')
    end
  end
end
