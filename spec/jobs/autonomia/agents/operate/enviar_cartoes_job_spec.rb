require 'rails_helper'

# #1479 F3: o mapa e o cartão de contato do turno saem por um job, DEPOIS que a mensagem âncora (o texto, o áudio, o
# último pedaço) saiu para o canal. Âncora que falhou: nenhum cartão. Âncora ainda pendente: reagenda até o teto, e
# desiste com registro. Cada cartão sai uma vez só, em ordem, e um erro ao postar o cartão não toca no texto.
RSpec.describe Autonomia::Agents::Operate::EnviarCartoesJob do
  include ActiveJob::TestHelper

  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:mapa) do
    { 'tipo' => 'location', 'chave' => 'a1b2c3d4', 'token' => 'mensagem:9:cartao:location:a1b2c3d4',
      'rich_message' => { 'type' => 'location', 'latitude' => -23.5489, 'longitude' => -46.6388, 'name' => 'Unidade Centro',
                          'address' => 'Rua Direita, 100' } }
  end
  let(:cartao_de_contato) do
    { 'tipo' => 'contact', 'chave' => 'pagina', 'token' => 'mensagem:9:cartao:contact:pagina',
      'rich_message' => { 'type' => 'contact', 'name' => 'Clínica', 'phone' => '+551140000473' } }
  end
  let(:logs) { [] }

  def ancora(cartoes, **atributos)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Fica no Centro.',
                     sender: agent_bot, content_attributes: { 'autonomia_agent_id' => 7, 'autonomia_cartoes' => cartoes }, **atributos)
  end

  def cartoes_enviados
    conversation.messages.outgoing.order(:id).select { |mensagem| mensagem.content_attributes.key?('autonomia_cartao_token') }
  end

  def reagendados
    enqueued_jobs.count { |item| item[:job] == described_class }
  end

  before do
    clear_enqueued_jobs
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:warn).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_including('[autonomia][turno]')) { |linha| logs << linha }
    allow(Rails.logger).to receive(:warn).with(a_string_including('cartao')) { |linha| logs << linha }
  end

  it 'âncora que saiu: os cartões em ordem, com o formato, o robô da âncora e o token; o 2º espera o 1º sair' do
    mensagem = ancora([mapa, cartao_de_contato], source_id: 'wamid.TEXTO')
    described_class.perform_now(mensagem.id)

    expect(cartoes_enviados.map { |cartao| cartao.content_attributes.dig('rich_message', 'type') }).to eq(%w[location])
    expect(reagendados).to eq(1)
    cartoes_enviados.first.update!(source_id: 'wamid.MAPA')
    described_class.perform_now(mensagem.id)

    expect(cartoes_enviados.map { |cartao| cartao.content_attributes.dig('rich_message', 'type') }).to eq(%w[location contact])
    expect(cartoes_enviados.first).to have_attributes(content: '', sender: agent_bot)
    expect(cartoes_enviados.first.content_attributes).to include('autonomia_agent_id' => 7, 'autonomia_cartao_token' => mapa['token'])
    expect(cartoes_enviados.first.content_attributes).not_to have_key('autonomia_reply_to_message_id')
  end

  it 'idempotente: o job que roda duas vezes não repete o cartão' do
    mensagem = ancora([mapa], source_id: 'wamid.TEXTO')
    2.times { described_class.perform_now(mensagem.id) }
    expect(cartoes_enviados.size).to eq(1)
  end

  it 'âncora que falhou: nenhum cartão, com registro' do
    mensagem = ancora([mapa], status: :failed)
    described_class.perform_now(mensagem.id)

    expect(cartoes_enviados).to be_empty
    expect(reagendados).to eq(0)
    expect(logs.join).to include('cartao_nao_enviado', "conv=#{conversation.id}", "msg=#{mensagem.id}", 'motivo=anterior_falhou')
  end

  it 'âncora pendente: reagenda com a espera curta; passado o teto, desiste com registro e não reagenda mais' do
    mensagem = ancora([mapa])
    described_class.perform_now(mensagem.id)
    expect(cartoes_enviados).to be_empty
    reagendado = enqueued_jobs.select { |item| item[:job] == described_class }.sole
    expect(reagendado[:args]).to eq([mensagem.id])
    expect(reagendado[:at]).to be_within(1).of((Time.current + described_class::ESPERA).to_f)

    clear_enqueued_jobs
    travel(described_class::TETO + 1.second) { described_class.perform_now(mensagem.id) }

    expect(cartoes_enviados).to be_empty
    expect(reagendados).to eq(0)
    expect(logs.join).to include('cartao_nao_enviado', 'motivo=anterior_pendente')
  end

  it 'âncora pendente que sai depois: o cartão sai no reagendamento' do
    mensagem = ancora([mapa])
    described_class.perform_now(mensagem.id)
    mensagem.update!(source_id: 'wamid.TEXTO')
    perform_enqueued_jobs(only: described_class)
    expect(cartoes_enviados.size).to eq(1)
  end

  it 'erro ao postar o cartão: registra só ids e a classe, e o texto fica como está' do
    mensagem = ancora([mapa], source_id: 'wamid.TEXTO')
    allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)

    expect { described_class.perform_now(mensagem.id) }.not_to raise_error
    expect(mensagem.reload).to have_attributes(content: 'Fica no Centro.', status: 'sent')
    expect(logs.join).to include('cartao_falhou', "msg=#{mensagem.id}", 'ActiveRecord::RecordInvalid')
    expect(logs.join).not_to include('Rua Direita')
  end

  it 'sem âncora ou sem cartões: nada' do
    expect { described_class.perform_now(0) }.not_to raise_error
    described_class.perform_now(ancora([], source_id: 'wamid.TEXTO').id)
    expect(cartoes_enviados).to be_empty
    expect(reagendados).to eq(0)
  end

  context 'when the inbox does not take the format (site chat)' do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

    it 'saiu ao gravar: os dois cartões de uma vez, em texto, sem rich_message' do
      described_class.perform_now(ancora([mapa, cartao_de_contato]).id)

      expect(cartoes_enviados.size).to eq(2)
      expect(cartoes_enviados.first.content).to eq("Unidade Centro\nRua Direita, 100\nhttps://maps.google.com/?q=-23.5489,-46.6388")
      expect(cartoes_enviados.first.content_attributes).not_to have_key('rich_message')
    end
  end
end
