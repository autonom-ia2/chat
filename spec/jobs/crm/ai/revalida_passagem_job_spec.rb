require 'rails_helper'

# #1975: o job da releitura (fora da rodada da fila). Aplica sob a trava, só se a resposta é sobre a espera que foi
# lida; qualquer falha vira "entrega como hoje" na rodada seguinte, sem nova chamada paga sem mensagem nova.
RSpec.describe Crm::Ai::RevalidaPassagemJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'trigger' => 'pedido de pessoa' } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', primary_conversation: conversation,
                              inbox: inbox)
  end
  let(:revalida) { instance_double(Crm::Ai::RevalidaPassagem) }
  let(:token) do
    Crm::Ai::RevalidacaoNaFila.new(conversation).segurar?
    marca['revalidando_desde']
  end

  before do
    card
    Crm::Entrega::Marca.marcar(conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: 'ia_crm', falha: 'ninguem_online',
                                             razao: 'cliente pediu a cotação e o robô falhou')
    conversation.save!
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Segue a cotação.')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::RevalidaPassagem).to receive(:new).and_return(revalida)
  end

  def marca
    Crm::Entrega::Marca.dados(conversation.reload)
  end

  def resposta(passa, motivo)
    { passa: passa, motivo: motivo, decisao: passa ? 'problema_em_aberto' : 'resolvido' }
  end

  def retiradas
    Crm::Activity.where(card_id: card.id, event_type: 'ai_handoff_withdrawn')
  end

  it 'resolvido: o pedido sai e o porquê fica no card', :aggregate_failures do
    allow(revalida).to receive(:call).and_return(resposta(false, 'o robô enviou a cotação e o cliente não voltou'))

    described_class.perform_now(conversation.id, token)

    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(false)
    expect(retiradas.sole.payload).to include('reason' => 'o robô enviou a cotação e o cliente não voltou', 'decision' => 'resolvido')
  end

  it 'aberto: a marca guarda a última mensagem lida e o motivo novo, e a releitura em curso sai', :aggregate_failures do
    allow(revalida).to receive(:call).and_return(resposta(true, 'cliente pediu explicação de DMH e o robô não soube'))

    described_class.perform_now(conversation.id, token)

    expect(marca).to include('revalidado_ate' => conversation.messages.maximum(:id),
                             'razao' => 'cliente pediu explicação de DMH e o robô não soube')
    expect(marca.keys).not_to include(*Crm::Entrega::Marca::RELEITURA, 'revalidacao_falhou')
    expect(retiradas).to be_empty
  end

  it 'falha: a marca guarda a última mensagem lida e a falha, com o motivo do pedido', :aggregate_failures do
    allow(revalida).to receive(:call).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    described_class.perform_now(conversation.id, token)

    expect(marca).to include('revalidado_ate' => conversation.messages.maximum(:id), 'revalidacao_falhou' => true,
                             'razao' => 'cliente pediu a cotação e o robô falhou')
    expect(marca).not_to have_key('revalidando_desde')
  end

  it 'erro inesperado ao montar o contexto também é falha (entrega como hoje)' do
    allow(Crm::Ai::RevalidaPassagem).to receive(:new).and_call_original
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'chave'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(instance_double(Crm::Ai::ResponsesClient))
    allow(Crm::Ai::ContextBuilder).to receive(:new).and_raise(NoMethodError, 'quebrou')

    described_class.perform_now(conversation.id, token)

    expect(marca).to include('revalidacao_falhou' => true)
  end

  # Revisão do PR #1980 (HIGH 1): um pedido explícito que chega durante a chamada não some com um "resolvido" velho.
  it 'pedido do cliente chega durante a releitura: a resposta velha é descartada e a espera fica', :aggregate_failures do
    allow(revalida).to receive(:call) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       content: 'Quero falar com uma pessoa, por favor')
      resposta(false, 'o robô enviou a cotação')
    end

    described_class.perform_now(conversation.id, token)

    expect(marca).to include('razao' => 'cliente pediu a cotação e o robô falhou')
    expect(marca.keys).not_to include('revalidado_ate', 'revalidando_desde')
    expect(retiradas).to be_empty
    expect(Crm::Ai::RevalidacaoNaFila.new(conversation).segurar?).to be(true)
  end

  it 'o motivo da espera muda durante a releitura: a resposta velha é descartada', :aggregate_failures do
    allow(revalida).to receive(:call) do
      valor = Crm::Entrega::Marca.dados(conversation.reload).merge('razao' => 'pedido novo')
      conversation.update!(additional_attributes: conversation.additional_attributes.merge(Crm::Entrega::Marca::CHAVE => valor))
      resposta(false, 'resolvido antes')
    end

    described_class.perform_now(conversation.id, token)

    expect(marca).to include('razao' => 'pedido novo')
    expect(retiradas).to be_empty
  end

  # Revisão do PR #1980 (MÉDIO 3): o job toma a execução sob a trava antes de chamar; um segundo job do mesmo token
  # (o reenfileirado, ou o mesmo entregue duas vezes) sai sem chamar.
  it 'dois jobs com o mesmo token: uma chamada só', :aggregate_failures do
    chamadas = 0
    allow(revalida).to receive(:call) do
      chamadas += 1
      described_class.perform_now(conversation.id, token)
      resposta(true, 'segue aberto')
    end

    described_class.perform_now(conversation.id, token)

    expect(chamadas).to eq(1)
    expect(marca).to include('razao' => 'segue aberto')
  end

  it 'falhou ao aplicar, depois da resposta: a marca guarda a falha e a rodada seguinte entrega como hoje' do
    allow(revalida).to receive(:call).and_return(resposta(false, 'resolvido'))
    allow(Crm::Entrega::Marca).to receive(:tirar).and_raise(ActiveRecord::StatementInvalid, 'caiu')

    described_class.perform_now(conversation.id, token)

    expect(marca).to include('revalidacao_falhou' => true, 'razao' => 'cliente pediu a cotação e o robô falhou')
  end

  # ALTO 1: o prazo total (10 min desde a primeira releitura desta espera) vence também para o job: não chama a IA.
  it 'prazo total vencido: o job não chama a IA' do
    token
    travel(11.minutes) { described_class.perform_now(conversation.id, token) }

    expect(Crm::Ai::RevalidaPassagem).not_to have_received(:new)
  end

  it 'o prazo vence durante a chamada: a resposta não é aplicada', :aggregate_failures do
    allow(revalida).to receive(:call) do
      travel(11.minutes)
      resposta(false, 'resolvido')
    end

    described_class.perform_now(conversation.id, token)

    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(true)
    expect(retiradas).to be_empty
  end

  it 'o job de uma releitura que já não existe não chama a IA' do
    token
    described_class.perform_now(conversation.id, '2000-01-01T00:00:00.000000Z')

    expect(Crm::Ai::RevalidaPassagem).not_to have_received(:new)
  end
end
