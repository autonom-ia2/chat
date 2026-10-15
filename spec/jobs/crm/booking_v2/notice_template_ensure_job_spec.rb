require 'rails_helper'

# Criação dos 4 modelos v2 dos avisos (#1524, épico #1585). A Meta é sempre o `MetaClient` falso: nada sai daqui.
RSpec.describe Crm::BookingV2::NoticeTemplateEnsureJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:host) { create(:user, account: account, role: :administrator) }
  let(:client) { instance_double(Whatsapp::Templates::MetaClient) }
  let(:garantir) { Whatsapp::Templates::Garantir }
  let(:nomes_v2) { %w[agendamento_ao_marcar_v2 agendamento_horario_mudou_v2 agendamento_1_dia_antes_v2 agendamento_1_hora_antes_v2] }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Whatsapp::Templates::MetaClient).to receive(:new).and_return(client)
    allow(client).to receive(:create) do |corpo|
      Whatsapp::Templates::MetaClient::Outcome.new(template: corpo.merge('id' => SecureRandom.hex(4), 'status' => 'PENDING'), created: true)
    end
    allow(garantir).to receive(:call).and_call_original
  end

  def cloud_inbox
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: []).inbox
  end

  def page_with(inbox, enabled: true)
    create_booking_profile(account: account, host: host, notice_inbox: inbox, enabled: enabled)
  end

  def autorizar(acao = WhatsappTemplateConsent::LIGOU)
    WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: acao, versao_aviso: 'v1', texto_aviso: 'Aviso.')
  end

  def nomes_na_lista(inbox)
    Array(inbox.channel.reload.message_templates).pluck('name')
  end

  # Caminho feliz: cada caixa oficial com página publicada ganha os 4 modelos, e duas páginas na mesma caixa não
  # repetem a criação (a Meta só pode receber cada nome uma vez por caixa).
  it 'com autorização: cria os 4 por caixa oficial publicada, sem repetir caixa' do
    primeira = cloud_inbox
    segunda = cloud_inbox
    page_with(primeira)
    page_with(primeira)
    page_with(segunda)
    autorizar

    described_class.perform_now(account.id)

    expect(nomes_na_lista(primeira)).to match_array(nomes_v2)
    expect(nomes_na_lista(segunda)).to match_array(nomes_v2)
    expect(client).to have_received(:create).exactly(8).times
    expect(garantir).to have_received(:call).with(hash_including(criar: true)).exactly(8).times
  end

  # Rodar de novo (outro gatilho, nova tentativa) não cria de novo: o que está em análise vem da lista da caixa.
  it 'repetido: não fala com a Meta outra vez para o que já está em análise' do
    page_with(cloud_inbox)
    autorizar

    2.times { described_class.perform_now(account.id) }

    expect(client).to have_received(:create).exactly(4).times
  end

  # Mexe com dinheiro: sem o Aviso de serviço ligado (ou desligado depois), nada é criado nem consultado com criar.
  it 'sem autorização: não chama o Garantir com criar' do
    page_with(cloud_inbox)
    autorizar
    autorizar(WhatsappTemplateConsent::DESLIGOU)

    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
    expect(client).not_to have_received(:create)
  end

  # Agendamento desligado na conta: a página não manda aviso, então não cria modelo para ela.
  it 'agendamento desligado na conta: nada' do
    page_with(cloud_inbox)
    autorizar
    account.disable_features('crm_booking_v2')
    account.save!

    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
  end

  # Só o WhatsApp oficial Cloud cria modelo pela API da Meta: WAHA, canal API e 360dialog ficam de fora.
  it 'caixa WAHA, API de campanhas ou 360dialog: ignorada' do
    page_with(create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }).inbox)
    page_with(create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false).inbox)
    autorizar

    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
  end

  # Página pausada (ou rascunho) não manda aviso: a caixa dela não ganha modelo só por estar configurada.
  it 'página despublicada: ignorada' do
    page_with(cloud_inbox, enabled: false)
    autorizar

    described_class.perform_now(account.id)

    expect(garantir).not_to have_received(:call)
  end

  # O disparo de produto passa a caixa: só ela é tratada, e só se tiver página publicada.
  it 'com inbox_id: só aquela caixa, e só se tiver página publicada' do
    alvo = cloud_inbox
    outra = cloud_inbox
    page_with(alvo)
    page_with(outra)
    rascunho = cloud_inbox
    page_with(rascunho, enabled: false)
    autorizar

    described_class.perform_now(account.id, alvo.id)
    described_class.perform_now(account.id, rascunho.id)

    expect(nomes_na_lista(alvo)).to match_array(nomes_v2)
    expect(nomes_na_lista(outra)).to be_empty
    expect(nomes_na_lista(rascunho)).to be_empty
  end

  # Um erro inesperado numa finalidade vai ao tracker e não impede as outras 3 de serem criadas.
  it 'erro numa finalidade não para as outras' do
    inbox = cloud_inbox
    page_with(inbox)
    autorizar
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    allow(garantir).to receive(:call).with(hash_including(finalidade: 'agendamento_horario_mudou')).and_raise(StandardError)

    described_class.perform_now(account.id)

    expect(nomes_na_lista(inbox)).to match_array(nomes_v2 - ['agendamento_horario_mudou_v2'])
    expect(tracker).to have_received(:capture_exception).once
  end

  # Meta fora do ar não perde a criação: o job volta para a fila e tenta mais tarde.
  it 'Meta fora do ar: reagenda o job' do
    page_with(cloud_inbox)
    autorizar
    allow(client).to receive(:create).and_raise(Whatsapp::Templates::MetaClient::Unreachable)

    expect { described_class.perform_now(account.id) }.to have_enqueued_job(described_class).with(account.id)
  end

  # Não insistir na Meta caída: na 1ª finalidade com `meta_fora`, as outras 3 da MESMA caixa ficam para a nova
  # tentativa; a outra caixa segue normalmente.
  it 'meta_fora na 1ª finalidade: pula as outras 3 da caixa e segue nas outras caixas' do
    caida = cloud_inbox
    boa = cloud_inbox
    page_with(caida)
    page_with(boa)
    autorizar
    allow(garantir).to receive(:call).with(hash_including(inbox: caida)).and_return(status: :indisponivel, motivo: 'meta_fora')

    expect { described_class.perform_now(account.id) }.to have_enqueued_job(described_class).with(account.id)

    expect(garantir).to have_received(:call).with(hash_including(inbox: caida)).once
    expect(garantir).to have_received(:call).with(hash_including(inbox: caida, finalidade: 'agendamento_ao_marcar'))
    expect(nomes_na_lista(boa)).to match_array(nomes_v2)
  end

  # Esgotadas as tentativas com a Meta fora, alguém precisa saber: vai ao tracker com a conta e a caixa (só ids).
  it 'Meta fora até o fim das tentativas: registra no tracker com conta e caixa' do
    inbox = cloud_inbox
    page_with(inbox)
    autorizar
    allow(client).to receive(:create).and_raise(Whatsapp::Templates::MetaClient::Unreachable)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(account.id) }

    expect(client).to have_received(:create).exactly(3).times
    expect(ChatwootExceptionTracker).to have_received(:new).once.with(
      an_instance_of(described_class::MetaFora).and(having_attributes(message: "account_id=#{account.id} inbox_ids=#{inbox.id}")),
      account: account
    )
    expect(tracker).to have_received(:capture_exception).once
  end
end
