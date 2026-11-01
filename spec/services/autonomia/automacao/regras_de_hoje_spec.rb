require 'rails_helper'

# #2414 F1.5: as regras de hoje das contas 6, 16 e 17 continuam funcionando igual, com a flag ligada ou desligada.
# As regras aqui são sintéticas, com a mesma forma das de produção (repo público: nada de dado de cliente).
# Cada caso parte da mudança real (o model despacha o evento) e roda os jobs até o fim: EventDispatcherJob e o job
# do Decisor.
RSpec.describe 'Regras de automação de hoje com a F1' do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox).reload }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def ate_o_fim(&)
    perform_enqueued_jobs(only: [EventDispatcherJob, Autonomia::Decisores::PerguntarJob], &)
  end

  # Só as notas da cadeia: pôr etiqueta também gera a atividade de sempre ("adicionou as etiquetas").
  def notas_da_cadeia
    enqueued_jobs.count do |job|
      job['job_class'] == 'Conversations::ActivityMessageJob' && job['arguments'].last['content'].to_s.include?('to avoid repetition')
    end
  end

  [false, true].each do |ligada|
    context(ligada ? 'com a flag automacao_fundacao' : 'sem a flag') do
      before { account.enable_features!('automacao_fundacao') if ligada }

      # Forma da conta 6: atributo da conversa igual a um valor põe etiquetas. Com a flag, a mudança da própria regra
      # casa de novo com ela: a cadeia recusa (laço) e deixa uma nota só.
      it 'conversa atualizada com o atributo põe as etiquetas' do
        create(:custom_attribute_definition, account: account, attribute_key: 'categoria', attribute_model: 'conversation_attribute',
                                             attribute_display_type: 'list', attribute_values: %w[sinistro renovacao])
        create(:automation_rule, account: account, event_name: 'conversation_updated',
                                 conditions: [{ attribute_key: 'categoria', filter_operator: 'equal_to', values: ['sinistro'],
                                                custom_attribute_type: 'conversation_attribute', query_operator: nil }],
                                 actions: [{ action_name: 'add_label', action_params: %w[pos-venda sinistro] }])
        conversation
        clear_enqueued_jobs

        ate_o_fim { conversation.update!(custom_attributes: { 'categoria' => 'sinistro' }) }

        expect(conversation.reload.label_list).to contain_exactly('pos-venda', 'sinistro')
        expect(notas_da_cadeia).to eq(ligada ? 1 : 0)
      end

      # Forma da conta 17: conversa nova na caixa vai para a dona da caixa.
      it 'conversa criada na caixa é atribuída à dona' do
        dona = create(:user, account: account, role: :agent)
        create(:inbox_member, inbox: inbox, user: dona)
        create(:automation_rule, account: account, event_name: 'conversation_created',
                                 conditions: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }],
                                 actions: [{ action_name: 'assign_agent', action_params: [dona.id] }])

        nova = ate_o_fim { create(:conversation, account: account, inbox: inbox) }

        expect(nova.reload.assignee_id).to eq(dona.id)
      end

      # Forma da conta 16: e-mail recebido com o assunto pergunta ao Decisor; o card vem depois da resposta.
      it 'mensagem recebida com o assunto pergunta ao Decisor e, com o sim, cria o card' do
        allow(TypesafeAi::Config).to receive_messages(api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
        stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return(
          status: 200,
          body: { model: 'jev-1.13.0', usage: { input_tokens: 800, output_tokens: 2 },
                  answers: { decisao: { type: 'choice', choice: 'sim', confidence: 0.95 } } }.to_json
        )
        _, etapa = create_crm_pipeline(account: account, user: create(:user, account: account, role: :administrator))
        conversation.update!(additional_attributes: { 'mail_subject' => 'Cotação de frota' })
        decisor = create(:autonomia_decisor, account: account)
        condicoes = [
          { attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: 'AND' },
          { attribute_key: 'message_type', filter_operator: 'equal_to', values: ['incoming'], query_operator: 'AND' },
          { attribute_key: 'mail_subject', filter_operator: 'contains', values: ['cotação'], query_operator: nil }
        ]
        create(:automation_rule, account: account, event_name: 'message_created', conditions: condicoes,
                                 actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] },
                                           { action_name: 'crm_create_card', action_params: [etapa.id] }])

        ate_o_fim { create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming) }

        expect(Autonomia::DecisorDecisao.last).to have_attributes(status: 'decidida', resposta: 'sim')
        expect(Crm::Card.where(account: account, stage: etapa).count).to eq(1)
      end
    end
  end
end
