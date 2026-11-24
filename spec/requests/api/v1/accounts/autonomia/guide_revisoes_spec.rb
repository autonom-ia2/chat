require 'rails_helper'

# O cartão da revisão de conversas (#3158, B8b) pela API: andamento, "ler as que faltam" e isolamento.
RSpec.describe 'Guia da Plataforma — revisão de conversas', type: :request do
  let(:account) { create(:account) }
  let(:dono) { create(:user, account: account, role: :agent) }
  let(:outro) { create(:user, account: account, role: :administrator) }
  let(:rota) { "/api/v1/accounts/#{account.id}/autonomia/guide/revisoes" }
  let(:revisao) do
    Autonomia::Guide::Revisao.create!(account: account, user: dono, status: 'concluida', titulo: 'Revisão', pedido: 'Por quê',
                                      selecao: { 'de' => '2026-11-17', 'ate' => '2026-11-23' }, ids: (1..400).to_a,
                                      limite: 300, posicao: 300, lidas: 300)
  end

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  it 'mostra a revisão ao dono', :aggregate_failures do
    get "#{rota}/#{revisao.id}", headers: dono.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'concluida', 'total' => 400, 'faltam' => 100, 'de' => '2026-11-17')
  end

  it 'responde 404 para outra pessoa, mesmo administradora' do
    get "#{rota}/#{revisao.id}", headers: outro.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'lê as que faltam: mais 300 e um job novo', :aggregate_failures do
    expect do
      post "#{rota}/#{revisao.id}/continuar", headers: dono.create_new_auth_token, as: :json
    end.to have_enqueued_job(Autonomia::Guide::RevisaoJob).with(revisao.id)

    expect(response.parsed_body).to include('status' => 'na_fila', 'limite' => 400)
  end

  it 'recusa continuar o que já leu tudo' do
    revisao.update!(posicao: 400)
    post "#{rota}/#{revisao.id}/continuar", headers: dono.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('nada_a_continuar')
  end

  it 'diz que outra revisão anda quando é isso que impede continuar' do
    Autonomia::Guide::Revisao.create!(account: account, user: dono, status: 'rodando', titulo: 'Outra', pedido: 'Por quê',
                                      selecao: {}, ids: [1], limite: 300)
    post "#{rota}/#{revisao.id}/continuar", headers: dono.create_new_auth_token, as: :json

    expect(response.parsed_body['error']).to eq('outra_andando')
  end

  it 'não mostra o motivo de conversa que o dono deixou de ver', :aggregate_failures do
    inbox = create(:inbox, account: account)
    create(:inbox_member, user: dono, inbox: inbox)
    vista = create(:conversation, account: account, inbox: inbox)
    escondida = create(:conversation, account: account)
    revisao.update!(resultados: [{ 'categoria' => 'Demora', 'motivo' => 'vista', 'conversa_id' => vista.id, 'numero' => vista.display_id },
                                 { 'categoria' => 'Demora', 'motivo' => 'escondida', 'conversa_id' => escondida.id,
                                   'numero' => escondida.display_id }])

    get "#{rota}/#{revisao.id}", headers: dono.create_new_auth_token, as: :json

    motivos = response.parsed_body['categorias'].flat_map { |categoria| categoria['conversas'] }.pluck('motivo')
    expect(motivos).to eq(['vista'])
  end
end
