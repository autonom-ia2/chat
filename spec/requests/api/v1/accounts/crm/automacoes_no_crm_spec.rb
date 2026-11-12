require 'rails_helper'

# #2499 F6.3/F6.5: as automações do motor novo no card ("Automações deste card": o que roda, o que já fez, "Parar para
# este card") e na etapa ("Automações desta etapa"). No OSS, sem função personalizada, só o administrador vê e para.
RSpec.describe 'Api::V1::Accounts::Crm automações no card e na etapa', :automacao_motor, type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:novo) { funil_e_etapa.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: funil, name: 'Proposta', position: 1) }
  let(:card) { account.crm_cards.create!(pipeline: funil, stage: proposta, title: 'Pedido', currency: 'BRL', owner: agente) }
  let(:outro_card) { account.crm_cards.create!(pipeline: funil, stage: proposta, title: 'Outro', currency: 'BRL') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:entrou) { { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => proposta.id } }
  let(:lembrete) do
    definicao = automacao_ligada(account, admin, [esperar_passo('p1', 3), esperar_passo('p2')], gatilho: entrou)
    definicao.update!(nome: 'Lembrete de proposta')
    definicao
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos', 'automacao_editor')
  end

  def abrir(definicao, alvo, estado: 'esperando', cursor: 'p1', due_at: 3.days.from_now)
    Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: alvo,
                                           chave_gatilho: 'card.entrou_na_etapa', estado: estado, cursor: cursor, due_at: due_at)
  end

  def registrar(execucao, passo, resultado = 'ok', dados = {})
    Autonomia::Automacao::Registro.create!(account: account, automacao: execucao.automacao, execucao: execucao, passo: passo, resultado: resultado,
                                           dados: dados)
  end

  describe 'GET cards/:card_id/automacoes' do
    let(:caminho) { "#{base}/cards/#{card.id}/automacoes" }

    it 'diz o que roda no card: o passo, até quando espera, a receita e o que já fez', :aggregate_failures do
      execucao = abrir(lembrete, card)
      registrar(execucao, 'p0')
      registrar(execucao, 'px', 'falhou')
      registrar(execucao, 'p1', 'ok', 'ate' => 3.days.from_now.iso8601)
      abrir(lembrete, outro_card)

      get caminho, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      lista = response.parsed_body['automacoes']
      expect(lista.size).to eq(1)
      item = lista.first
      expect(item).to include('id' => execucao.id, 'automacao_id' => lembrete.id, 'nome' => 'Lembrete de proposta',
                              'estado' => 'esperando', 'passo' => 'p1')
      expect(Time.zone.parse(item['esperando_ate'])).to be_within(1.second).of(execucao.due_at)
      expect(item['receita']['passos'].pluck('id')).to eq(%w[p1 p2])
      # A espera em curso e o passo que falhou não contam como feitos.
      expect(item['feitos'].pluck('passo')).to eq(%w[p0])
    end

    it 'a espera sem prazo sai sem hora' do
      execucao = abrir(lembrete, card)
      registrar(execucao, 'p1', 'ok', 'sem_prazo' => true)

      get caminho, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['automacoes'].first).to include('esperando_ate' => nil, 'esperando_sem_prazo' => true)
    end

    it 'não lista a execução terminada nem a de card fechado', :aggregate_failures do
      abrir(lembrete, card).update!(estado: 'concluida')
      get caminho, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['automacoes']).to eq([])

      abrir(lembrete, card)
      card.update!(status: :won)
      get caminho, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['automacoes']).to eq([])
    end

    it 'agente sem a chave de automação não vê' do
      abrir(lembrete, card)

      get caminho, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'sem os gatilhos de card, a lista não existe' do
      account.disable_features!('automacao_gatilhos')

      get caminho, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'card de outra conta é 404, mesmo para quem administra as duas' do
      outra = create(:account)
      create(:account_user, account: outra, user: admin, role: :administrator)
      ligar_motor(outra)
      outra.enable_features!('automacao_gatilhos')

      get "/api/v1/accounts/#{outra.id}/crm/cards/#{card.id}/automacoes", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST cards/:card_id/automacoes/:id/parar' do
    let(:caminho) { "#{base}/cards/#{card.id}/automacoes/#{lembrete.id}/parar" }

    it 'para só neste card: os outros cards seguem e a automação continua ligada', :aggregate_failures do
      aqui = abrir(lembrete, card)
      la = abrir(lembrete, outro_card)

      post caminho, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['paradas']).to eq(1)
      expect(aqui.reload).to have_attributes(estado: 'parada', finalizada_em: be_present)
      expect(la.reload.estado).to eq('esperando')
      expect(lembrete.reload.ativa).to be(true)
      expect(Autonomia::Automacao::Registro.find_by(execucao: aqui)).to have_attributes(passo: 'p1', resultado: 'pulado', motivo: 'parada_no_card')
    end

    it 'para também a outra vez dela que rodava junto no card, e não mexe nas de outra automação', :aggregate_failures do
      primeira = abrir(lembrete, card)
      paralela = Autonomia::Automacao::Execucao.create!(account: account, automacao: lembrete, versao: lembrete.versao_ativa, alvo: card,
                                                        chave_gatilho: 'card.entrou_na_etapa', estado: 'esperando', cursor: 'p1', paralela: true)
      outra = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: entrou)
      dela = abrir(outra, card)

      post caminho, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['paradas']).to eq(2)
      expect([primeira, paralela].map { |execucao| execucao.reload.estado }).to eq(%w[parada parada])
      expect(dela.reload.estado).to eq('esperando')
    end

    it 'sem nada rodando, responde zero' do
      post caminho, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['paradas']).to eq(0)
    end

    it 'agente sem a chave de automação não para', :aggregate_failures do
      execucao = abrir(lembrete, card)

      post caminho, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'automação de outra conta é 404' do
      outra = create(:account)
      estranha = create(:autonomia_automacao, account: outra)

      post "#{base}/cards/#{card.id}/automacoes/#{estranha.id}/parar", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'parar funciona mesmo com os gatilhos de card desligados (como o desligar)' do
      execucao = abrir(lembrete, card)
      account.disable_features!('automacao_gatilhos')

      post caminho, headers: admin.create_new_auth_token, as: :json

      expect(execucao.reload.estado).to eq('parada')
    end
  end

  describe 'GET stages/:stage_id/automacoes' do
    let(:caminho) { "#{base}/stages/#{proposta.id}/automacoes" }

    it 'lista as automações com gatilho nesta etapa, ligadas e desligadas, e nenhuma outra', :aggregate_failures do
      lembrete
      saiu = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.saiu_da_etapa', 'etapa_id' => proposta.id })
      parado = automacao_ligada(account, admin, [esperar_passo('p1')],
                                gatilho: { 'tipo' => 'card.parado', 'etapa_id' => proposta.id, 'dias' => 5 })
      parado.desligar!
      automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => novo.id })
      automacao_ligada(account, admin, [esperar_passo('p1')])

      get caminho, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      lista = response.parsed_body['automacoes']
      expect(lista.pluck('id')).to eq([lembrete.id, saiu.id, parado.id])
      expect(lista.last).to include('ativa' => false)
      expect(lista.first['versao']).to include('id' => lembrete.versao_ativa_id)
      expect(lista.first['versao']['receita']['gatilho']).to eq(entrou)
    end

    it 'agente sem as chaves não vê' do
      get caminho, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'etapa de outra conta é 404' do
      outra = create(:account)
      outro_funil = create_crm_pipeline(account: outra, user: create(:user, account: outra, role: :administrator))

      get "#{base}/stages/#{outro_funil.last.id}/automacoes", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
