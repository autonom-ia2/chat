require 'rails_helper'

# F3 do tema 8 (#1429): a API da linha "Base de seguros". GET para quem vê (autonomia_view), POST para quem gerencia
# (autonomia_manage). Sem a Fase 2, na Lia e no Guia, 404. O texto da base nunca sai.
RSpec.describe 'Base de seguros do agente (#1429 F3)', type: :request do
  let(:conta) { conta_da_fase2 }
  let(:admin) { create(:user, account: conta, role: :administrator) }
  let(:so_ve) { usuario_com_funcao(%w[autonomia_view]) }
  let(:gerencia) { usuario_com_funcao(%w[autonomia_manage]) }
  let(:bloco) { Autonomia::Segmentos::Bloco }
  let(:seguradora) do
    { 'segmento' => 'seguros/seguradora', 'versao' => bloco.versao('seguros/seguradora'), 'texto' => bloco.for_segmento('seguros/seguradora') }
  end
  let(:agente) { criar_principal(conta, config: { 'with_knowledge' => false, 'base' => seguradora }) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true') { example.run } }

  before do
    nicho = Autonomia::Agents::Nicho
    conta.update!(internal_attributes: conta.internal_attributes.to_h.merge(nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => 'corretora'))
    Autonomia::Agents::BaseDeSeguros::Limite.liberar!(agente)
    Redis::Alfred.delete(Autonomia::Agents::BaseDeSeguros::Limite.chave_da_conta(conta))
  end

  def usuario_com_funcao(permissoes)
    usuario = create(:user, account: conta, role: :agent)
    funcao = create(:custom_role, account: conta, permissions: permissoes)
    usuario.account_users.find_by(account: conta).update!(custom_role: funcao)
    usuario
  end

  # O antes e depois desta pessoa terminou (o que a Comparacao grava ao fim do job).
  def comparou(usuario = admin, versao: bloco.versao('seguros/corretora'))
    Autonomia::Agents::BaseDeSeguros::Comparada.marcar_quem_viu!(agente, usuario.account_users.find_by(account: conta), versao)
  end

  def caminho(acao = nil, agent: agente)
    ["/api/v1/accounts/#{conta.id}/autonomia/agents/#{agent.id}/base", acao].compact.join('/')
  end

  def pedir(metodo, acao = nil, usuario: admin, params: {}, agent: agente)
    send(metodo, caminho(acao, agent: agent), headers: usuario.create_new_auth_token, params: params, as: :json)
  end

  describe 'GET base' do
    it 'mostra a situação para quem só vê, sem o texto da base' do
      pedir(:get, usuario: so_ve)

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body
      expect(corpo['situacao']).to eq('conta_mudou')
      expect(corpo.dig('atual', 'segmento')).to eq('seguros/seguradora')
      expect(corpo.dig('nova', 'segmento')).to eq('seguros/corretora')
      expect(corpo.dig('nova', 'data')).to eq(bloco.data_da_versao('seguros/corretora', bloco.versao('seguros/corretora')).iso8601)
      expect(response.body).not_to include(bloco.for_segmento('seguros/seguradora'))
      expect(response.body).not_to include(bloco.for_segmento('seguros/corretora'))
    end

    it 'conta geral e agente sem base: situação nula (a linha não aparece)' do
      nicho = Autonomia::Agents::Nicho
      conta.update!(internal_attributes: conta.internal_attributes.to_h.except(nicho::NICHO_KEY, nicho::PERFIL_KEY))
      sem_base = criar_principal(conta, nome: 'Sem base')

      pedir(:get, agent: sem_base)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['situacao']).to be_nil
    end
  end

  describe 'portas fechadas' do
    it 'sem a Fase 2, 404 em tudo' do
      Autonomia::Agents::Fase2.desligar!(conta)

      [[:get, nil], [:post, 'comparar'], [:post, 'atualizar'], [:post, 'desfazer']].each do |metodo, acao|
        pedir(metodo, acao)
        expect(response).to have_http_status(:not_found), "#{metodo} #{acao}"
      end
    end

    it 'a Lia não tem base: 404 nas 4 ações, sem gastar o limite' do
      lia = Autonomia::Agents::Agent.create!(account: conta, name: 'Lia', agent_type: 'insurance_quote', instruction: 'Cotação.',
                                             config: { 'with_knowledge' => false })

      [[:get, nil], [:post, 'comparar'], [:post, 'atualizar'], [:post, 'desfazer']].each do |metodo, acao|
        pedir(metodo, acao, agent: lia, params: { versao: bloco.versao('seguros/corretora') })
        expect(response).to have_http_status(:not_found), "#{metodo} #{acao}"
      end
      expect(Redis::Alfred.get(Autonomia::Agents::BaseDeSeguros::Limite.chave_da_conta(conta))).to be_nil
      expect(lia.reload.config).not_to have_key('base')
    end

    it 'o Guia (system_key) não existe para esta API: 404' do
      guia = criar_principal(conta, nome: 'Guia', config: { 'with_knowledge' => false, 'system_key' => 'guia' })

      pedir(:get, agent: guia)

      expect(response).to have_http_status(:not_found)
    end

    it 'agente de outra conta: 404' do
      de_fora = criar_principal(conta_da_fase2, nome: 'De fora')

      pedir(:get, agent: de_fora)

      expect(response).to have_http_status(:not_found)
    end

    it 'quem só vê não compara, não atualiza nem desfaz' do
      %w[comparar atualizar desfazer].each do |acao|
        pedir(:post, acao, usuario: so_ve)
        expect(response).to have_http_status(:unauthorized), acao
      end
      expect(agente.reload.config['base']).to eq(seguradora)
    end
  end

  describe 'POST base/atualizar e base/desfazer' do
    it 'quem gerencia atualiza depois de comparar: só a base muda, e o Desfazer aparece' do
      comparou(gerencia)
      pedir(:post, 'atualizar', usuario: gerencia, params: { versao: bloco.versao('seguros/corretora') })

      expect(response).to have_http_status(:ok)
      expect(agente.reload.config.dig('base', 'segmento')).to eq('seguros/corretora')
      expect(agente.config.dig('base', 'texto')).to eq(bloco.for_segmento('seguros/corretora'))
      corpo = response.parsed_body
      expect(corpo['situacao']).to eq('em_dia')
      expect(corpo.dig('desfazer', 'anterior', 'segmento')).to eq('seguros/seguradora')
      expect(response.body).not_to include(bloco.for_segmento('seguros/corretora'))
    end

    # O antes e depois é exigido pelo servidor: nem o Guia nem a API trocam a base sem ele.
    it 'sem comparar antes: 422 (comparar_antes) e nada muda' do
      pedir(:post, 'atualizar', params: { versao: bloco.versao('seguros/corretora') })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('comparar_antes')
      expect(agente.reload.config['base']).to eq(seguradora)
    end

    it 'a comparação de outra pessoa não vale: 422 e nada muda' do
      comparou(gerencia)
      pedir(:post, 'atualizar', params: { versao: bloco.versao('seguros/corretora') })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('comparar_antes')
      expect(agente.reload.config['base']).to eq(seguradora)
    end

    it 'a comparação de outra versão não vale: 422 e nada muda' do
      comparou(versao: 'outra0000000')
      pedir(:post, 'atualizar', params: { versao: bloco.versao('seguros/corretora') })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('comparar_antes')
    end

    it 'agente sem instrução: 422 com o motivo próprio (sem_instrucao), no comparar e no atualizar' do
      sem_instrucao = criar_principal(conta, nome: 'Sem instrução', instruction: nil, config: { 'with_knowledge' => false })

      %w[comparar atualizar].each do |acao|
        pedir(:post, acao, agent: sem_instrucao, params: { versao: bloco.versao('seguros/corretora') })
        expect(response).to have_http_status(:unprocessable_entity), acao
        expect(response.parsed_body['code']).to eq('sem_instrucao'), acao
      end
      expect(Redis::Alfred.get(Autonomia::Agents::BaseDeSeguros::Limite.chave_da_conta(conta))).to be_nil
    end

    it 'desfaz e volta à base de antes; pedir de novo é 409' do
      comparou
      pedir(:post, 'atualizar', params: { versao: bloco.versao('seguros/corretora') })
      pedir(:post, 'desfazer')

      expect(response).to have_http_status(:ok)
      expect(agente.reload.config['base']).to eq(seguradora)
      expect(response.parsed_body['desfazer']).to be_nil

      pedir(:post, 'desfazer')
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('desfazer_fechado')
    end

    it 'a base nova mudou desde que a pessoa viu: 409 e nada muda' do
      pedir(:post, 'atualizar', params: { versao: 'outra0000000' })

      expect(response).to have_http_status(:conflict)
      expect(agente.reload.config['base']).to eq(seguradora)
    end

    it 'sem base nova (em dia): 422 e nada muda' do
      em_dia = { 'segmento' => 'seguros/corretora', 'versao' => bloco.versao('seguros/corretora'),
                 'texto' => bloco.for_segmento('seguros/corretora') }
      agente.update!(config: agente.config.merge('base' => em_dia))

      versao = bloco.versao('seguros/corretora')
      expect { pedir(:post, 'atualizar', params: { versao: versao }) }.not_to change(Autonomia::Agents::InstructionVersion, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'sem a versão que a pessoa viu: 422 e nada muda' do
      pedir(:post, 'atualizar')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('comparar_antes')
      expect(agente.reload.config['base']).to eq(seguradora)
    end

    it 'a API genérica do agente continua sem gravar a base' do
      forjada = seguradora.merge('texto' => 'FORJADO')
      patch "/api/v1/accounts/#{conta.id}/autonomia/agents/#{agente.id}", headers: admin.create_new_auth_token, as: :json,
                                                                          params: { agent: { config: { 'base' => forjada } } }

      expect(agente.reload.config['base']).to eq(seguradora)
    end
  end

  describe 'POST base/comparar' do
    it 'enfileira a comparação para quem gerencia e devolve onde buscar a resposta' do
      expect { pedir(:post, 'comparar', usuario: gerencia) }.to have_enqueued_job(Crm::Ai::InteractiveJob)

      expect(response).to have_http_status(:accepted)
      dados = Crm::Ai::InteractiveRequest.read(response.parsed_body['id'])
      expect(dados).to include('operation' => 'agent_base_compare', 'inputs' => { 'agent_id' => agente.id })
    end

    it 'uma comparação a cada 2 minutos por agente: a segunda é 429' do
      pedir(:post, 'comparar')
      pedir(:post, 'comparar')

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['code']).to eq('comparar_espere')
    end

    # O rescue_from roda fora do around_action do idioma (#1419): sem reabrir o idioma, o aviso sairia em inglês.
    it 'os avisos saem no idioma de quem pediu' do
      admin.update!(ui_settings: { 'locale' => 'pt_BR' })
      pedir(:post, 'comparar')
      pedir(:post, 'comparar')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.base_de_seguros.comparar_espere', locale: :pt_BR))

      pedir(:post, 'atualizar', params: { versao: '' })
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.base_de_seguros.comparar_antes', locale: :pt_BR))

      pedir(:post, 'atualizar', params: { versao: 'outra' })
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.base_de_seguros.base_mudou', locale: :pt_BR))
    end

    # Reabrir a gaveta nos 2 minutos depois de uma comparação pronta: o mesmo antes e depois, não a espera.
    it 'com a comparação pronta guardada: devolve ela (200), sem job e sem 429, e quem pediu passa a poder atualizar' do
      admin.update!(ui_settings: { 'locale' => 'en' })
      versao = bloco.versao('seguros/corretora')
      pronta = { versao: versao, perguntas: [{ pergunta: 'O que é franquia?', hoje: 'a', hoje_equipe: false, nova: 'b', nova_equipe: false }] }
      Autonomia::Agents::BaseDeSeguros::Limite.reservar!(agente)
      Autonomia::Agents::BaseDeSeguros::Comparada.guardar!(agente, gerencia.account_users.find_by(account: conta), 'en', pronta)

      expect { pedir(:post, 'comparar') }.not_to have_enqueued_job(Crm::Ai::InteractiveJob)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(pronta.deep_stringify_keys)

      pedir(:post, 'atualizar', params: { versao: versao })
      expect(response).to have_http_status(:ok)
    end

    it 'a comparação guardada em outro idioma não serve: segue a regra da espera' do
      admin.update!(ui_settings: { 'locale' => 'en' })
      pronta = { versao: bloco.versao('seguros/corretora'), perguntas: [{ pergunta: 'O que é franquia?' }] }
      Autonomia::Agents::BaseDeSeguros::Limite.reservar!(agente)
      Autonomia::Agents::BaseDeSeguros::Comparada.guardar!(agente, admin.account_users.find_by(account: conta), 'pt_BR', pronta)

      pedir(:post, 'comparar')

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'tipo sem perguntas para o antes e depois: 422, sem gastar o limite, e a linha não oferece o botão' do
      allow(Autonomia::Segmentos::Bloco).to receive(:perguntas).and_return([])

      pedir(:post, 'comparar')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('sem_base_nova')
      expect(Redis::Alfred.get(Autonomia::Agents::BaseDeSeguros::Limite.chave_da_conta(conta))).to be_nil

      pedir(:get)
      expect(response.parsed_body['pode_atualizar']).to be(false)
    end

    it 'no máximo 10 por dia na conta: a 11ª é 429' do
      limite = Autonomia::Agents::BaseDeSeguros::Limite
      limite::POR_DIA.times { Redis::Alfred.incr(limite.chave_da_conta(conta)) }

      pedir(:post, 'comparar')

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['code']).to eq('comparar_amanha')
    end

    it 'sem base nova: 422, sem gastar o limite' do
      em_dia = { 'segmento' => 'seguros/corretora', 'versao' => bloco.versao('seguros/corretora'),
                 'texto' => bloco.for_segmento('seguros/corretora') }
      agente.update!(config: agente.config.merge('base' => em_dia))

      pedir(:post, 'comparar')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Redis::Alfred.get(Autonomia::Agents::BaseDeSeguros::Limite.chave_da_conta(conta))).to be_nil
    end
  end
end
