require 'rails_helper'

RSpec.describe 'Tela inicial API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:colega) { create(:user, account: account, role: :agent) }
  let(:caixa) { create(:inbox, account: account) }
  let(:outra_caixa) { create(:inbox, account: account) }
  let(:rota) { "/api/v1/accounts/#{account.id}/tela_inicial/resumo" }

  def conversa(inbox: caixa, dono: nil, atendida: false, status: :open)
    create(:conversation, account: account, inbox: inbox, status: status, assignee: dono).tap do |c|
      c.update!(first_reply_created_at: 1.hour.ago, waiting_since: nil) if atendida
    end
  end

  before do
    create(:inbox_member, user: agente, inbox: caixa)
    create(:inbox_member, user: colega, inbox: caixa)
  end

  it 'exige autenticação' do
    get rota, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'o agente vê só os números dele, sem a equipe' do
    2.times { conversa(dono: agente) }
    conversa(dono: agente, atendida: true)
    conversa(dono: agente, status: :resolved)
    conversa(dono: colega)
    conversa
    conversa(inbox: outra_caixa)

    get rota, headers: agente.create_new_auth_token, as: :json

    corpo = response.parsed_body
    expect(response).to have_http_status(:success)
    expect(corpo.slice('esperam', 'sem_responsavel')).to eq('esperam' => 2, 'sem_responsavel' => 1)
    expect(corpo['fora_do_prazo']).to be_nil
    expect(corpo).not_to have_key('equipe')
  end

  it 'o administrador recebe também a equipe, de todas as caixas' do
    conversa(dono: admin)
    conversa(dono: agente)
    conversa(dono: colega, atendida: true)
    conversa
    conversa(inbox: outra_caixa)

    get rota, headers: admin.create_new_auth_token, as: :json

    corpo = response.parsed_body
    expect(corpo['esperam']).to eq(1)
    expect(corpo['sem_responsavel']).to eq(2)
    expect(corpo['equipe']).to eq('esperam' => 4, 'sem_responsavel' => 2, 'fora_do_prazo' => nil)
  end

  it 'a próxima é a dele que espera há mais tempo' do
    recente = conversa(dono: agente)
    antiga = conversa(dono: agente)
    recente.update!(waiting_since: 10.minutes.ago)
    antiga.update!(waiting_since: 3.hours.ago)

    get rota, headers: agente.create_new_auth_token, as: :json

    proxima = response.parsed_body['proxima']
    expect(proxima.slice('id', 'display_id', 'nome_do_contato')).to eq(
      'id' => antiga.id, 'display_id' => antiga.display_id, 'nome_do_contato' => antiga.contact.name
    )
    expect(proxima['waiting_since']).to eq(antiga.reload.waiting_since.to_i)
  end

  it 'nada esperando: zero e sem próxima' do
    conversa(dono: agente, atendida: true)

    get rota, headers: agente.create_new_auth_token, as: :json

    expect(response.parsed_body.slice('esperam', 'proxima')).to eq('esperam' => 0, 'proxima' => nil)
  end

  it 'outra conta não vaza' do
    outra = create(:account)
    create(:conversation, account: outra, assignee: create(:user, account: outra))
    create(:conversation, account: outra)

    get rota, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['equipe']).to include('esperam' => 0, 'sem_responsavel' => 0)
  end

  it 'conta de outra pessoa responde 401' do
    outra = create(:account)

    get "/api/v1/accounts/#{outra.id}/tela_inicial/resumo", headers: agente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
