require 'rails_helper'

# #3100 — o cartão fidelidade com função personalizada: `fidelidade_view` vê o cartão e o painel; `fidelidade_manage`
# cria, muda, pausa e ajusta à mão (e vê). Dar o prêmio pela ficha segue quem pode mexer no contato (D1), não a chave.
RSpec.describe 'Fidelidade com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let(:regras) { { tipo: 'carimbos', a_cada: 50, ganha: 1, meta: 10, premio: 'Uma lavagem grátis' } }

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def call(user, verb, path, params = {})
    public_send(verb, "#{base}/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
  end

  it 'aceita as duas chaves novas na função' do
    expect(CustomRole::PERMISSIONS).to include('fidelidade_view', 'fidelidade_manage')
  end

  it 'ver: lê o cartão e o painel, mas não muda nem ajusta' do
    viewer = role_user('fidelidade_view')

    call(viewer, :get, 'fidelidade/programa')
    expect(response).to have_http_status(:ok)
    call(viewer, :get, 'fidelidade/resumo')
    expect(response).to have_http_status(:ok)
    call(viewer, :put, 'fidelidade/programa', programa: regras)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'mexer: cria, pausa e ajusta à mão, e também vê' do
    # O ajuste fica na ficha: a função precisa ver os contatos para chegar nela.
    manager = role_user('fidelidade_manage', 'contact_view')

    call(manager, :put, 'fidelidade/programa', programa: regras)
    expect(response).to have_http_status(:ok)
    call(manager, :patch, 'fidelidade/programa', ligado: false)
    expect(response.parsed_body).to include('ligado' => false)
    call(manager, :get, 'fidelidade/programa')
    expect(response).to have_http_status(:ok)
    call(manager, :post, "relacionamentos/pessoas/#{ana.id}/fidelidade/ajustes", quantos: 2)
    expect(response).to have_http_status(:created)
  end

  it 'sem a chave, a função não vê o painel' do
    call(role_user('contact_view'), :get, 'fidelidade/resumo')

    expect(response).to have_http_status(:unauthorized)
  end

  it 'dar o prêmio pede mexer no contato: só ver o contato não basta' do
    programa = Fidelidade::Programa.create!(account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                                            premio: 'Uma lavagem grátis', ligado: true, ligado_em: 1.day.ago)
    Fidelidade::Carteira.new(programa, ana).entrar(tipo: 'presente', quantos: 10)

    call(role_user('contact_view'), :post, "relacionamentos/pessoas/#{ana.id}/fidelidade/premios")
    expect(response).to have_http_status(:unauthorized)
    call(role_user('contact_manage'), :post, "relacionamentos/pessoas/#{ana.id}/fidelidade/premios")
    expect(response).to have_http_status(:created)
  end
end
