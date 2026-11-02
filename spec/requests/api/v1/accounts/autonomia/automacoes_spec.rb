require 'rails_helper'

# O editor da Automação livre (#2414 F5): catálogo, lista, criar, salvar versão, ligar e desligar.
RSpec.describe 'Api::V1::Accounts::Autonomia::Automacoes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:receita) do
    { gatilho: { tipo: 'conversa.resolvida' },
      passos: [{ id: 'p1', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } }] }
  end

  before { account.enable_features!('automacao_editor') }

  def criar(nome: 'Lembrete', com: receita)
    post base, params: { nome: nome, receita: com }, headers: admin.create_new_auth_token, as: :json
  end

  def ligar(id, versao_id, quem: admin)
    post "#{base}/#{id}/ligar", params: { versao_id: versao_id }, headers: quem.create_new_auth_token, as: :json
  end

  def versao_id_de(id)
    Autonomia::Automacao::Definicao.find(id).versao_ativa_id
  end

  it 'esconde tudo quando a conta não tem a flag' do
    account.disable_features!('automacao_editor')

    get base, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'não deixa agente sem automation_view ver nem montar' do
    get base, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    post base, params: { nome: 'x', receita: receita }, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'entrega o catálogo de passos que o editor lê' do
    get "#{base}/passos", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['passos'].pluck('tipo')).to include('esperar', 'se', 'acao')
    expect(response.parsed_body['gatilhos'].pluck('tipo')).to include('conversa.criada')
  end

  it 'cria a automação desligada, de origem manual, com a v1' do
    criar

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('nome' => 'Lembrete', 'ativa' => false, 'origem' => 'manual')
    expect(response.parsed_body.dig('versao', 'numero')).to eq(1)
    expect(Autonomia::Automacao::Definicao.find(response.parsed_body['id']).versao_ativa.autor).to eq(admin)
  end

  it 'recusa receita com problema, em frase, e não deixa automação pela metade' do
    ruim = receita.merge(passos: [{ id: 'p1', tipo: 'acao', acao: 'DELETE agents/:id', descricao: 'x' }])

    expect { criar(com: ruim) }.not_to change(Autonomia::Automacao::Definicao, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas']).to be_present
  end

  it 'salvar de novo cria a v2 e a v1 não muda' do
    criar
    id = response.parsed_body['id']
    v1 = Autonomia::Automacao::Definicao.find(id).versao_ativa
    nova = receita.merge(gatilho: { tipo: 'conversa.criada' })

    patch "#{base}/#{id}", params: { receita: nova, base_versao_id: v1.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('versao', 'numero')).to eq(2)
    expect(response.parsed_body.dig('versao', 'receita', 'gatilho', 'tipo')).to eq('conversa.criada')
    expect(v1.reload.receita.dig('gatilho', 'tipo')).to eq('conversa.resolvida')
  end

  it 'liga como quem pediu e desliga' do
    criar
    id = response.parsed_body['id']

    ligar(id, versao_id_de(id))
    expect(response.parsed_body).to include('ativa' => true)
    expect(response.parsed_body.dig('ligada_por', 'id')).to eq(admin.id)

    post "#{base}/#{id}/desligar", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('ativa' => false)
  end

  describe 'versão que a tela viu (🔴1, 🟠2 e 🟠3 da qualidade)' do
    let(:outro) { create(:user, account: account, role: :administrator) }
    let(:id) do
      criar
      response.parsed_body['id']
    end

    it 'não liga a versão que outra pessoa salvou depois da que a tela mostrou' do
      vista = versao_id_de(id)
      Autonomia::Automacao::Definicao.find(id).salvar_versao!(receita: receita.deep_stringify_keys, autor: outro)

      ligar(id, vista)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.versao_mudou'))
      expect(Autonomia::Automacao::Definicao.find(id).ativa).to be(false)
    end

    it 'aceita a versão vista em texto' do
      vista = versao_id_de(id).to_s

      patch "#{base}/#{id}", params: { receita: receita, base_versao_id: vista }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      ligar(id, versao_id_de(id).to_s)
      expect(response).to have_http_status(:ok)
      expect(Autonomia::Automacao::Definicao.find(id).ativa).to be(true)
    end

    it 'trata versão vista que não é número como versão que mudou' do
      ligar(id, "#{versao_id_de(id)}abc")

      expect(response).to have_http_status(:conflict)
    end

    it 'não liga sem dizer qual versão viu' do
      ligar(id, nil)

      expect(response).to have_http_status(:conflict)
    end

    it 'não salva por cima de versão que não viu, nem sem dizer a base' do
      vista = versao_id_de(id)
      Autonomia::Automacao::Definicao.find(id).salvar_versao!(receita: receita.deep_stringify_keys, autor: outro)

      patch "#{base}/#{id}", params: { receita: receita, base_versao_id: vista }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)

      patch "#{base}/#{id}", params: { receita: receita }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)
      expect(Autonomia::Automacao::Definicao.find(id).versoes.count).to eq(2)
    end

    it 'confere a receita de novo ao ligar e devolve as frases' do
      create(:custom_attribute_definition, account: account, attribute_key: 'placa', attribute_model: 'conversation_attribute')
      com_atributo = receita.merge(gatilho: { tipo: 'conversa.resolvida',
                                              filtros: [{ campo: { '$valor' => 'conversa.atributos.placa' }, op: 'preenchido' }] })
      criar(com: com_atributo)
      novo = response.parsed_body['id']
      account.custom_attribute_definitions.find_by(attribute_key: 'placa').destroy!

      ligar(novo, versao_id_de(novo))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.motivos.receita_com_problema'))
      expect(response.parsed_body['problemas'].join).to include('placa')
    end

    it 'não liga automação sem versão' do
      vazia = create(:autonomia_automacao, account: account)

      ligar(vazia.id, nil)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.motivos.sem_versao'))
    end
  end

  it 'não abre, salva, liga nem desliga automação de outra conta' do
    alheia = create(:autonomia_automacao)
    cabecalho = admin.create_new_auth_token

    get "#{base}/#{alheia.id}", headers: cabecalho, as: :json
    expect(response).to have_http_status(:not_found)
    patch "#{base}/#{alheia.id}", params: { nome: 'x' }, headers: cabecalho, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{base}/#{alheia.id}/ligar", headers: cabecalho, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{base}/#{alheia.id}/desligar", headers: cabecalho, as: :json
    expect(response).to have_http_status(:not_found)
    expect(alheia.reload.nome).not_to eq('x')
  end

  it 'desliga mesmo com a flag desligada depois (D7)' do
    criar
    id = response.parsed_body['id']
    ligar(id, versao_id_de(id))
    account.disable_features!('automacao_editor')

    post "#{base}/#{id}/desligar", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(Autonomia::Automacao::Definicao.find(id).ativa).to be(false)
  end

  it 'recusa ação fora da lista pela API, com a frase (DELETE de etapa)' do
    ruim = receita.merge(passos: [{ id: 'p1', tipo: 'acao', acao: 'DELETE crm/stages/:id', descricao: 'x', caminho: { id: 1 } }])

    criar(com: ruim)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas'].join).to include('DELETE crm/stages/:id')
  end

  it 'guarda idêntico o passo que o editor não sabe mostrar' do
    etiqueta = create(:label, account: account)
    avancado = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'PUT labels/:id', 'descricao' => 'Renomear',
                 'caminho' => { 'id' => etiqueta.id }, 'corpo' => { 'title' => 'renomeada' } }
    criar
    id = response.parsed_body['id']

    patch "#{base}/#{id}", params: { receita: receita.merge(passos: [avancado]), base_versao_id: versao_id_de(id) },
                           headers: admin.create_new_auth_token, as: :json
    get "#{base}/#{id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body.dig('versao', 'receita', 'passos')).to eq([avancado])
  end

  it 'não devolve nome de coisa de outra conta que a receita cite' do
    alheia = create(:label, title: 'etiqueta_de_outra_conta')
    passo = { id: 'p1', tipo: 'acao', acao: 'PATCH labels/:id', descricao: 'x', caminho: { id: alheia.id }, corpo: { show_on_sidebar: true } }
    criar(com: receita.merge(passos: [passo]))
    expect(response).to have_http_status(:created)

    get "#{base}/#{response.parsed_body['id']}", headers: admin.create_new_auth_token, as: :json

    expect(response.body).not_to include('etiqueta_de_outra_conta')
  end

  context 'when a função monta automação mas não gerencia funis' do
    let(:montador) { create(:user, account: account, role: :agent) }
    let(:passo_de_card) do
      { id: 'p1', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Mover', caminho: { id: 1 }, corpo: { stage_id: 1 } }
    end

    before do
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage])
      montador.account_users.find_by(account: account).update!(custom_role: funcao)
    end

    it 'recusa salvar passo de card pela API direta (D2)' do
      post base, params: { nome: 'x', receita: receita.merge(passos: [passo_de_card]) }, headers: montador.create_new_auth_token,
                 as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
    end

    it 'recusa salvar por cima com passo de card, e confere a versão antes' do
      automacao = create(:autonomia_automacao, account: account)
      automacao.salvar_versao!(receita: receita.deep_stringify_keys, autor: admin)
      com_card = receita.merge(passos: [passo_de_card])
      cabecalho = montador.create_new_auth_token

      patch "#{base}/#{automacao.id}", params: { receita: com_card, base_versao_id: 0 }, headers: cabecalho, as: :json
      expect(response).to have_http_status(:conflict)

      patch "#{base}/#{automacao.id}", params: { receita: com_card, base_versao_id: automacao.versao_ativa_id },
                                       headers: cabecalho, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
      expect(automacao.versoes.count).to eq(1)
    end

    it 'devolve 422 em frase, não 500, para receita fora do formato' do
      post base, params: { nome: 'x', receita: { gatilho: { tipo: 'conversa.criada' }, passos: [nil, 5] } },
                 headers: montador.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end

    it 'recusa ligar automação com passo de card' do
      automacao = create(:autonomia_automacao, account: account)
      versao = create(:autonomia_automacao_versao, automacao: automacao, numero: 1)
      automacao.update_columns(versao_ativa_id: versao.id) # rubocop:disable Rails/SkipsModelValidations
      Autonomia::Automacao::Versao.where(id: versao.id)
                                  .update_all(receita: receita.merge(passos: [passo_de_card]).deep_stringify_keys) # rubocop:disable Rails/SkipsModelValidations

      ligar(automacao.id, versao.id, quem: montador)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(automacao.reload.ativa).to be(false)
    end
  end
end
