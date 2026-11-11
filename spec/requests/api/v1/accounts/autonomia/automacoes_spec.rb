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

  it 'lista cada automação com a receita, para a frase da lista' do
    criar

    get base, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    lista = response.parsed_body['automacoes']
    expect(lista.pluck('nome')).to eq(['Lembrete'])
    expect(lista.first.dig('versao', 'receita', 'gatilho', 'tipo')).to eq('conversa.resolvida')
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

  # #2486: o editor esconde mensagem e avisar sem a flag da F4, mas a API é quem recusa. Quem chama direto não passa.
  it 'pela API, sem a flag da F4, recusa mensagem e avisar ao criar e ao salvar', :aggregate_failures do
    mensagem = { id: 'p2', tipo: 'mensagem', texto: ['Oi ', { '$valor' => 'contato.nome' }] }
    avisar = { id: 'p3', tipo: 'avisar', texto: ['Olhe esta'], para: { responsavel: true } }
    com_f4 = receita.merge(passos: receita[:passos] + [mensagem, avisar])

    expect { criar(com: com_f4) }.not_to change(Autonomia::Automacao::Definicao, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas']).to include(
      I18n.t('autonomia.automacao.receita.passo_desligado', passo: 'p2'),
      I18n.t('autonomia.automacao.receita.passo_desligado', passo: 'p3')
    )

    criar
    id = response.parsed_body['id']
    patch "#{base}/#{id}", params: { receita: com_f4, base_versao_id: versao_id_de(id) }, headers: admin.create_new_auth_token,
                           as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Autonomia::Automacao::Definicao.find(id).versao_ativa.numero).to eq(1)
  end

  # #2500 F7: sem a flag da F7, o servidor recusa passo de IA ao criar e ao salvar, venha do editor ou de quem chama a
  # API direto. O Guia chama esta mesma rota pela ChamadaInterna (spec próprio em guide/).
  it 'pela API, sem a flag da F7, recusa passo de IA ao criar e ao salvar', :aggregate_failures do
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens')
    resumir = { id: 'p2', tipo: 'resumir', le: ['mensagens_recentes'], linhas: 3, destino: 'nota' }
    com_ia = receita.merge(passos: receita[:passos] + [resumir])

    expect { criar(com: com_ia) }.not_to change(Autonomia::Automacao::Definicao, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas']).to include(I18n.t('autonomia.automacao.receita.ia_desligada', passo: 'p2'))

    criar
    id = response.parsed_body['id']
    patch "#{base}/#{id}", params: { receita: com_ia, base_versao_id: versao_id_de(id) }, headers: admin.create_new_auth_token,
                           as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Autonomia::Automacao::Definicao.find(id).versao_ativa.numero).to eq(1)

    account.enable_features!('automacao_ia')
    criar(com: com_ia)
    expect(response).to have_http_status(:created)
  end

  # #2486: o dado de um campo que a conta apagou continua {$valor} na receita; o salvar recusa com a frase, e a tela a
  # mostra. Nunca vira texto literal para o cliente.
  it 'com a F4 ligada, recusa texto com campo personalizado que a conta não tem' do
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens')
    mensagem = { id: 'p2', tipo: 'mensagem', texto: ['Placa: ', { '$valor' => 'contato.atributos.placa' }] }

    criar(com: receita.merge(passos: receita[:passos] + [mensagem]))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas']).to include(
      I18n.t('autonomia.automacao.receita.atributo_inexistente', passo: 'p2', caminho: 'contato.atributos.placa')
    )
  end

  # #2496: o editor só oferece as opções do valor fechado; quem chama direto (o Guia) também não grava a que nunca casa.
  it 'recusa ao criar e ao salvar a condição da mensagem com valor ou operador que ela não tem', :aggregate_failures do
    filtro = { campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }
    de_mensagem = ->(*filtros) { receita.merge(gatilho: { tipo: 'mensagem.criada', filtros: filtros }) }

    criar(com: de_mensagem.call(filtro.merge(valor: 'open')))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas']).to include(
      I18n.t('autonomia.automacao.receita.valor_fora', passo: 'gatilho', caminho: 'mensagem.tipo', valor: 'open',
                                                       opcoes: 'recebida, enviada, nota')
    )

    criar(com: de_mensagem.call(filtro))
    id = response.parsed_body['id']
    patch "#{base}/#{id}", params: { receita: de_mensagem.call(filtro.merge(op: 'contem')), base_versao_id: versao_id_de(id) },
                           headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas']).to include(
      I18n.t('autonomia.automacao.receita.operador_fora', passo: 'gatilho', caminho: 'mensagem.tipo', operadores: 'igual, diferente')
    )
    expect(Autonomia::Automacao::Definicao.find(id).versao_ativa.numero).to eq(1)
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

  it 'liga como quem fez o pedido, mesmo com outro user_id no corpo (parecer do Funções no #2476)' do
    outro = create(:user, account: account, role: :administrator)
    criar
    id = response.parsed_body['id']

    post "#{base}/#{id}/ligar", params: { versao_id: versao_id_de(id), user_id: outro.id, ligada_por_id: outro.id },
                                headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ligada_por', 'id')).to eq(admin.id)
    expect(Autonomia::Automacao::Definicao.find(id).ligada_por_id).to eq(admin.id)
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

    it 'lê a versão vista sempre na base 10 (🟡3 da qualidade no #2485)' do
      controlador = Api::V1::Accounts::Autonomia::AutomacoesController.new
      # #2889: recebe o valor lido pelo nome (params[:versao_id]), para o formato do Guia ver o campo.
      vista = ->(valor) { controlador.send(:versao_vista, valor) }

      expect(vista.call('012')).to eq(12)
      expect(vista.call('0x1f')).to be_nil
      expect(vista.call(12)).to eq(12)
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

  it 'recusa pela API trocar a lista inteira de etiquetas da conversa (fora), e aceita mudar a etiqueta da conta' do
    etiqueta = create(:label, account: account)
    fora = { id: 'p1', tipo: 'acao', acao: 'POST conversations/:conversation_id/labels', descricao: 'x',
             caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { labels: ['vip'] } }
    criar(com: receita.merge(passos: [fora]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['problemas'].join).to include('POST conversations/:conversation_id/labels')

    permitida = { id: 'p1', tipo: 'acao', acao: 'PUT labels/:id', descricao: 'Mudar a descrição da etiqueta',
                  caminho: { id: etiqueta.id }, corpo: { description: 'Revisada' } }
    criar(com: receita.merge(passos: [permitida]))
    expect(response).to have_http_status(:created)
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

    # G3 (#2629): o retorno cria pelo crm/follow_ups e pede a mesma chave.
    it 'recusa salvar o passo "criar retorno" pela API direta' do
      retorno = { id: 'r1', tipo: 'retorno', titulo: ['Ligar'], daqui: { valor: 1, unidade: 'dias' } }

      post base, params: { nome: 'x', receita: receita.merge(passos: [retorno]) }, headers: montador.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
    end

    # #2499: o gatilho de card também pede a chave de funis, mesmo sem passo de card.
    it 'recusa salvar gatilho de card pela API direta' do
      account.enable_features!('automacao_gatilhos')
      receita_de_card = receita.merge(gatilho: { tipo: 'card.ganho' })

      post base, params: { nome: 'x', receita: receita_de_card }, headers: montador.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
    end

    # #2716: ler o card a partir da conversa pede a mesma chave do gatilho de card.
    it 'automação de conversa que lê o card no "Só se": recusa sem a chave de funis, aceita com ela', :aggregate_failures do
      filtro = [{ campo: { '$valor' => 'card.etapa_id' }, op: 'igual', valor: 1 }]
      le_o_card = receita.merge(gatilho: { tipo: 'conversa.criada', filtros: filtro })

      post base, params: { nome: 'x', receita: le_o_card }, headers: montador.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
      montador.account_users.find_by(account: account).custom_role.update!(permissions: %w[automation_manage crm_manage_pipelines])
      post base, params: { nome: 'x', receita: le_o_card }, headers: montador.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
    end

    # Decisão 19 (#2716): a âncora do "em outro registro" e origem.card.* no ramo leem o card da conversa: pedem a chave.
    it 'automação de conversa cuja âncora ou ramo lê o card: recusa sem a chave de funis', :aggregate_failures do
      ramo = lambda do |registro, passos|
        [{ id: 'o1', tipo: 'em_outro_registro', registro: registro, passos: passos }]
      end
      ancora = { de: 'contato_do_campo', campo: { '$valor' => 'card.atributos.indicado_por' }, usar: 'contato' }
      se_aberto = { id: 's1', tipo: 'se', condicao: { campo: { '$valor' => 'origem.card.status' }, op: 'igual', valor: 'open' },
                    entao: [receita[:passos].first], senao: [] }
      no_contato = { de: 'contato_do_campo', campo: { '$valor' => 'contato.atributos.x' }, usar: 'contato' }
      receitas = [ramo.call(ancora, [receita[:passos].first]), ramo.call(no_contato, [se_aberto])]
                 .map { |passos| { gatilho: { tipo: 'conversa.criada' }, passos: passos } }

      receitas.each do |le_o_card|
        post base, params: { nome: 'x', receita: le_o_card }, headers: montador.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
      end
      montador.account_users.find_by(account: account).custom_role.update!(permissions: %w[automation_manage crm_manage_pipelines])
      receitas.each do |le_o_card|
        post base, params: { nome: 'x', receita: le_o_card }, headers: montador.create_new_auth_token, as: :json
        expect(response.parsed_body['error']).not_to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
      end
    end

    # G4: o passo "criar card" é passo de funil, como a ação de card.
    it 'recusa salvar o passo "criar card" pela API direta' do
      account.enable_features!('automacao_gatilhos')
      _, etapa = create_crm_pipeline(account: account, user: admin)
      criar_card = { id: 'p1', tipo: 'card', etapa_id: etapa.id }

      post base, params: { nome: 'x', receita: receita.merge(passos: [criar_card]) }, headers: montador.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
    end

    # Parecer da Funções (#2859): a prospecção cria card, e é passo de funil como o "criar card".
    it 'recusa salvar o passo "prospecção" sem a chave de funis, mesmo com a chave da Prospecção' do
      Autonomia::Prospecting::Config.enable_for!(account)
      montador.account_users.find_by(account: account).custom_role.update!(permissions: %w[automation_manage prospecting_manage])
      prospeccao = { id: 'r1', tipo: 'prospeccao', faz: 'recusar' }

      post base, params: { nome: 'x', receita: receita.merge(passos: [prospeccao]) }, headers: montador.create_new_auth_token, as: :json

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

    # F7 (#2500): a chave de funis anda pelos caminhos e pelo "nenhum" do decidir, pela travessia única da Receita.
    it 'recusa passo de card dentro de um caminho ou do nenhum do decidir (travessia única)', :aggregate_failures do
      account.enable_features!('automacao_ia')
      caminho = ->(chave, passos) { { nome: chave, chave: chave, descricao: chave, passos: passos } }
      decidir = { id: 'd1', tipo: 'decidir', pergunta: 'assunto?', caminhos: [caminho.call('a', []), caminho.call('b', [])] }
      no_caminho = decidir.merge(caminhos: [caminho.call('a', [passo_de_card]), caminho.call('b', [])])
      no_nenhum = decidir.merge(nenhum: [passo_de_card])

      [no_caminho, no_nenhum].each do |passo|
        post base, params: { nome: 'x', receita: receita.merge(passos: [passo]) }, headers: montador.create_new_auth_token,
                   as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('autonomia.automacao.editor.sem_funil'))
      end
    end

    it 'aceita passo de card de quem tem crm_admin sem crm_manage_pipelines (mesmas chaves da regra do funil)' do
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_admin])
      montador.account_users.find_by(account: account).update!(custom_role: funcao)

      post base, params: { nome: 'x', receita: receita.merge(passos: [passo_de_card]) }, headers: montador.create_new_auth_token,
                 as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe 'o que aconteceu (#2498)' do
    let(:automacao) { create(:autonomia_automacao, account: account) }
    let(:versao) { create(:autonomia_automacao_versao, automacao: automacao) }

    before do
      execucao = create(:autonomia_automacao_execucao, versao: versao, estado: 'parada',
                                                       alvo: create(:conversation, account: account))
      create(:autonomia_automacao_registro, execucao: execucao, resultado: 'pulado', motivo: 'spam')
    end

    it 'mostra as execuções com os passos a quem pode ver a automação', :aggregate_failures do
      get "#{base}/#{automacao.id}/historico", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      passo = response.parsed_body['execucoes'].first['passos'].first
      expect(passo).to include('resultado' => 'pulado', 'motivo' => I18n.t('autonomia.automacao.motivos.spam'))
      expect(response.parsed_body['versoes'].keys).to eq([versao.id.to_s])
    end

    it 'a receita de versoes sai igual à do show' do
      automacao.update!(versao_ativa: versao)

      get "#{base}/#{automacao.id}", headers: admin.create_new_auth_token, as: :json
      do_show = response.parsed_body.dig('versao', 'receita')
      get "#{base}/#{automacao.id}/historico", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('versoes', versao.id.to_s, 'receita')).to eq(do_show)
    end

    it 'recusa quem não tem automation_view e esconde a de outra conta', :aggregate_failures do
      get "#{base}/#{automacao.id}/historico", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      de_fora = create(:autonomia_automacao)
      get "#{base}/#{de_fora.id}/historico", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'deixa ver com a função que só tem automation_view' do
      leitor = create(:user, account: account, role: :agent)
      funcao = create(:custom_role, account: account, permissions: %w[automation_view])
      leitor.account_users.find_by(account: account).update!(custom_role: funcao)

      get "#{base}/#{automacao.id}/historico", headers: leitor.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
    end

    describe 'o custo da IA em dinheiro (#2557)' do
      def dados_da_ia(quem)
        get "#{base}/#{automacao.id}/historico", headers: quem.create_new_auth_token, as: :json
        response.parsed_body['execucoes'].first['passos'].find { |passo| passo['passo'] == 'p_ia' }.dig('dados', 'ia')
      end

      def com_funcao(permissoes)
        create(:user, account: account, role: :agent).tap do |pessoa|
          funcao = create(:custom_role, account: account, permissions: permissoes)
          pessoa.account_users.find_by(account: account).update!(custom_role: funcao)
        end
      end

      before do
        execucao = automacao.execucoes.first
        create(:autonomia_automacao_registro, execucao: execucao, passo: 'p_ia', resultado: 'ok',
                                              dados: { 'ia' => { 'custo_usd' => 0.002, 'modelo' => 'm', 'tokens_saida' => 30 } })
      end

      it 'nem o custo nem os tokens saem para quem só tem automation_view' do
        expect(dados_da_ia(com_funcao(%w[automation_view]))).to eq('modelo' => 'm')
      end

      it 'sai para o administrador e para a função com financial_view', :aggregate_failures do
        expect(dados_da_ia(admin)).to eq('custo_usd' => 0.002, 'modelo' => 'm', 'tokens_saida' => 30)
        expect(dados_da_ia(com_funcao(%w[automation_view financial_view]))).to eq('custo_usd' => 0.002, 'modelo' => 'm', 'tokens_saida' => 30)
      end
    end

    it 'a lista leva o fato da semana de cada automação' do
      get base, headers: admin.create_new_auth_token, as: :json

      linha = response.parsed_body['automacoes'].find { |item| item['id'] == automacao.id }
      expect(linha['semana']).to eq('rodou' => 1, 'parou' => 1)
    end
  end
end
