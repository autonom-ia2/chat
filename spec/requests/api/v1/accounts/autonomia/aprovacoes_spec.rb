require 'rails_helper'

# #2931: a tela "Pedidos de aprovação" do lado de quem aprova. Cada pessoa vê só os pedidos dela, e só enquanto vê o
# registro; a pergunta sai com os valores pelas permissões de quem olha; vale a primeira resposta; depois do prazo, não.
RSpec.describe 'Api::V1::Accounts::Autonomia::Aprovacoes', :automacao_motor, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:inbox) { create(:inbox, account: account) }
  let(:atendente) { create(:user, account: account, role: :agent, name: 'Bruna') }
  let(:outro) { create(:user, account: account, role: :agent, name: 'Caio') }
  let(:contato) { create(:contact, account: account, name: 'Ana') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato, status: :open) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/aprovacoes" }

  let(:passo) do
    { 'id' => 'aprova', 'tipo' => 'pedir_aprovacao', 'quem' => { 'de' => 'pessoa', 'id' => atendente.id },
      'pergunta' => ['Posso dar desconto para ', { '$valor' => 'contato.nome' }, '?'], 'prazo' => { 'valor' => 1, 'unidade' => 'dias' },
      'aprovado' => [esperar_passo('se_aprovou')] }
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_passos_novos')
    create(:inbox_member, user: atendente, inbox: inbox)
  end

  def pedir
    definicao = automacao_ligada(account, admin, [passo])
    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
    Autonomia::Automacao::Registro.find_by(execucao: execucao, motivo: 'esperando_resposta')
  end

  it 'lista os abertos de quem aprova, com a pergunta montada e a automação', :aggregate_failures do
    pedido = pedir

    get base, headers: atendente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    item = response.parsed_body['pedidos'].sole
    expect(item).to include('id' => pedido.id, 'estado' => 'aberto', 'pergunta' => 'Posso dar desconto para Ana?',
                            'conversa_id' => conversa.display_id)
    expect(item['automacao']).to include('id' => pedido.automacao_id)
  end

  it 'quem não está no pedido não vê nem responde (404)', :aggregate_failures do
    pedido = pedir

    get base, headers: outro.create_new_auth_token, as: :json
    expect(response.parsed_body['pedidos']).to be_empty

    post "#{base}/#{pedido.id}/responder", params: { aprovado: true }, headers: outro.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'quem perdeu o acesso à conversa deixa de ver o pedido' do
    pedido = pedir
    InboxMember.where(user: atendente, inbox: inbox).destroy_all

    get "#{base}/#{pedido.id}", headers: atendente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'aprovar segue a automação; a segunda resposta recebe "já respondido" (409)', :aggregate_failures do
    pedido = pedir

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      post "#{base}/#{pedido.id}/responder", params: { aprovado: true }, headers: atendente.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('estado' => 'aprovado')
    expect(response.parsed_body['decisao']).to include('por_nome' => 'Bruna', 'por_mim' => true)
    expect(Autonomia::Automacao::Registro.where(execucao_id: pedido.execucao_id).pluck(:passo)).to include('se_aprovou')

    post "#{base}/#{pedido.id}/responder", params: { aprovado: false }, headers: atendente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.pedido.responder.ja_respondido', locale: account.locale))
  end

  it 'depois do prazo, a resposta é recusada (422)' do
    pedido = pedir

    travel 25.hours do
      post "#{base}/#{pedido.id}/responder", params: { aprovado: true }, headers: atendente.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'sem a flag dos passos novos, a tela não existe (404)' do
    account.disable_features!('automacao_passos_novos')

    get base, headers: atendente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  describe 'o resumo da pesquisa na lista de automações (#2936)' do
    let(:pesquisa) do
      { 'id' => 'nota', 'tipo' => 'pesquisa_nota', 'pergunta' => 'De 0 a 10?', 'baixa_ate' => 6, 'alta_desde' => 9,
        'intervalo_dias' => 30, 'espera' => { 'valor' => 2, 'unidade' => 'dias' } }
    end

    it 'mostra a média e quantas pessoas responderam, só na automação com a pesquisa', :aggregate_failures do
      account.enable_features!('automacao_editor', 'automacao_mensagens', 'automacao_ia')
      com_pesquisa = automacao_ligada(account, admin, [pesquisa])
      sem_pesquisa = automacao_ligada(account, admin, [esperar_passo('p1')])
      [8, 9].each do |nota|
        create(:contact, account: account, additional_attributes: { 'pesquisas' => { com_pesquisa.id.to_s => { 'nota' => nota } } })
      end

      get "/api/v1/accounts/#{account.id}/autonomia/automacoes", headers: admin.create_new_auth_token, as: :json

      lista = response.parsed_body['automacoes'].index_by { |item| item['id'] }
      expect(lista[com_pesquisa.id]['pesquisa']).to eq('media' => 8.5, 'respostas' => 2)
      expect(lista[sem_pesquisa.id]).not_to have_key('pesquisa')
    end
  end
end
