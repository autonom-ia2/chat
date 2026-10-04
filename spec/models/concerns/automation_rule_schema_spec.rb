require 'rails_helper'

# #932 — a regra interna de conditions e actions é um esquema. Os casos vêm do spec do vocabulário
# do #917: o que ele aceitava a plataforma aceita, e o que ele recusava ela recusa, com o que vale.
# O que depende da conta (time, etiqueta) a plataforma não recusa: quem confere é o Guia
# (`spec/services/autonomia/guide/conferencia_por_dentro_spec.rb`).
RSpec.describe AutomationRuleSchema do
  let(:conta) { create(:account) }

  def regra(condicoes: [], acoes: [{ action_name: 'resolve_conversation', action_params: [] }], **extra)
    AutomationRule.new({ account: conta, name: 'R', event_name: 'message_created', conditions: condicoes, actions: acoes }.merge(extra))
  end

  def condicao(chave, operador, valores, ligacao = nil)
    { attribute_key: chave, filter_operator: operador, values: valores, query_operator: ligacao }
  end

  def erros(registro)
    registro.validate
    registro.errors.full_messages.join(' | ')
  end

  describe 'paridade com o motor (AC-G3)' do
    let(:esquema) { described_class.actions(nil) }
    let(:ramos) { esquema['items']['allOf'].map { |ramo| ramo.dig('if', 'properties', 'action_name', 'const') } }

    it 'toda ação que a regra aceita tem ramo, e todo ramo é uma ação que o motor executa', :aggregate_failures do
      nomes = AutomationRule.new.actions_attributes.uniq

      expect(ramos).to match_array(nomes)
      expect(described_class.new(nil).parametros.keys).to match_array(nomes)
      ramos.each do |nome|
        expect(AutomationRules::ActionService.private_method_defined?(nome) || AutomationRules::ActionService.method_defined?(nome) ||
               nome == Autonomia::Decisores::PASSO).to be(true), "#{nome} não é método do ActionService"
      end
    end

    it 'toda condição que a regra aceita tem ramo' do
      chaves = described_class.conditions(nil)['items']['allOf'].filter_map { |ramo| ramo.dig('if', 'properties', 'attribute_key', 'const') }

      expect(chaves).to match_array(AutomationRule.new.conditions_attributes.uniq)
    end

    it 'marca sem volta só o que sai da plataforma' do
      sem_volta = esquema['items']['allOf'].select { |ramo| ramo['x-sem-volta'] }.map { |ramo| ramo.dig('if', 'properties', 'action_name', 'const') }

      expect(sem_volta).to match_array(%w[send_message send_email_to_team send_email_transcript send_webhook_event send_attachment])
    end
  end

  describe 'o que vale' do
    it 'aceita cada ação, com o parâmetro na forma do método', :aggregate_failures do
      todas = [
        ['add_label', ['retencao']], ['remove_label', ['risco_de_cancelamento']], ['assign_team', [5]], ['assign_team', ['nil']],
        ['assign_agent', [7]], ['assign_agent', ['last_responding_agent']], ['remove_assigned_agent', []],
        ['remove_assigned_team', []], ['send_message', ['Já te atendemos.']], ['add_private_note', ['Atenção']],
        ['send_email_to_team', [{ team_ids: [5], message: 'Novo caso' }]],
        ['send_webhook_event', ['https://exemplo.com/gancho']], ['send_email_transcript', ['a@exemplo.com, b@exemplo.com']],
        ['send_email_transcript', ['{{contact.email}}, gestor@exemplo.com']],
        ['change_status', ['pending']], ['change_priority', ['urgent']], ['change_priority', ['nil']],
        ['mute_conversation', []], ['snooze_conversation', nil], ['open_conversation', []], ['pending_conversation', []],
        ['resolve_conversation', []], ['crm_create_card', [11]], ['crm_move_card_stage', [11]],
        ['crm_mark_card_won', []], ['crm_mark_card_lost', []], ['crm_assign_card_owner', [7]],
        ['disable_crm_ai_followup', []], ['enable_crm_ai_followup', []]
      ].map { |nome, parametros| { action_name: nome, action_params: parametros } }

      expect(erros(regra(acoes: todas))).to eq('')
    end

    it 'aceita condições de conversa, contato, mensagem, CRM e atributo personalizado' do
      create(:custom_attribute_definition, account: conta, attribute_key: 'plano', attribute_model: 'contact_attribute')
      condicoes = [
        condicao('status', 'equal_to', ['open'], 'AND'), condicao('message_type', 'equal_to', ['incoming'], 'and'),
        condicao('labels', 'not_equal_to', ['risco_de_cancelamento'], 'AND'), condicao('assignee_id', 'is_not_present', [], 'AND'),
        condicao('inbox_id', 'equal_to', [3], 'AND'), condicao('phone_number', 'starts_with', ['+55'], 'OR'),
        condicao('crm_stage_id', 'equal_to', [11], 'AND'), condicao('priority', 'equal_to', ['nil'], 'AND'),
        condicao('plano', 'equal_to', ['ouro'], 'AND').merge(custom_attribute_type: 'contact_attribute'),
        condicao('email', 'contains', ['@exemplo.com'])
      ]

      expect(erros(regra(condicoes: condicoes))).to eq('')
    end

    it 'aceita attribute_changed e o atraso em message_created', :aggregate_failures do
      mudou = regra(event_name: 'conversation_updated',
                    condicoes: [condicao('status', 'attribute_changed', { from: ['open'], to: ['resolved'] })])
      atraso = regra(execution_delay: 15, condicoes: [condicao('status', 'equal_to', ['open'], 'AND'),
                                                      condicao('assignee_id', 'is_not_present', [])])

      expect(erros(mudou)).to eq('')
      expect(erros(atraso)).to eq('')
    end

    # O painel manda o query_operator da última como nulo, mas a regra antiga e a API o trazem: o motor
    # tolera. Divergência consciente do #917, que recusava no Guia.
    it 'aceita query_operator na última condição' do
      expect(erros(regra(condicoes: [condicao('status', 'equal_to', ['open'], 'AND')]))).to eq('')
    end
  end

  describe 'o que recusa, com o que vale' do
    it 'ação, condição e operador que não existem, listando os que existem', :aggregate_failures do
      expect(erros(regra(acoes: [{ action_name: 'send_sms', action_params: ['x'] }]))).to include('"send_sms" is not one of', 'send_message')
      expect(erros(regra(condicoes: [condicao('mensagem', 'contains', ['x'])]))).to include('"mensagem" is not one of', 'message_type')
      expect(erros(regra(condicoes: [condicao('status', 'contains', ['open'])]))).to include('"contains" is not one of: equal_to, not_equal_to')
      expect(erros(regra(condicoes: [condicao('status', 'equal_to', ['aberta'])]))).to include('"aberta" is not one of: open, resolved')
      expect(erros(regra(condicoes: [condicao('status', 'equal_to', ['open'], 'XOR')]))).to include('"XOR" is not one of')
    end

    it 'falta query_operator entre condições' do
      expect(erros(regra(condicoes: [condicao('status', 'equal_to', ['open']), condicao('priority', 'equal_to', ['high'])])))
        .to include('should have query operator')
    end

    it 'atributo personalizado sem o tipo' do
      create(:custom_attribute_definition, account: conta, attribute_key: 'plano', attribute_model: 'contact_attribute')

      expect(erros(regra(condicoes: [condicao('plano', 'equal_to', ['ouro'])]))).to include('custom_attribute_type is required')
    end

    # assign_team e assign_agent comparam com Integer (`team_ids.include?(team_ids[0])`): "5" grava e não faz nada.
    it 'id em texto, que o motor compara com número e ignora', :aggregate_failures do
      expect(erros(regra(acoes: [{ action_name: 'assign_team', action_params: ['5'] }]))).to include('must be of type integer')
      expect(erros(regra(acoes: [{ action_name: 'assign_agent', action_params: ['5'] }]))).to include('must be of type integer')
      expect(erros(regra(acoes: [{ action_name: 'send_email_to_team', action_params: [{ team_ids: ['5'], message: 'x' }] }])))
        .to include('must be of type integer')
    end

    it 'action_params na forma errada', :aggregate_failures do
      expect(erros(regra(acoes: [{ action_name: 'send_webhook_event', action_params: ['exemplo.com'] }]))).to include('valid uri')
      expect(erros(regra(acoes: [{ action_name: 'send_email_to_team', action_params: ['aviso'] }]))).to include('must be of type hash')
      expect(erros(regra(acoes: [{ action_name: 'send_message', action_params: %w[um dois] }]))).to include('too long (maximum is 1)')
      expect(erros(regra(acoes: [{ action_name: 'send_email_transcript', action_params: ['fulano'] }]))).to include('lista-de-emails')
      expect(erros(regra(acoes: [{ action_name: 'send_email_transcript', action_params: ['{{contact.name}}'] }]))).to include('lista-de-emails')
      expect(erros(regra(acoes: [{ action_name: 'add_label', action_params: ['x'], prioridade: 1 }]))).to include('/0/prioridade is not allowed')
    end

    it 'as regras do atraso', :aggregate_failures do
      expect(erros(regra(event_name: 'conversation_updated', execution_delay: 30,
                         condicoes: [condicao('labels', 'equal_to', ['vip'])]))).to include('only supports status and inbox')
      expect(erros(regra(execution_delay: 5))).to include('Execution delay')
    end

    it 'criação sem conditions e actions' do
      sem_nada = AutomationRule.new(account: conta, name: 'Sem nada', conditions: nil, actions: nil)

      expect(erros(sem_nada)).to include('Conditions must be of type array', 'Actions must be of type array')
    end
  end

  # AC-G4: o atributo personalizado vale na conta que o tem, e só nela.
  describe 'atributo personalizado da conta (AC-G4)' do
    let(:outra) { create(:account) }

    it 'aceita a chave na conta que tem o atributo e recusa na outra, citando a chave', :aggregate_failures do
      create(:custom_attribute_definition, account: conta, attribute_key: 'ramo', attribute_model: 'conversation_attribute')
      condicoes = [condicao('ramo', 'equal_to', ['auto']).merge(custom_attribute_type: 'conversation_attribute')]

      expect(erros(regra(condicoes: condicoes))).to eq('')
      expect(erros(regra(condicoes: condicoes).tap { |registro| registro.account = outra })).to include('"ramo" is not one of')
    end
  end

  # O Guia escolhe o evento pela descrição: ela tem de cobrir exatamente o que o listener escuta.
  it 'descreve todos os eventos que o AutomationRuleListener escuta, e só eles' do
    escutados = AutomationRuleListener.public_instance_methods(false).map(&:to_s)

    expect(described_class::EVENTOS.keys).to match_array(escutados)
  end
end
