require 'rails_helper'

RSpec.describe Autonomia::Decisores::DuvidaJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming,
                     content: 'Queria saber o preço do seguro do meu carro')
  end
  let(:decisor) { create(:autonomia_decisor, account: account) }
  let(:rule) do
    create(:automation_rule, account: account,
                             event_name: 'message_created',
                             conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }],
                             actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] },
                                       { action_name: 'add_label', action_params: ['lead'] }])
  end
  let!(:decisao) do
    create(:autonomia_decisor_decisao, decisor: decisor, conversation: conversation, message: message, automation_rule: rule,
                                       esperas: [{ 'regra' => rule.id, 'indice' => 0 }], status: 'duvida', resposta: 'sim', certeza: 0.6)
  end
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def guia_responde(resposta:, seguro:)
    allow(cliente).to receive(:create).and_return(text: { resposta: resposta, seguro: seguro, motivo: 'Pede preço de seguro auto.' }.to_json)
  end

  it 'Guia seguro: decide, vira exemplo de origem guia e retoma a automação' do
    guia_responde(resposta: 'sim', seguro: true)

    expect { described_class.perform_now(decisao.id) }
      .to have_enqueued_job(Autonomia::Decisores::PerguntarJob).with(rule.id, conversation.id, message.id, 0, true)

    expect(decisao.reload).to have_attributes(status: 'decidida_pelo_guia', resposta: 'sim', motivo: 'Pede preço de seguro auto.')
    expect(decisor.reload.exemplos.last).to include('resposta' => 'sim', 'origem' => 'guia', 'decisao_id' => decisao.id)
    expect(decisor.exemplos.last['texto']).to include('preço do seguro')
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'decisor_duvida', account: account))
  end

  it 'a pessoa resolveu enquanto o Guia pensava: o Guia não grava por cima nem retoma de novo' do
    allow(cliente).to receive(:create) do
      Autonomia::Decisores::Resolucao.new(decisao: Autonomia::DecisorDecisao.find(decisao.id), user: nil).resolver!('nao')
      { text: { resposta: 'sim', seguro: true, motivo: 'Pede preço.' }.to_json }
    end

    expect { described_class.perform_now(decisao.id) }.to have_enqueued_job(Autonomia::Decisores::PerguntarJob).exactly(:once)

    expect(decisao.reload).to have_attributes(status: 'resolvida', resposta: 'nao')
    expect(decisor.reload.exemplos.map { |exemplo| exemplo['origem'] }).to eq(['pessoa'])
  end

  it 'conversa sem texto: o Guia decide e a automação retoma, sem travar no exemplo' do
    message.update!(content: nil)
    guia_responde(resposta: 'sim', seguro: true)

    expect { described_class.perform_now(decisao.id) }.to have_enqueued_job(Autonomia::Decisores::PerguntarJob)

    expect(decisao.reload.status).to eq('decidida_pelo_guia')
    expect(decisor.reload.exemplos).to be_empty
  end

  it 'a retomada roda os passos seguintes sem perguntar ao Jev de novo' do
    guia_responde(resposta: 'sim', seguro: true)

    perform_enqueued_jobs { described_class.perform_now(decisao.id) }

    expect(conversation.reload.label_list).to eq(['lead'])
  end

  it 'Guia inseguro: espera uma pessoa e agenda o vencimento em 2 dias' do
    guia_responde(resposta: 'sim', seguro: false)

    expect { described_class.perform_now(decisao.id) }.to have_enqueued_job(Autonomia::Decisores::VencerJob).with(decisao.id)
    expect(decisao.reload.status).to eq('esperando_pessoa')
    expect(decisor.reload.exemplos).to be_empty
  end

  it 'sem chave de IA na conta, o caso espera uma pessoa' do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

    described_class.perform_now(decisao.id)

    expect(decisao.reload).to have_attributes(status: 'esperando_pessoa')
    expect(decisao.motivo).to include('ia_nao_configurada')
  end

  it 'caso parado vence depois de 2 dias e não retoma mais' do
    decisao.update!(status: 'esperando_pessoa')

    travel_to(3.days.from_now) { Autonomia::Decisores::VencerJob.perform_now(decisao.id) }

    expect(decisao.reload.status).to eq('vencida')
  end
end
