require 'rails_helper'

# O que o Guia fez e o desfazer (#855), pela API que a tela usa. A conversa do
# Guia some ao recarregar a página; é por aqui que a pessoa desfaz depois.
RSpec.describe 'Guia da Plataforma — o que ele fez', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:outro_admin) { create(:user, account: account, role: :administrator) }
  let(:rota) { "/api/v1/accounts/#{account.id}/autonomia/guide/execucoes" }
  let(:execucao) do
    execucao = Autonomia::Guide::Execucao.abrir(account: account, user: admin)
    Autonomia::Guide::Diario.gravando(execucao, 0) { account.labels.create!(title: 'nova') }
    execucao.registrar_passo(acao: 'POST labels', frase: 'Criei a etiqueta nova.', feito: true)
    execucao
  end

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  it 'lista o que o Guia fez para a pessoa, com o desfazer', :aggregate_failures do
    execucao
    get rota, headers: admin.create_new_auth_token, as: :json

    item = response.parsed_body['execucoes'].first
    expect(item['passos']).to eq([{ 'frase' => 'Criei a etiqueta nova.', 'ok' => true }])
    expect(item['desfazivel']).to be(true)
  end

  it 'desfaz e devolve o desfecho', :aggregate_failures do
    post "#{rota}/#{execucao.id}/desfazer", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['execucao']['desfeita_em']).to be_present
    expect(account.labels.where(title: 'nova')).to be_empty
  end

  # A execução saiu com a permissão de quem pediu. Outra pessoa não vê nem desfaz.
  it 'não mostra nem desfaz o que foi feito para outra pessoa', :aggregate_failures do
    execucao
    get rota, headers: outro_admin.create_new_auth_token, as: :json
    expect(response.parsed_body['execucoes']).to be_empty

    post "#{rota}/#{execucao.id}/desfazer", headers: outro_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(account.labels.where(title: 'nova')).to exist
  end

  it 'recusa desfazer duas vezes com um motivo legível', :aggregate_failures do
    post "#{rota}/#{execucao.id}/desfazer", headers: admin.create_new_auth_token, as: :json
    post "#{rota}/#{execucao.id}/desfazer", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.guide.undo.already_undone'))
  end
end
