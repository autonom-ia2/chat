require 'rails_helper'

# #2568 P7: a mudança feita por uma Automação livre aparece como dela, com quem a ligou.
RSpec.describe ConversationAtividadeDaAutomacao do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:juliana) { create(:user, account: account, role: :administrator, name: 'Juliana Prado') }
  let(:maria) { create(:user, account: account, role: :agent, name: 'Maria Souza') }
  let(:conversation) { create(:conversation, account: account, status: :open) }
  let(:automacao) { create(:autonomia_automacao, account: account, nome: 'Boas-vindas', ligada_por: juliana) }
  let(:quem_age) { I18n.t('automation.livre.com_quem_ligou', nome: 'Boas-vindas', user_name: 'Juliana Prado') }

  before do
    create(:inbox_member, user: maria, inbox: conversation.inbox)
    create(:inbox_member, user: juliana, inbox: conversation.inbox)
    Current.user = juliana
  end

  after { Current.reset }

  # O ato é aberto pelo AcoesDoMotor em volta do pedido da automação (ver acoes_do_motor_spec, de ponta a ponta).
  def pela_automacao(id = automacao.id, &)
    Autonomia::Automacao::Ato.da(id, &)
  end

  def atividades
    enqueued_jobs.select { |job| job['job_class'] == 'Conversations::ActivityMessageJob' }
                 .map { |job| ActiveJob::Arguments.deserialize(job['arguments']).last[:content] }
  end

  it 'atribuição diz a automação e quem a ligou' do
    pela_automacao { conversation.update!(assignee: maria) }

    expect(atividades).to include(I18n.t('conversations.activity.assignee.assigned', assignee_name: 'Maria Souza', user_name: quem_age))
  end

  it 'atribuir para quem ligou não vira "atribuiu a si mesmo" e avisa a pessoa' do
    pela_automacao { conversation.update!(assignee: juliana) }

    expect(atividades).to include(I18n.t('conversations.activity.assignee.assigned', assignee_name: 'Juliana Prado', user_name: quem_age))
    expect(conversation.send(:notifiable_assignee_change?)).to be(false) # fora da cadeia, volta ao normal
    pela_automacao { expect(conversation.send(:notifiable_assignee_change?)).to be(true) }
  end

  it 'status diz a automação e quem a ligou' do
    pela_automacao { conversation.update!(status: :resolved) }

    expect(atividades).to include(I18n.t('conversations.activity.status.resolved', user_name: quem_age))
  end

  it 'prioridade, etiqueta e equipe também dizem a automação' do
    team = create(:team, account: account, name: 'Vendas')

    pela_automacao do
      conversation.update!(priority: :high)
      conversation.update!(label_list: ['vip'])
      conversation.update!(team: team)
    end

    expect(atividades.size).to eq(3)
    expect(atividades).to all(include(quem_age))
  end

  it 'busca a automação uma vez só por conversa' do
    pela_automacao { conversation.update!(assignee: juliana) }
    consultas = 0
    contar = ->(*, payload) { consultas += 1 if payload[:sql].include?('autonomia_automacoes') }

    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
      pela_automacao { 3.times { conversation.send(:self_assign?, juliana.id) } }
    end

    expect(consultas).to eq(0)
  end

  it 'sem quem ligou, fica só o nome da automação' do
    automacao.update!(ligada_por: nil)

    pela_automacao { conversation.update!(status: :resolved) }

    so_o_nome = I18n.t('automation.livre.sem_quem_ligou', nome: 'Boas-vindas')
    expect(atividades).to include(I18n.t('conversations.activity.status.resolved', user_name: so_o_nome))
  end

  it 'automação de outra conta não empresta o nome' do
    outra = create(:autonomia_automacao, nome: 'De fora')

    pela_automacao(outra.id) { conversation.update!(status: :resolved) }

    expect(atividades).to include(I18n.t('conversations.activity.status.resolved', user_name: 'Juliana Prado'))
  end

  it 'quem herda a cadeia da automação no evento não assina como ela' do
    Autonomia::Automacao::Cadeia.restaurada(["automacao:#{automacao.id}"], account.id) { conversation.update!(assignee: juliana) }

    expect(atividades).to include(I18n.t('conversations.activity.assignee.self_assigned', user_name: 'Juliana Prado'))
    expect(atividades.join).not_to include('Boas-vindas')
  end
end
