require 'rails_helper'

# #2414 F1.2 (D1): a ação que uma automação faz pela porta da frente fica em nome de quem a ligou, não "sistema". E o
# pedido de dentro não apaga a marca de quem chamou por fora, nem a cadeia de automações.
RSpec.describe Autonomia::Guide::ChamadaInterna do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:juliana) { create(:user, account: account, role: :administrator, name: 'Juliana Prado') }
  let(:conversation) { create(:conversation, account: account, status: :open) }
  let(:rule) { create(:automation_rule, account: account) }

  after { Current.reset }

  def resolver_pela_porta_da_frente
    described_class.new(user: juliana).chamar(
      'POST', "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/toggle_status",
      corpo: { status: 'resolved' }
    )
  end

  it 'a atividade sai com o nome de quem ligou, mesmo chamada de dentro de uma regra' do
    Current.executed_by = rule

    resposta = Autonomia::Automacao::Cadeia.com('automacao:1') { resolver_pela_porta_da_frente }

    expect(resposta.codigo).to eq('200')
    atividade = enqueued_jobs.find { |job| job['job_class'] == 'Conversations::ActivityMessageJob' }
    conteudo = ActiveJob::Arguments.deserialize(atividade['arguments']).last[:content]
    expect(conteudo).to include('Juliana Prado')
    expect(conteudo).not_to include(I18n.t('automation.system_name'))
  end

  it 'devolve o executed_by de fora e a cadeia continua depois do pedido' do
    Current.executed_by = rule

    depois = Autonomia::Automacao::Cadeia.com('automacao:1') do
      resolver_pela_porta_da_frente
      Autonomia::Automacao::Cadeia.origens
    end

    expect(Current.executed_by).to eq(rule)
    expect(depois).to eq(['automacao:1'])
  end
end
