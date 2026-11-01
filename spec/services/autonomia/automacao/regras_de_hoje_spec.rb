require 'rails_helper'

# #2414 F1.5: as regras de hoje das contas 6, 16 e 17 continuam funcionando igual, com a flag ligada ou desligada.
# As regras aqui são sintéticas, com a mesma forma das de produção (repo público: nada de dado de cliente).
RSpec.describe 'Regras de automação de hoje com a F1' do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:listener) { AutomationRuleListener.instance }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox).reload }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def evento(nome, dados)
    Events::Base.new(nome, Time.zone.now, dados)
  end

  [false, true].each do |ligada|
    context(ligada ? 'com a flag automacao_fundacao' : 'sem a flag') do
      before { account.enable_features!('automacao_fundacao') if ligada }

      # Forma da conta 6: atributo da conversa igual a um valor põe etiquetas.
      it 'conversa atualizada com o atributo põe as etiquetas' do
        create(:custom_attribute_definition, account: account, attribute_key: 'categoria', attribute_model: 'conversation_attribute',
                                             attribute_display_type: 'list', attribute_values: %w[sinistro renovacao])
        create(:automation_rule, account: account, event_name: 'conversation_updated',
                                 conditions: [{ attribute_key: 'categoria', filter_operator: 'equal_to', values: ['sinistro'],
                                                custom_attribute_type: 'conversation_attribute', query_operator: nil }],
                                 actions: [{ action_name: 'add_label', action_params: %w[pos-venda sinistro] }])
        conversation.update!(custom_attributes: { 'categoria' => 'sinistro' })

        listener.conversation_updated(evento('conversation_updated', conversation: conversation,
                                                                     changed_attributes: { custom_attributes: [{}, { 'categoria' => 'sinistro' }] }))

        expect(conversation.reload.label_list).to contain_exactly('pos-venda', 'sinistro')
      end

      # Forma da conta 17: conversa nova na caixa vai para a dona da caixa.
      it 'conversa criada na caixa é atribuída à dona' do
        dona = create(:user, account: account, role: :agent)
        create(:inbox_member, inbox: inbox, user: dona)
        create(:automation_rule, account: account, event_name: 'conversation_created',
                                 conditions: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }],
                                 actions: [{ action_name: 'assign_agent', action_params: [dona.id] }])

        listener.conversation_created(evento('conversation_created', conversation: conversation))

        expect(conversation.reload.assignee_id).to eq(dona.id)
      end

      # Forma da conta 16: e-mail recebido com o assunto pergunta ao Decisor; o card só vem depois da resposta.
      it 'mensagem recebida com o assunto pergunta ao Decisor e espera a resposta' do
        _, etapa = create_crm_pipeline(account: account, user: create(:user, account: account, role: :administrator))
        conversation.update!(additional_attributes: { 'mail_subject' => 'Cotação de frota' })
        decisor = create(:autonomia_decisor, account: account)
        condicoes = [
          { attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: 'AND' },
          { attribute_key: 'message_type', filter_operator: 'equal_to', values: ['incoming'], query_operator: 'AND' },
          { attribute_key: 'mail_subject', filter_operator: 'contains', values: ['cotação'], query_operator: nil }
        ]
        regra = create(:automation_rule, account: account, event_name: 'message_created', conditions: condicoes,
                                         actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] },
                                                   { action_name: 'crm_create_card', action_params: [etapa.id] }])
        mensagem = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
        clear_enqueued_jobs

        listener.message_created(evento('message_created', message: mensagem))

        expect(Autonomia::Decisores::PerguntarJob).to have_been_enqueued.with(regra.id, conversation.id, mensagem.id, 0)
        expect(Crm::Card.where(account: account).count).to eq(0)
      end
    end
  end
end
