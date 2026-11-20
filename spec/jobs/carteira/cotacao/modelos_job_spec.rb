require 'rails_helper'

# #3055: o pedido à Meta dos 2 modelos da cotação da renovação, no molde do NoticeTemplateEnsureJob do Agendamento. A
# Meta é sempre o `MetaClient` falso: nada sai daqui. Tudo fictício.
RSpec.describe Carteira::Cotacao::ModelosJob do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:client) { instance_double(Whatsapp::Templates::MetaClient) }
  let(:garantir) { Whatsapp::Templates::Garantir }
  let(:nomes) { %w[renovacao_algo_mudou_v1 renovacao_proposta_v1] }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    allow(Whatsapp::Templates::MetaClient).to receive(:new).and_return(client)
    allow(client).to receive(:upload_media).and_return('4::handle-exemplo')
    allow(client).to receive(:create) do |corpo|
      Whatsapp::Templates::MetaClient::Outcome.new(template: corpo.merge('id' => SecureRandom.hex(4), 'status' => 'PENDING'), created: true)
    end
    allow(garantir).to receive(:call).and_call_original
  end

  def autorizar(acao = WhatsappTemplateConsent::LIGOU, marca: 'utility')
    WhatsappTemplateConsent.create!(account: account, marca: marca, acao: acao, versao_aviso: 'v1', texto_aviso: 'Aviso.')
  end

  def nomes_na_lista(inbox)
    Array(inbox.channel.reload.message_templates).pluck('name')
  end

  # Motivo: o caminho feliz. A caixa escolhida em Ajustar renovações ganha os 2 modelos; outra caixa oficial da conta,
  # não. O pedido vai com `criar: true` (o Envio só lê).
  it 'cotação aberta e Aviso de serviço ligado: pede os 2 modelos só na caixa escolhida' do
    outra = caixa_oficial(account, nome: 'Outra caixa')
    cotacao_ligada(account, user: admin, caixa: caixa)
    autorizar

    described_class.perform_now(account.id)

    expect(nomes_na_lista(caixa)).to match_array(nomes)
    expect(nomes_na_lista(outra)).to be_empty
    expect(garantir).to have_received(:call).with(inbox: caixa, finalidade: 'renovacao_algo_mudou', criar: true)
    expect(garantir).to have_received(:call).with(inbox: caixa, finalidade: 'renovacao_proposta', criar: true)
    expect(client).to have_received(:create).twice
  end

  # Motivo: os 3 gatilhos podem disparar juntos; repetir não fala com a Meta para o que já está em análise.
  it 'repetido: não pede de novo o que já está em análise' do
    cotacao_ligada(account, user: admin, caixa: caixa)
    autorizar

    2.times { described_class.perform_now(account.id) }

    expect(client).to have_received(:create).twice
  end

  # Motivo: sem a chave da cotação, a renovação é a da E5 e nenhum dos 2 modelos é usado.
  it 'sem a chave da cotação: nada' do
    cotacao_ligada(account, user: admin, caixa: caixa)
    Carteira::Cotacao::Liberada.desligar!(account)
    autorizar

    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
  end

  # Motivo: "ninguém cota" fecha a cotação: o portão é o mesmo do resto da E8 (Carteira::Cotacao.aberta?).
  it 'ninguém cota: nada' do
    cotacao_ligada(account, user: admin, caixa: caixa, quem_cota: 'ninguem')
    autorizar

    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
  end

  # Motivo: sem ajustes ou sem caixa escolhida, não há onde pedir.
  it 'sem ajustes ou sem caixa: nada' do
    autorizar
    described_class.perform_now(account.id)

    cotacao_ligada(account, user: admin, caixa: nil)
    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
  end

  # Motivo: mexe com dinheiro. Sem o Aviso de serviço ligado (ou desligado depois), ou só com a Divulgação, nada é
  # pedido: os 2 modelos são de utilidade.
  it 'sem o Aviso de serviço: nada' do
    cotacao_ligada(account, user: admin, caixa: caixa)
    autorizar(marca: 'marketing')
    described_class.perform_now(account.id)

    autorizar
    autorizar(WhatsappTemplateConsent::DESLIGOU)
    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
    expect(client).not_to have_received(:create)
  end

  # Motivo: só o WhatsApp oficial Cloud cria modelo pela API da Meta.
  it 'caixa que não é do WhatsApp oficial Cloud: nada' do
    api = create(:channel_api, account: account).inbox
    cotacao_ligada(account, user: admin, caixa: api)
    autorizar

    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
  end

  # Motivo: um erro inesperado numa finalidade vai ao tracker e não impede a outra.
  it 'erro numa finalidade não para a outra' do
    cotacao_ligada(account, user: admin, caixa: caixa)
    autorizar
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    allow(garantir).to receive(:call).with(hash_including(finalidade: 'renovacao_algo_mudou')).and_raise(StandardError)

    described_class.perform_now(account.id)

    expect(nomes_na_lista(caixa)).to eq(['renovacao_proposta_v1'])
    expect(tracker).to have_received(:capture_exception).once
  end

  # Motivo: Meta fora do ar não perde o pedido, e não insiste na Meta caída: a 2ª finalidade fica para a nova tentativa.
  it 'Meta fora do ar: para na 1ª finalidade e reagenda o job' do
    cotacao_ligada(account, user: admin, caixa: caixa)
    autorizar
    allow(client).to receive(:create).and_raise(Whatsapp::Templates::MetaClient::Unreachable)

    expect { described_class.perform_now(account.id) }.to have_enqueued_job(described_class).with(account.id)

    expect(garantir).to have_received(:call).once
    expect(garantir).to have_received(:call).with(hash_including(finalidade: 'renovacao_algo_mudou'))
  end

  # Motivo: esgotadas as tentativas com a Meta fora, alguém precisa saber: tracker com a conta e a caixa (só ids).
  it 'Meta fora até o fim das tentativas: registra no tracker com conta e caixa' do
    cotacao_ligada(account, user: admin, caixa: caixa)
    autorizar
    allow(client).to receive(:create).and_raise(Whatsapp::Templates::MetaClient::Unreachable)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(account.id) }

    expect(client).to have_received(:create).exactly(3).times
    expect(ChatwootExceptionTracker).to have_received(:new).once.with(
      an_instance_of(described_class::MetaFora).and(having_attributes(message: "account_id=#{account.id} inbox_id=#{caixa.id}")),
      account: account
    )
    expect(tracker).to have_received(:capture_exception).once
  end
end
