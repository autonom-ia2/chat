require 'rails_helper'

# #932 — o Guia lê a regra interna das colunas JSON no esquema que o modelo declara, confere o corpo
# por dentro antes de gravar e pede confirmação para o que o esquema marca sem volta. Nada aqui
# depende de código do Guia por domínio: o modelo fictício do fim prova isso.
RSpec.describe Autonomia::Guide::Formatos::Conferencia, '#por_dentro' do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:acoes) { Autonomia::Guide::Acoes.new(account: conta, user: admin) }
  let(:agente_do_guia) do
    Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active, enabled: false,
                                     instruction: 'Guia.', config: { 'with_knowledge' => false })
  end
  let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  def ferramenta(classe, params)
    classe.new(agent: agente_do_guia, params: params, operador: operador).call
  end

  def regra(acoes_da_regra, condicoes: [])
    { name: 'R', event_name: 'conversation_created', conditions: condicoes, actions: acoes_da_regra }
  end

  def recusa(corpo, acao: 'POST automation_rules', caminho: {})
    allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_call_original
    acoes.executar(acao, { caminho: caminho, corpo: corpo })
    raise 'era para recusar'
  rescue Autonomia::Guide::Acoes::CorpoForaDoFormato => e
    expect(Autonomia::Guide::ChamadaInterna).not_to have_received(:new)
    e.message
  end

  def executa(corpo, acao: 'POST automation_rules', caminho: {})
    resultado = acoes.executar(acao, { caminho: caminho, corpo: corpo })
    expect(resultado.ok).to be(true), "#{acao}: #{resultado.mensagem} #{resultado.dica}"
  end

  describe 'formato com esquema (AC-G6)' do
    it 'o resumo cabe no teto e mostra o primeiro nível com a lista fechada', :aggregate_failures do
      texto = Autonomia::Guide::Formatos.resumo_para_o_modelo('POST automation_rules')

      expect(texto.size).to be <= Autonomia::Guide::Formatos::Resumo::TETO
      expect(texto).to include('action_name: um de: send_message', 'attribute_key: um de:', 'campo "actions.<action_name>"')
    end

    it 'com campo, devolve só o ramo pedido, com a descrição em português', :aggregate_failures do
      params = { 'acao' => 'POST automation_rules', 'campo' => 'actions.send_email_to_team' }
      texto = ferramenta(Autonomia::Agents::Tools::Native::GuiaFormato, params)

      expect(texto).to include('actions.send_email_to_team', 'team_ids', 'Manda um e-mail aos membros dos times')
      expect(texto).not_to include('send_webhook_event', 'Formato de POST automation_rules')
    end

    it 'com o campo inteiro, lista cada ramo com o que ele faz' do
      texto = Autonomia::Guide::Formatos.resumo_para_o_modelo('POST automation_rules', campo: 'actions')

      expect(texto).to include('Campo actions:', '- add_label: Põe estas etiquetas')
    end

    it 'o campo de dentro de lista também tem ramos' do
      texto = Autonomia::Guide::Formatos.resumo_para_o_modelo('POST crm/stages/:stage_id/stage_automations',
                                                              campo: 'steps.action_config.move_stage')

      expect(texto).to include('target_stage_id', 'Move o card para a etapa')
    end
  end

  describe 'conferência por dentro' do
    # AC-G7
    it 'recusa time de fora da conta antes de gravar, com o caminho e os times válidos', :aggregate_failures do
      time = conta.teams.create!(name: 'sinistros')
      corpo = regra([{ action_name: 'assign_team', action_params: [999] }])

      texto = ferramenta(Autonomia::Agents::Tools::Native::GuiaExecucao,
                         'acao' => 'POST automation_rules', 'descricao' => 'Criar a regra.', 'corpo_json' => corpo.to_json)

      expect(texto).to include('/actions/0/action_params/0', '999 não existe nesta conta', "#{time.id} (sinistros)")
      expect(conta.automation_rules.count).to eq(0)
      expect([Autonomia::Guide::Execucao.count, Autonomia::Guide::Mudanca.count]).to eq([0, 0])
    end

    # AC-G8
    it 'recusa chave que o passo não lê, com o caminho', :aggregate_failures do
      _pipeline, etapa = create_crm_pipeline(account: conta, user: admin)
      automacao = Crm::StageAutomation.create!(account: conta, pipeline: etapa.pipeline, stage: etapa, name: 'E')

      texto = recusa({ action_type: 'create_follow_up', action_config: { title: 'Ligar', lembrete: 'x' } },
                     acao: 'POST crm/stage_automations/:stage_automation_id/steps', caminho: { stage_automation_id: automacao.id })

      expect(texto).to include('/action_config/lembrete', 'não conhece', 'follow_up_type')
      expect(automacao.steps.count).to eq(0)
    end

    it 'recusa o que o motor ignora e o que a conta não tem, como o vocabulário do #917', :aggregate_failures do
      outro_time = create(:team)
      conta.labels.create!(title: 'retencao')
      create(:custom_attribute_definition, account: conta, attribute_key: 'plano', attribute_model: 'contact_attribute')

      expect(recusa(regra([{ action_name: 'send_sms', action_params: ['x'] }]))).to include('"send_sms" não vale aqui', 'send_message')
      expect(recusa(regra([{ action_name: 'assign_team', action_params: [outro_time.id] }]))).to include('não existe nesta conta')
      expect(recusa(regra([{ action_name: 'assign_team', action_params: ['5'] }]))).to include('número inteiro, sem aspas')
      expect(recusa(regra([{ action_name: 'add_label', action_params: ['Retencao'] }]))).to include('"Retencao" não existe', 'retencao')
      expect(recusa(regra([{ action_name: 'send_email_transcript', action_params: ['{{contact.name}}'] }]))).to include('{{contact.email}}')
      expect(recusa(regra([{ action_name: 'send_message', action_params: %w[um dois] }]))).to include('no máximo 1')
      expect(recusa(regra([], condicoes: [{ attribute_key: 'status', filter_operator: 'contains', values: ['open'] }])))
        .to include('"contains" não vale aqui', 'equal_to, not_equal_to')
      expect(recusa(regra([], condicoes: [{ attribute_key: 'plano', filter_operator: 'equal_to', values: ['ouro'] }])))
        .to include('falta custom_attribute_type')
      sem_atributo = { attribute_key: 'ramo', filter_operator: 'equal_to', values: ['x'], custom_attribute_type: 'contact_attribute' }
      expect(recusa(regra([], condicoes: [sem_atributo]))).to include('"ramo" não existe nesta conta', 'plano')
    end

    it 'recusa tipo de passo que não existe e o que falta no passo', :aggregate_failures do
      _pipeline, etapa = create_crm_pipeline(account: conta, user: admin)
      corpo = ->(passo) { { name: 'E', trigger_event: 'on_enter', steps: [passo] } }
      acao = 'POST crm/stages/:stage_id/stage_automations'

      expect(recusa(corpo.call({ action_type: 'enviar', action_config: {} }), acao: acao, caminho: { stage_id: etapa.id }))
        .to include('/steps/0/action_type', 'move_stage')
      expect(recusa(corpo.call({ action_type: 'create_follow_up', action_config: { titulo: 'x' } }), acao: acao, caminho: { stage_id: etapa.id }))
        .to include('/steps/0/action_config/titulo', 'falta title')
    end
  end

  describe 'regras válidas passam pela conferência e pela API' do
    let(:agente) { create_crm_agent(account: conta).first }
    let(:time) { conta.teams.create!(name: 'retencao') }
    let(:funil) { create_crm_pipeline(account: conta, user: admin) }

    before { %w[risco_de_cancelamento retencao].each { |titulo| conta.labels.create!(title: titulo) } }

    it 'aceita cada ação, com o parâmetro na forma do método' do
      etapa = funil.last
      todas = [
        ['add_label', ['retencao']], ['remove_label', ['risco_de_cancelamento']], ['assign_team', [time.id]],
        ['assign_agent', [agente.id]], ['assign_agent', ['last_responding_agent']], ['remove_assigned_agent', []],
        ['send_email_to_team', [{ team_ids: [time.id], message: 'Novo caso' }]], ['change_priority', ['nil']],
        ['send_webhook_event', ['https://exemplo.com/gancho']], ['send_email_transcript', ['{{contact.email}}, b@exemplo.com']],
        ['crm_create_card', [etapa.id]], ['crm_move_card_stage', [etapa.id]], ['crm_assign_card_owner', [agente.id]]
      ].map { |nome, parametros| { action_name: nome, action_params: parametros } }

      executa(regra(todas))

      expect(conta.automation_rules.find_by(name: 'R').actions.size).to eq(todas.size)
    end

    it 'aceita condições da plataforma e atributo personalizado da conta' do
      create(:custom_attribute_definition, account: conta, attribute_key: 'plano', attribute_model: 'contact_attribute')
      condicoes = [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [create_crm_inbox(account: conta).id], query_operator: 'AND' },
                   { attribute_key: 'plano', filter_operator: 'equal_to', values: ['ouro'], custom_attribute_type: 'contact_attribute' }]

      executa(regra([{ action_name: 'add_label', action_params: ['retencao'] }], condicoes: condicoes))

      expect(conta.automation_rules.count).to eq(1)
    end

    it 'aceita automação de etapa com os três tipos de passo' do
      pipeline, etapa = funil
      destino = create_crm_stage(account: conta, pipeline: pipeline, name: 'Proposta')
      executa({ name: 'Ao entrar', trigger_event: 'on_enter',
                steps: [{ action_type: 'create_follow_up', action_config: { title: 'Ligar', follow_up_type: 'call' } },
                        { action_type: 'assign_owner', action_config: { owner_id: agente.id } },
                        { action_type: 'move_stage', delay_seconds: 3600, action_config: { target_stage_id: destino.id } }] },
              acao: 'POST crm/stages/:stage_id/stage_automations', caminho: { stage_id: etapa.id })

      expect(Crm::StageAutomation.find_by(name: 'Ao entrar').steps.pluck(:action_type)).to eq(%w[create_follow_up assign_owner move_stage])
    end
  end

  # AC-G9
  describe 'sem volta pelo esquema' do
    let(:transcricao) { regra([{ action_name: 'send_email_transcript', action_params: ['gestor@exemplo.com'] }]) }

    it 'regra que manda e-mail vai para propor_acao; só etiqueta executa direto, com desfazer', :aggregate_failures do
      conta.labels.create!(title: 'vip')
      params = { 'acao' => 'POST automation_rules', 'descricao' => 'Criar a regra.', 'corpo_json' => transcricao.to_json }

      expect(ferramenta(Autonomia::Agents::Tools::Native::GuiaExecucao, params)).to include('Use propor_acao')
      expect(ferramenta(Autonomia::Agents::Tools::Native::GuiaAcao, params)).to include('Proposta preparada')
      expect(conta.automation_rules.count).to eq(0)

      etiqueta = params.merge('corpo_json' => regra([{ action_name: 'add_label', action_params: ['vip'] }]).to_json)
      expect(ferramenta(Autonomia::Agents::Tools::Native::GuiaExecucao, etiqueta)).to include('Feito')
      expect(Autonomia::Guide::Execucao.last.desfazivel?).to be(true)
    end

    it 'passo que manda mensagem sozinho também pede confirmação' do
      corpo = { name: 'E', steps: [{ action_type: 'create_follow_up', action_config: { title: 'x', automation_mode: 'auto_send_message' } }] }

      expect(acoes.desfazivel?('POST crm/stages/:stage_id/stage_automations', { corpo: corpo })).to be(false)
    end

    it 'não existe arquivo de sem volta por domínio no Guia' do
      expect(Rails.root.glob('app/services/autonomia/guide/**/*sem_volta*.rb')).to eq([])
    end
  end

  # AC-G10: um modelo que o Guia nunca viu, com esquema na coluna, entra no formato e na conferência.
  describe 'genérico de verdade (AC-G10)' do
    let(:ficticio) do
      Class.new(ApplicationRecord) do
        self.table_name = 'crm_stage_automations'

        def self.name = 'Ficticio'

        validates :metadata, json_schema: { schema: {
          'type' => 'object', 'additionalProperties' => false,
          'properties' => { 'equipe' => { 'type' => 'integer', 'x-da-conta' => { 'modelo' => 'Team' } },
                            'avisar' => { 'type' => 'boolean', 'description' => 'Manda aviso.' } },
          'allOf' => [{ 'if' => { 'properties' => { 'avisar' => { 'const' => true } }, 'required' => ['avisar'] }, 'x-sem-volta' => true }]
        } }
      end
    end
    let(:formato) do
      corpo = Autonomia::Guide::Formatos::Corpo.new(modelos: [ficticio], criando: true)
      corpo.livre(['metadata'])
      corpo.saida(Api::V1::Accounts::LabelsController).merge('completo' => true)
    end

    before { allow(Autonomia::Guide::Formatos).to receive(:para).with('POST ficticios').and_return(formato) }

    it 'o formato traz o esquema e a conferência confere por dentro, sem linha nova no Guia', :aggregate_failures do
      time = conta.teams.create!(name: 'vendas')
      conferencia = ->(metadata) { described_class.new('POST ficticios', { metadata: metadata }, conta: conta) }

      expect(formato.dig('campos', 'metadata', 'esquema', 'properties').keys).to eq(%w[equipe avisar])
      expect(conferencia.call({ equipe: 999 }).problemas).to include(a_hash_including(caminho: '/metadata/equipe', validos: ["#{time.id} (vendas)"]))
      expect(conferencia.call({ outra: 1 }).problemas).to include(a_hash_including(caminho: '/metadata/outra'))
      expect(conferencia.call({ equipe: time.id }).problemas).to eq([])
      expect(conferencia.call({ equipe: time.id, avisar: true }).sem_volta?).to be(true)
      expect(conferencia.call({ equipe: time.id, avisar: false }).sem_volta?).to be(false)
      expect(Rails.root.glob('app/services/autonomia/guide/**/*.rb').map(&:read).join).not_to include('Ficticio')
    end
  end
end
