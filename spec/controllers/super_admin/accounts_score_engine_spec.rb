require 'rails_helper'

# Só o superadmin vira a nota da conta para o Orth (#681), no console da conta, ao lado dos interruptores da prospecção.
RSpec.describe 'Super Admin prospecting score engine', type: :request do
  let(:account) { create(:account) }
  let!(:super_admin) { create(:super_admin) }
  let(:toggle_path) { "/super_admin/accounts/#{account.id}/toggle_prospecting_score_engine" }

  def engine
    Autonomia::Prospecting::Setting.for_account(account).score_engine
  end

  it 'recusa quem não entrou como superadmin e mantém o legado' do
    post toggle_path, params: { engine: 'orth' }

    expect(response).to have_http_status(:redirect)
    expect(engine).to eq('legacy')
  end

  it 'recusa administrador da conta que não é superadmin' do
    sign_in(create(:user, :administrator, account: account), scope: :user)

    post toggle_path, params: { engine: 'orth' }

    expect(engine).to eq('legacy')
  end

  context 'when it is the super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'vira a conta para o Orth e desvira para o legado' do
      post toggle_path, params: { engine: 'orth' }
      expect(flash[:notice]).to eq('Prospecting score engine: orth')
      expect(engine).to eq('orth')

      post toggle_path, params: { engine: 'legacy' }
      expect(flash[:notice]).to eq('Prospecting score engine: legacy')
      expect(engine).to eq('legacy')
    end

    it 'recusa motor fora da lista sem mudar a conta' do
      post toggle_path, params: { engine: 'outro' }

      expect(flash[:error]).to eq('score_engine must be legacy or orth')
      expect(engine).to eq('legacy')
    end

    it 'mostra o interruptor na página da conta com o motor atual' do
      get "/super_admin/accounts/#{account.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(toggle_path, 'Prospecting score engine', 'Current engine: <strong>legacy</strong>', 'Switch to Orth score')
    end
  end
end
