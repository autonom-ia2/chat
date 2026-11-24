require 'rails_helper'

# #3099: as duas versões da mensagem pelo Histórico da automação. Ver pede automation_view; escolher a versão que fica
# pede automation_manage e vale uma vez só.
RSpec.describe 'Automação livre · duas versões da mensagem', :automacao_motor, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:regra) { { 'criterio' => 'respostas', 'divisao' => 50, 'espera' => 4 } }
  let(:passo) { mensagem_passo('p1', 'Oi').merge('versoes' => regra.merge('texto' => ['Olá'], 'modelo' => nil)) }
  let(:automacao) do
    create(:autonomia_automacao, account: account).tap do |definicao|
      definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }, autor: admin)
    end
  end
  let(:caminho) { "/api/v1/accounts/#{account.id}/autonomia/automacoes/#{automacao.id}/duas_versoes" }

  before { account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_editor', 'automacao_mensagens') }

  def linha = Autonomia::Automacao::VersaoVencedora.find_by!(automacao_id: automacao.id, passo: 'p1')

  describe 'GET duas_versoes' do
    it 'traz cada passo com duas versões, com o estado e os números', :aggregate_failures do
      get caminho, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      passos = response.parsed_body['passos']
      expect(passos.pluck('passo', 'estado', 'criterio', 'espera')).to eq([['p1', 'testando', 'respostas', 4]])
      expect(passos.first['versoes'].pluck('numero', 'receberam')).to eq([[1, 0], [2, 0]])
    end

    it 'não deixa agente sem automation_view ver' do
      get caminho, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'automação de outra conta é 404' do
      outra = create(:account)
      outra.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_editor')
      dono = create(:user, account: outra, role: :administrator)

      get "/api/v1/accounts/#{outra.id}/autonomia/automacoes/#{automacao.id}/duas_versoes", headers: dono.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST duas_versoes/vencedora' do
    it 'grava a versão que fica e responde o bloco do passo', :aggregate_failures do
      post "#{caminho}/vencedora", params: { passo: 'p1', versao: 2 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('passo' => 'p1', 'estado' => 'escolhida', 'vencedora' => 2, 'escolhida_por' => 'voce')
      expect(linha.escolhida_por_user_id).to eq(admin.id)
    end

    it 'a mesma versão de novo responde 200; outra versão responde 422', :aggregate_failures do
      post "#{caminho}/vencedora", params: { passo: 'p1', versao: 2 }, headers: admin.create_new_auth_token, as: :json
      post "#{caminho}/vencedora", params: { passo: 'p1', versao: 2 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      post "#{caminho}/vencedora", params: { passo: 'p1', versao: 1 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.duas_versoes.versao_ja_escolhida'))
      expect(linha.vencedora).to eq(2)
    end

    it 'versão fora de 1 e 2 é 422; passo sem duas versões é 404', :aggregate_failures do
      post "#{caminho}/vencedora", params: { passo: 'p1', versao: 3 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "#{caminho}/vencedora", params: { passo: 'p9', versao: 1 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'não deixa agente sem automation_manage escolher' do
      post "#{caminho}/vencedora", params: { passo: 'p1', versao: 2 }, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(linha.vencedora).to be_nil
    end
  end
end
