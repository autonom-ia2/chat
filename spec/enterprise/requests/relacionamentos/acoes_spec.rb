require 'rails_helper'

# #2894 — as ações em grupo da Lista nova de Relacionamentos para quem tem função personalizada: cada ação pede a mesma
# chave que a tela de hoje pede (ver o CRM, criar card, editar contato, apagar contato), além de ver os contatos.
RSpec.describe 'Ações em grupo da Lista de Relacionamentos: funções', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let!(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('relacionamentos_novo')
    create(:label, account: account, title: 'feira')
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def pedir(caminho, quem:, **corpo)
    post "#{base}/#{caminho}", params: corpo, headers: quem.create_new_auth_token, as: :json
  end

  def o_que_mudou
    [account.contacts.exists?(ana.id), account.crm_cards.count, ana.reload.label_list]
  end

  describe 'GET funis' do
    it 'só mostra os funis a quem a função deixa ver o CRM' do
      vendas

      get "#{base}/funis", headers: pessoa_com(%w[contact_view]).create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      get "#{base}/funis", headers: pessoa_com(%w[contact_view crm_view]).create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.pluck('nome')).to eq(['Vendas'])
    end

    # Acesso por funil (#1148): a lista é a mesma do quadro, só com os funis da pessoa.
    it 'mostra só os funis de quem tem acesso por funil' do
      sinistro = create_crm_pipeline(account: account, user: admin, name: 'Sinistro')
      caixa = create(:inbox, account: account)
      account.crm_pipeline_inboxes.create!(pipeline: vendas.first, inbox: caixa)
      account.crm_pipeline_inboxes.create!(pipeline: sinistro.first, inbox: create(:inbox, account: account))
      vendedora = pessoa_com(%w[contact_view crm_view crm_manage_cards])
      create(:inbox_member, user: vendedora, inbox: caixa)
      acesso = Crm::InboxAgentAccess.create!(account: account, inbox: caixa, user: vendedora, all_pipelines: false, triage: false)
      acesso.agent_pipelines.create!(account: account, pipeline: vendas.first)

      get "#{base}/funis", headers: vendedora.create_new_auth_token
      expect(response.parsed_body.pluck('nome')).to eq(['Vendas'])

      pedir('cards', quem: vendedora, pessoa_ids: [ana.id], funil_id: sinistro.first.id, etapa_id: sinistro.last.id)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'funil desconhecido')
      expect(account.crm_cards.count).to eq(0)
    end
  end

  describe 'POST cards' do
    let(:corpo) { { pessoa_ids: [ana.id], funil_id: vendas.first.id, etapa_id: vendas.last.id } }

    it 'pede a chave de criar card do CRM, e a de ver os contatos' do
      [%w[contact_view], %w[contact_view crm_view], %w[contact_view crm_view crm_move_cards], %w[crm_view crm_manage_cards]].each do |chaves|
        pedir('cards', quem: pessoa_com(chaves), **corpo)

        expect(response).to have_http_status(:unauthorized), chaves.to_s
      end
      expect(o_que_mudou).to eq([true, 0, []])
    end

    it 'cria o card para quem tem as duas chaves' do
      pedir('cards', quem: pessoa_com(%w[contact_view crm_manage_cards]), **corpo)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('criados' => 1, 'de_fora' => [])
    end
  end

  describe 'POST etiqueta' do
    it 'pede a chave de editar contatos' do
      pedir('etiqueta', quem: pessoa_com(%w[contact_view contact_delete]), pessoa_ids: [ana.id], etiqueta: 'feira')

      expect(response).to have_http_status(:unauthorized)
      expect(o_que_mudou).to eq([true, 0, []])
    end

    it 'etiqueta para quem tem a chave' do
      pedir('etiqueta', quem: pessoa_com(%w[contact_manage]), pessoa_ids: [ana.id], etiqueta: 'feira')

      expect(response.parsed_body).to eq('aplicadas' => 1, 'de_fora' => [])
    end
  end

  describe 'POST apagar' do
    it 'pede a chave de apagar contatos: editar não basta' do
      pedir('apagar', quem: pessoa_com(%w[contact_manage]), pessoa_ids: [ana.id])

      expect(response).to have_http_status(:unauthorized)
      expect(o_que_mudou).to eq([true, 0, []])
    end

    it 'apaga para quem tem a chave' do
      pedir('apagar', quem: pessoa_com(%w[contact_view contact_delete]), pessoa_ids: [ana.id])

      expect(response.parsed_body).to eq('apagadas' => 1, 'de_fora' => [])
      expect(account.contacts.exists?(ana.id)).to be(false)
    end
  end
end
