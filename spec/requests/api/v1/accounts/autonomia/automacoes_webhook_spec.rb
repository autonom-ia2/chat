require 'rails_helper'

# G13 (#2670): o segredo da assinatura do passo "webhook" e o que o salvar recusa no passo. O segredo é dos que a
# plataforma gera: o administrador ou a função com `token_manage` vê e troca.
RSpec.describe 'Automação livre · passo webhook (G13)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:automacao) { create(:autonomia_automacao, account: account, ligada_por: admin) }
  let(:caminho) { "/api/v1/accounts/#{account.id}/autonomia/automacoes/#{automacao.id}" }

  before { account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_editor', 'automacao_gatilhos') }

  describe 'o segredo' do
    it 'o administrador vê o segredo, sem cache, e ele não muda entre leituras', :aggregate_failures do
      get "#{caminho}/segredo_do_webhook", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
      primeiro = response.parsed_body['secret']
      expect(primeiro).to match(/\A\h{64}\z/)
      get "#{caminho}/segredo_do_webhook", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['secret']).to eq(primeiro)
    end

    it 'trocar invalida o anterior na hora, e cada automação tem o seu', :aggregate_failures do
      antes = Autonomia::Automacao::SegredoDoWebhook.new(automacao).valor
      outra = create(:autonomia_automacao, account: account, ligada_por: admin)

      post "#{caminho}/trocar_segredo_do_webhook", headers: admin.create_new_auth_token, as: :json

      novo = response.parsed_body['secret']
      expect(novo).not_to eq(antes)
      expect(Autonomia::Automacao::SegredoDoWebhook.new(automacao.reload).valor).to eq(novo)
      expect(Autonomia::Automacao::SegredoDoWebhook.new(outra).valor).not_to eq(novo)
      expect(automacao.reload.segredo_geracao).to eq(1)
      expect(account.reload.internal_attributes.to_json).not_to include(novo)
    end

    it 'uma gravação da conta lida antes da troca não volta o segredo anterior', :aggregate_failures do
      conta_lida_antes = Account.find(account.id)
      novo = Autonomia::Automacao::SegredoDoWebhook.new(automacao).trocar!

      conta_lida_antes.update!(internal_attributes: conta_lida_antes.internal_attributes.merge('outra' => true))

      expect(Autonomia::Automacao::SegredoDoWebhook.new(automacao).valor).to eq(novo)
    end

    it 'a função com token_manage vê e troca; sem ela, nem com automações e integrações', :aggregate_failures do
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage integration_manage])
      agente.account_users.find_by(account: account).update!(custom_role: funcao)

      get "#{caminho}/segredo_do_webhook", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{caminho}/trocar_segredo_do_webhook", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      funcao.update!(permissions: %w[token_manage])
      get "#{caminho}/segredo_do_webhook", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      post "#{caminho}/trocar_segredo_do_webhook", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'automação de outra conta não existe aqui' do
      outra = create(:autonomia_automacao, account: create(:account), ligada_por: admin)

      get "/api/v1/accounts/#{account.id}/autonomia/automacoes/#{outra.id}/segredo_do_webhook", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'o salvar' do
    def problemas(url, gravar: [])
      passo = { 'id' => 'w1', 'tipo' => 'webhook', 'descricao' => 'Mandar', 'url' => url, 'corpo' => { 'nome' => { '$valor' => 'contato.nome' } },
                'gravar' => gravar }
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    around { |exemplo| with_modified_env(FRONTEND_URL: 'https://app.plataforma.com') { exemplo.run } }

    it 'aceita https público' do
      expect(problemas('https://hooks.exemplo.com/entrada')).to eq([])
    end

    it 'recusa http, senha no endereço, IP interno, metadata e a própria plataforma', :aggregate_failures do
      frase = ->(chave) { I18n.t("autonomia.automacao.receita.#{chave}", passo: 'w1') }
      expect(problemas('http://hooks.exemplo.com/x')).to eq([frase.call(:webhook_so_https)])
      expect(problemas('https://usuario:senha@hooks.exemplo.com/x')).to eq([frase.call(:webhook_sem_senha_no_endereco)])
      %w[https://10.0.0.5/x https://127.0.0.1/x https://169.254.169.254/latest https://localhost/x https://[::1]/x
         https://app.plataforma.com/api].each do |url|
        expect(problemas(url)).to eq([frase.call(:webhook_endereco_interno)]), url
      end
    end

    it 'quem só monta automações (sem a chave de integrações) não salva o passo que manda dados para fora', :aggregate_failures do
      passo = { 'id' => 'w1', 'tipo' => 'webhook', 'descricao' => 'Mandar', 'url' => 'https://hooks.exemplo.com/x' }
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage])
      conta_do_agente = agente.account_users.find_by(account: account)
      conta_do_agente.update!(custom_role: funcao)
      frase = I18n.t('autonomia.automacao.receita.webhook_sem_permissao', passo: 'w1')

      expect(Autonomia::Automacao::Receita.new(receita, conta: account, account_user: conta_do_agente).problemas).to include(frase)
      funcao.update!(permissions: %w[automation_manage integration_manage])
      expect(Autonomia::Automacao::Receita.new(receita, conta: account, account_user: conta_do_agente.reload).problemas).not_to include(frase)
    end

    it 'a resposta só grava em atributo que existe, num lugar que o gatilho alcança', :aggregate_failures do
      expect(problemas('https://hooks.exemplo.com/x', gravar: [{ 'chave' => 'id', 'destino' => 'contato.email' }]).join).to include('contato.email')
      expect(problemas('https://hooks.exemplo.com/x', gravar: [{ 'chave' => 'id', 'destino' => 'contato.atributos.nao_existe' }])).not_to be_empty
      expect(problemas('https://hooks.exemplo.com/x', gravar: [{ 'chave' => 'id', 'destino' => 'card.atributos.numero' }])).not_to be_empty
    end
  end
end
