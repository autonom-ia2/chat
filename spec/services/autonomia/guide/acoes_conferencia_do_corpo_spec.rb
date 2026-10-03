require 'rails_helper'

# O corpo conferido contra o formato da ação ANTES de chamar a plataforma (#900).
#
# Em produção a chave que o `permit` não conhece é descartada calada e a
# resposta é 200. Na conta 18 o Guia mandou uma permissão inventada numa função
# personalizada: "feito", e a função ficou sem ela. Os casos de recusa provam
# que nada chega à plataforma; os de execução provam, contra a aplicação de
# verdade, que a conferência não barra ação legítima — corpo plano ou no
# envelope.
RSpec.describe Autonomia::Guide::Acoes do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:acoes) { described_class.new(account: conta, user: admin) }

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run }
  end

  describe 'o que recusa antes de chamar a plataforma' do
    before { allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_call_original }

    def recusa(acao, corpo, caminho: {})
      acoes.executar(acao, { caminho: caminho, corpo: corpo })
      raise 'era para recusar'
    rescue described_class::CorpoForaDoFormato => e
      expect(Autonomia::Guide::ChamadaInterna).not_to have_received(:new)
      e.message
    end

    # O pedido da conta 18, em 02/10/2026.
    it 'recusa permissão inventada e lista as que existem', :aggregate_failures do
      conta.enable_features!('custom_roles')
      funcao = conta.custom_roles.create!(name: 'Marketing', permissions: ['conversation_manage'])

      texto = recusa('PATCH custom_roles/:id', { permissions: %w[inbox_read conversation_manage] }, caminho: { id: funcao.id })

      expect(texto).to include('inbox_read não é valor aceito')
      expect(texto).to include(*CustomRole::PERMISSIONS)
      expect(texto).to include('"custom_role"')
      expect(funcao.reload.permissions).to eq(['conversation_manage'])
    end

    it 'recusa campo que a ação não tem, em vez de deixar a plataforma descartar calada' do
      texto = recusa('POST labels', { title: 'vip', cor: 'vermelha' })

      expect(texto).to include('campo que esta ação não tem: cor')
    end

    it 'recusa valor fora da lista de um enum' do
      expect(recusa('POST crm/cards', { title: 'x', pipeline_id: 1, stage_id: 1, priority: 'altissima' }))
        .to include('priority: altissima não é valor aceito; os aceitos são: low, medium, high, urgent')
    end

    it 'recusa criação sem o que o código exige (params.require)' do
      contato = create(:contact, account: conta)

      expect(recusa('POST contacts/:id/call', { conversation_id: 7 }, caminho: { id: contato.id }))
        .to include('falta o obrigatório: inbox_id')
    end

    it 'recusa corpo em ação que não lê corpo' do
      etiqueta = conta.labels.create!(title: 'fica')

      expect(recusa('DELETE labels/:id', { title: 'fica' }, caminho: { id: etiqueta.id })).to include('não lê corpo')
    end

    # O mesmo ponto vale para quem propõe e para quem abre a execução do turno.
    it 'recusa também na proposta e na conferência do turno', :aggregate_failures do
      dados = { corpo: { title: 'vip', cor: 'x' }, descricao: 'Criar a etiqueta vip.' }

      expect { acoes.descrever('POST labels', dados) }.to raise_error(described_class::CorpoForaDoFormato)
      expect { acoes.conferir!('POST labels', dados) }.to raise_error(described_class::CorpoForaDoFormato)
    end
  end

  describe 'o formato parcial' do
    # `POST crm/pipelines` é parcial (lê `goal` cru): chave desconhecida pode
    # existir, então passa — mas o modelo fica sabendo que ela não voltou.
    it 'deixa passar a chave desconhecida e avisa que ela não voltou no registro', :aggregate_failures do
      resultado = acoes.executar('POST crm/pipelines', { corpo: { name: 'Residencial', inventado: 'x' } })

      expect(resultado.ok).to be(true)
      expect(resultado.aviso).to include('inventado')
      expect(conta.crm_pipelines.find_by(name: 'Residencial')).to be_present
    end
  end

  describe 'ações legítimas, contra a aplicação de verdade' do
    def executa(acao, corpo, caminho: {})
      resultado = acoes.executar(acao, { caminho: caminho, corpo: corpo })
      expect(resultado.ok).to be(true), "#{acao}: #{resultado.mensagem}"
      resultado
    end

    it 'cria e altera função personalizada, com o corpo plano', :aggregate_failures do
      conta.enable_features!('custom_roles')

      executa('POST custom_roles', { name: 'Marketing', permissions: %w[inbox_view contact_view] })
      funcao = conta.custom_roles.find_by(name: 'Marketing')
      executa('PATCH custom_roles/:id', { permissions: %w[inbox_view] }, caminho: { id: funcao.id })

      expect(funcao.reload.permissions).to eq(%w[inbox_view])
    end

    it 'cria etiqueta e time no envelope', :aggregate_failures do
      executa('POST labels', { label: { title: 'renovacao', color: '#ff0000' } })
      executa('POST teams', { team: { name: 'Recepção' } })

      expect(conta.labels.find_by(title: 'renovacao').color).to eq('#ff0000')
      expect(conta.teams.find_by(name: 'recepção')).to be_present
    end

    it 'monta funil, etapa e card do CRM', :aggregate_failures do
      executa('POST crm/pipelines', { name: 'Seguro Residencial' })
      funil = conta.crm_pipelines.find_by(name: 'Seguro Residencial')
      executa('POST crm/pipelines/:pipeline_id/stages', { name: 'Contato', position: 0 }, caminho: { pipeline_id: funil.id })
      etapa = funil.stages.find_by(name: 'Contato')
      executa('PATCH crm/stages/:id', { stage: { win_probability: 40 } }, caminho: { id: etapa.id })
      executa('POST crm/cards', { title: 'João', pipeline_id: funil.id, stage_id: etapa.id, priority: 'high' })

      expect(etapa.reload.win_probability).to eq(40)
      expect(conta.crm_cards.find_by(title: 'João').priority).to eq('high')
    end

    # Bateria do #900, C19: a plataforma gravava os membros e devolvia uma LISTA; ler a lista como
    # registro quebrava depois do sucesso, e o Guia dizia que não tinha conseguido.
    it 'põe agentes num time, ação que devolve uma lista', :aggregate_failures do
      agente, = create_crm_agent(account: conta)
      executa('POST teams', { team: { name: 'Recepção' } })
      time = conta.teams.find_by(name: 'recepção')

      resultado = executa('POST teams/:team_id/team_members', { user_ids: [agente.id] }, caminho: { team_id: time.id })

      expect(time.reload.members).to include(agente)
      expect(resultado.registro).to be_nil
    end

    it 'cria caixa, renomeia e põe agente nela', :aggregate_failures do
      agente, = create_crm_agent(account: conta)

      executa('POST inboxes', { name: 'Sinistros', channel: { type: 'api', webhook_url: '' } })
      caixa = conta.inboxes.find_by(name: 'Sinistros')
      executa('PATCH inboxes/:id', { name: 'Sinistros Auto' }, caminho: { id: caixa.id })
      executa('POST inbox_members', { inbox_id: caixa.id, user_ids: [agente.id] })

      expect(caixa.reload.name).to eq('Sinistros Auto')
      expect(caixa.members).to include(agente)
    end

    it 'cria automação com condições e ações' do
      caixa = create_crm_inbox(account: conta, name: 'Sinistros')
      conta.labels.create!(title: 'sinistro')

      executa('POST automation_rules', {
                name: 'Sinistro', event_name: 'conversation_created', active: true,
                conditions: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [caixa.id], query_operator: nil }],
                actions: [{ action_name: 'add_label', action_params: ['sinistro'] }]
              })

      expect(conta.automation_rules.find_by(name: 'Sinistro').actions.first['action_name']).to eq('add_label')
    end
  end

  # O que só o modelo exige não é barrado antes: a action pode preencher (o
  # card tira o título do contato). Quem recusa é a plataforma, e a recusa
  # volta com o formato.
  describe 'o que só o modelo exige' do
    it 'chega à plataforma, que recusa com o motivo', :aggregate_failures do
      resultado = acoes.executar('POST teams', { corpo: { description: 'sem nome' } })

      expect(resultado.ok).to be(false)
      expect(resultado.dica).to include('name: texto; o registro exige')
      expect(conta.teams.count).to eq(0)
    end
  end

  # A recusa da plataforma volta com o que o formato sabe do campo recusado:
  # "Title is invalid" sozinho não diz como acertar.
  describe 'a recusa que ensina' do
    it 'junta o formato ao atributo que a validação recusou', :aggregate_failures do
      resultado = acoes.executar('POST labels', { corpo: { title: 'Cliente VIP' } })

      expect(resultado.ok).to be(false)
      expect(resultado.dica).to include('title: texto; o registro exige')
      expect(resultado.mensagem).not_to include('formato')
    end

    it 'aponta o envelope quando falta o parâmetro que a action exige' do
      resposta = Autonomia::Guide::ChamadaInterna::Resposta.new(
        codigo: 422, corpo: { error: 'param is missing or the value is empty or invalid: custom_role' }.to_json
      )
      allow(Autonomia::Guide::ChamadaInterna).to receive(:new)
        .and_return(instance_double(Autonomia::Guide::ChamadaInterna, chamar: resposta))
      conta.enable_features!('custom_roles')
      funcao = conta.custom_roles.create!(name: 'Marketing', permissions: [])

      resultado = acoes.executar('PATCH custom_roles/:id', { caminho: { id: funcao.id }, corpo: {} })

      expect(resultado.dica).to include('os campos vão dentro de "custom_role"')
    end
  end
end
