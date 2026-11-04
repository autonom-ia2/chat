require 'rails_helper'

# Ensaiar (#2498): a salva ensaia a versão ativa, o rascunho e a nova mandam a receita no corpo. Pede automation_view;
# receita com problema e gatilho de card voltam em frase; conversa fora do alcance de quem pede é 404.
RSpec.describe 'Api::V1::Accounts::Autonomia::Automacoes ensaio', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:inbox) { create(:inbox, account: account) }
  let!(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:esperar) { { id: 'p1', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } } }
  let(:receita) { { gatilho: { tipo: 'conversa.resolvida' }, passos: [esperar] } }
  let(:automacao) { create(:autonomia_automacao, account: account) }

  before do
    account.enable_features!('automacao_editor')
    automacao.salvar_versao!(receita: receita.deep_stringify_keys, autor: admin)
  end

  def ensaiar(caminho, quem: admin, **corpo)
    post "#{base}/#{caminho}", params: corpo, headers: quem.create_new_auth_token, as: :json
  end

  it 'ensaia a versão ativa nas conversas recentes' do
    ensaiar("#{automacao.id}/ensaio")

    expect(response).to have_http_status(:ok)
    item = response.parsed_body['conversas'].first
    expect(item).to include('conversa_id' => conversa.display_id, 'entraria' => true)
    expect(item['passos'].pluck('id')).to eq(['p1'])
  end

  it 'com receita no corpo, ensaia o rascunho, não a versão salva' do
    ensaiar("#{automacao.id}/ensaio", receita: receita.merge(passos: [esperar.merge(id: 'r1')]))

    expect(response.parsed_body['conversas'].first['passos'].pluck('id')).to eq(['r1'])
  end

  it 'a nova, ainda sem id, ensaia pela coleção' do
    ensaiar('ensaio', receita: receita)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['conversas'].pluck('conversa_id')).to eq([conversa.display_id])
  end

  it 'receita com problema volta 422 com a frase', :aggregate_failures do
    ensaiar('ensaio', receita: receita.merge(passos: [{ id: 'p1', tipo: 'acao', acao: 'DELETE agents/:id', descricao: 'x' }]))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.ensaio.receita_invalida'))
    expect(response.parsed_body['problemas']).to be_present
  end

  it 'sem receita, volta 422 em frase' do
    ensaiar('ensaio')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas']).to eq([I18n.t('autonomia.automacao.ensaio.sem_receita')])
  end

  it 'gatilho de card ainda não ensaia: recusa em frase' do
    allow(Autonomia::Automacao::Receita).to receive(:esquema_valido?).and_return(true)
    allow(Autonomia::Automacao::Receita).to receive(:new).and_return(instance_double(Autonomia::Automacao::Receita, problemas: []))

    ensaiar('ensaio', receita: receita.merge(gatilho: { tipo: 'card.na_etapa' }))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.ensaio.gatilho_de_card'))
  end

  it 'pede automation_view' do
    ensaiar('ensaio', quem: agente, receita: receita)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'conversa fora do alcance de quem pede é 404' do
    funcao = create(:custom_role, account: account, permissions: %w[automation_view conversation_view])
    agente.account_users.find_by(account: account).update!(custom_role: funcao)
    create(:inbox_member, user: agente, inbox: inbox)
    escondida = create(:conversation, account: account, inbox: create(:inbox, account: account))

    ensaiar("#{automacao.id}/ensaio", quem: agente, conversa_id: escondida.display_id)
    expect(response).to have_http_status(:not_found)

    ensaiar("#{automacao.id}/ensaio", quem: agente, conversa_id: conversa.display_id)
    expect(response.parsed_body['conversas'].pluck('conversa_id')).to eq([conversa.display_id])
  end
end
