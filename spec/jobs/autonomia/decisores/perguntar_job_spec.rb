require 'rails_helper'

RSpec.describe Autonomia::Decisores::PerguntarJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'site@corretora.com', email: 'site@corretora.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming,
                     content: "Nome: Joana Lima\nTelefone: (11) 98888-7777")
  end
  let(:decisor) { create(:autonomia_decisor, account: account) }
  let(:rule) do
    create(:automation_rule, account: account,
                             event_name: 'message_created',
                             conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }],
                             actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] },
                                       { action_name: 'add_label', action_params: ['lead'] }])
  end
  let(:jev_url) { 'https://api.typesafe.ai/v1/systemone' }

  before do
    allow(TypesafeAi::Config).to receive_messages(api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
  end

  def jev_responde(choice, confidence)
    stub_request(:post, jev_url).to_return(
      status: 200,
      body: { model: 'jev-1.13.0', usage: { input_tokens: 800, output_tokens: 2 },
              answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }.to_json
    )
  end

  def rodar
    described_class.perform_now(rule.id, conversation.id, message.id, 0)
  end

  it 'segue para os próximos passos quando o Decisor responde a chave com certeza suficiente' do
    jev_responde('sim', 0.92)

    rodar

    expect(conversation.reload.label_list).to eq(['lead'])
    expect(Autonomia::DecisorDecisao.last).to have_attributes(status: 'decidida', resposta: 'sim', automation_rule_id: rule.id,
                                                              esperas: [{ 'regra' => rule.id, 'indice' => 0 }])
    expect(decisor.reload).to have_attributes(perguntas_count: 1, duvidas_count: 0)
    expect(decisor.ultima_pergunta_em).to be_present
  end

  it 'para quando a resposta é outra' do
    jev_responde('nao', 0.97)

    rodar

    expect(conversation.reload.label_list).to be_empty
    expect(Autonomia::DecisorDecisao.last.status).to eq('decidida')
  end

  it 'na dúvida não segue e manda a pergunta ao Guia' do
    jev_responde('sim', 0.55)

    expect { rodar }.to have_enqueued_job(Autonomia::Decisores::DuvidaJob)

    expect(conversation.reload.label_list).to be_empty
    expect(Autonomia::DecisorDecisao.last.status).to eq('duvida')
    expect(decisor.reload.duvidas_count).to eq(1)
  end

  it 'reaproveita a decisão já guardada para a mesma mensagem, sem chamar o Jev de novo' do
    create(:autonomia_decisor_decisao, decisor: decisor, conversation: conversation, message: message, resposta: 'sim')

    rodar

    expect(a_request(:post, jev_url)).not_to have_been_made
    expect(conversation.reload.label_list).to eq(['lead'])
  end

  it 'acima do limite mensal da conta não pergunta e não segue' do
    stub_const('Autonomia::Decisores::LIMITE_MENSAL', 1)
    create(:autonomia_decisor_decisao, decisor: decisor, conversation: conversation)

    rodar

    expect(a_request(:post, jev_url)).not_to have_been_made
    expect(Autonomia::DecisorDecisao.find_by(message_id: message.id).status).to eq('sem_cota')
    expect(conversation.reload.label_list).to be_empty
  end

  it 'não faz nada quando a regra foi desligada depois de enfileirar' do
    rule.update!(active: false)

    rodar

    expect(a_request(:post, jev_url)).not_to have_been_made
  end

  it 'conversa sem texto (só áudio ou imagem) não vai ao Jev e não segue' do
    message.update!(content: nil)

    rodar

    expect(a_request(:post, jev_url)).not_to have_been_made
    expect(Autonomia::DecisorDecisao.last).to have_attributes(status: 'sem_conteudo')
    expect(decisor.reload.perguntas_count).to eq(0)
    expect(conversation.reload.label_list).to be_empty
  end

  context 'with duas regras usando o mesmo Decisor' do
    let(:regra_do_nao) do
      create(:automation_rule, account: account,
                               event_name: 'message_created',
                               conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }],
                               actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'nao'] },
                                         { action_name: 'add_label', action_params: ['nao_lead'] }])
    end
    let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

    before do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
      allow(cliente).to receive(:create).and_return(text: { resposta: 'nao', seguro: true, motivo: 'Não pede seguro.' }.to_json)
    end

    it 'na dúvida as duas esperam, e quando o Guia decide retoma a regra da resposta dada' do
      jev_responde('sim', 0.6)

      rodar
      described_class.perform_now(regra_do_nao.id, conversation.id, message.id, 0)

      decisao = Autonomia::DecisorDecisao.sole
      expect(decisao.esperas).to contain_exactly({ 'regra' => rule.id, 'indice' => 0 }, { 'regra' => regra_do_nao.id, 'indice' => 0 })
      expect(a_request(:post, jev_url)).to have_been_made.once

      perform_enqueued_jobs { Autonomia::Decisores::DuvidaJob.perform_now(decisao.id) }

      expect(conversation.reload.label_list).to eq(['nao_lead'])
    end
  end

  context 'when a automação é retomada depois da dúvida' do
    let(:rule) do
      create(:automation_rule, account: account,
                               conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }],
                               actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] },
                                         { action_name: 'send_message', action_params: ['Recebemos seu pedido'] }])
    end

    before do
      create(:autonomia_decisor_decisao, decisor: decisor, conversation: conversation, message: message, automation_rule: rule,
                                         status: 'resolvida', resposta: 'sim', esperas: [{ 'regra' => rule.id, 'indice' => 0 }])
    end

    def enviadas
      conversation.messages.outgoing.where(content: 'Recebemos seu pedido').count
    end

    it 'a retomada repetida (Guia e pessoa, retry) roda os passos uma vez só' do
      2.times { described_class.perform_now(rule.id, conversation.id, message.id, 0, true) }

      expect(enviadas).to eq(1)
    end

    it 'não age quando as condições da regra não valem mais (conversa resolvida enquanto esperava)' do
      conversation.update!(status: :resolved)

      described_class.perform_now(rule.id, conversation.id, message.id, 0, true)

      expect(enviadas).to eq(0)
    end
  end

  context 'with campos declarados no Decisor' do
    let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

    before do
      decisor.update!(campos: [{ chave: 'nome', descricao: 'Nome', destino: 'contato.nome' },
                               { chave: 'telefone', descricao: 'Telefone', destino: 'contato.telefone' }])
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
      allow(cliente).to receive(:create).and_return(text: { nome: 'Joana Lima', telefone: '+5511988887777' }.to_json)
    end

    it 'extrai e grava no contato antes de seguir, e guarda só o que gravou' do
      jev_responde('sim', 0.9)

      rodar

      expect(contact.reload).to have_attributes(name: 'Joana Lima', phone_number: '+5511988887777')
      expect(Autonomia::DecisorDecisao.last.campos_extraidos).to eq('nome' => 'Joana Lima', 'telefone' => '+5511988887777')
      expect(conversation.reload.label_list).to eq(['lead'])
    end

    it 'não extrai quando a resposta não é a que segue' do
      jev_responde('nao', 0.9)

      rodar

      expect(cliente).not_to have_received(:create)
      expect(contact.reload.name).to eq('site@corretora.com')
    end

    # #1000 — o campo que não grava fica na decisão com o motivo, não só no log.
    it 'guarda na decisão o motivo do campo que não gravou' do
      allow(cliente).to receive(:create).and_return(text: { nome: 'Joana Lima', telefone: 'ligar à tarde' }.to_json)
      jev_responde('sim', 0.9)

      rodar

      decisao = Autonomia::DecisorDecisao.last
      expect(decisao.campos_extraidos).to eq('nome' => 'Joana Lima')
      expect(decisao.motivo).to include('telefone', 'fora do formato')
    end

    it 'segue mesmo quando a extração falha, guardando o motivo' do
      allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'network_timeout: read_timeout')
      jev_responde('sim', 0.9)

      rodar

      expect(conversation.reload.label_list).to eq(['lead'])
      expect(Autonomia::DecisorDecisao.last.motivo).to include('extração')
    end
  end
end
