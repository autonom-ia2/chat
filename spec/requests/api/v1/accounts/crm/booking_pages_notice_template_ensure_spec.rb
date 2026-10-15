require 'rails_helper'

# Disparos de produto da criação dos modelos v2 dos avisos (#1524, `Crm::BookingNoticeTemplateEnsure`): publicar a
# página e trocar a caixa de avisos de uma página publicada, pelo painel. Só enfileira; a Meta nunca é chamada aqui.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages notice template ensure', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }
  let(:page) { world.profile }
  let(:member) { "/api/v1/accounts/#{account.id}/crm/booking_pages/#{page.id}" }
  let(:job) { Crm::BookingV2::NoticeTemplateEnsureJob }
  let(:cloud) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:waha) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }).inbox }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Whatsapp::Templates::MetaClient).to receive(:new).and_raise('a Meta não pode ser chamada na requisição')
  end

  def autorizar
    WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU,
                                    versao_aviso: 'v1', texto_aviso: 'Aviso.')
  end

  def publish
    post "#{member}/publish", headers: admin.create_new_auth_token, as: :json
  end

  def trocar_caixa(inbox)
    patch member, params: { booking_page: { notice_inbox_id: inbox.id } }, headers: admin.create_new_auth_token, as: :json
  end

  # Página que passa a publicada com caixa oficial e o dono já autorizou: os modelos dela precisam existir.
  it 'publicar com autorização: enfileira a criação para a caixa de avisos' do
    page.update!(enabled: false, notice_inbox: cloud)
    autorizar

    expect { publish }.to have_enqueued_job(job).with(account.id, cloud.id)
    expect(response).to have_http_status(:ok)
  end

  # Sem a autorização do dono, publicar não cria nada na Meta (mexe com dinheiro).
  it 'publicar sem autorização: não enfileira' do
    page.update!(enabled: false, notice_inbox: cloud)

    expect { publish }.not_to have_enqueued_job(job)
    expect(response).to have_http_status(:ok)
  end

  # A caixa de avisos de uma página já publicada passa a ser a oficial: ela ganha os modelos.
  it 'trocar a caixa de uma página publicada para a oficial: enfileira para a caixa nova' do
    page.update!(notice_inbox: waha)
    autorizar

    expect { trocar_caixa(cloud) }.to have_enqueued_job(job).with(account.id, cloud.id)
    expect(response).to have_http_status(:ok)
  end

  # WAHA não usa modelo da Meta: trocar para ela não cria nada.
  it 'trocar para uma caixa WAHA: não enfileira' do
    page.update!(notice_inbox: cloud)
    autorizar

    expect { trocar_caixa(waha) }.not_to have_enqueued_job(job)
  end

  # Rascunho não manda aviso: trocar a caixa dele não cria modelo (cria quando for publicado).
  it 'trocar a caixa de uma página não publicada: não enfileira' do
    page.update!(enabled: false)
    autorizar

    expect { trocar_caixa(cloud) }.not_to have_enqueued_job(job)
  end

  # Gravar outra coisa numa página publicada não repete o pedido.
  it 'salvar outro campo de uma página publicada com caixa oficial: não enfileira' do
    page.update!(notice_inbox: cloud)
    autorizar

    expect do
      patch member, params: { booking_page: { title: 'Outro título' } }, headers: admin.create_new_auth_token, as: :json
    end.not_to have_enqueued_job(job)
  end
end
