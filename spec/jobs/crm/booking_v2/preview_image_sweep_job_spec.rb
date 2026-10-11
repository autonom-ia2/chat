require 'rails_helper'

# Varredura de pré-aquecimento (#1303): quando o desenho da prévia muda, as imagens guardadas de todas as páginas
# ficam velhas. A varredura passa pelas páginas no ar, em lotes, e desenha em job.
RSpec.describe Crm::BookingV2::PreviewImageSweepJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:draw_limit) { Crm::BookingV2::PreviewImage::DrawLimit }
  let(:renderer) { Crm::BookingV2::PreviewImage::Renderer }
  let(:warm_job) { Crm::BookingV2::PreviewImageWarmJob }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    clear_slots
    allow(renderer).to receive(:png).and_return(Rails.root.join('spec/assets/avatar.png').binread)
  end

  after { clear_slots }

  def clear_slots
    draw_limit::MAX_LIMIT.times { |index| Redis::Alfred.delete(draw_limit.slot_key(index)) }
    Redis::Alfred.delete(draw_limit.account_key(account.id))
    warmup = Crm::BookingV2::PreviewImage::Warmup
    Crm::AgentBookingProfile.where(account: account).pluck(:id).each { |id| Redis::Alfred.delete(warmup.queued_key(id)) }
  end

  def page(**attrs)
    create_booking_profile(account: account, host: world.host, **attrs)
  end

  it 'entra na fila de baixa prioridade' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue('low')
  end

  it 'desenha as páginas novas no ar e pula as pausadas e as antigas' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    live = [world.profile, page]
    off = [page(enabled: false), page(page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox)]

    described_class.perform_now

    expect(live.map { |item| item.reload.preview_image.attached? }).to eq([true, true])
    expect(off.map { |item| item.reload.preview_image.attached? }).to eq([false, false])
  end

  it 'anda em lotes: cada job faz um lote e deixa o seguinte na fila, a partir da última página' do
    stub_const("#{described_class}::BATCH", 2)
    pages = [world.profile, page, page]

    expect { described_class.perform_now }.to have_enqueued_job(described_class).with(pages[1].id)
    expect(pages.map { |item| item.reload.preview_image.attached? }).to eq([true, true, false])

    perform_enqueued_jobs(only: described_class)
    expect(pages.last.reload.preview_image).to be_attached
  end

  it 'rodar de novo não desenha o que já está guardado' do
    world.profile
    2.times { described_class.perform_now }

    expect(renderer).to have_received(:png).once
  end

  it 'respeita o teto global: com ele cheio não desenha, manda a página para o job dela e segue' do
    pages = [world.profile, page]
    draw_limit.limit.times { |index| Redis::Alfred.set(draw_limit.slot_key(index), 'outro-processo', nx: true, ex: 30) }

    expect { described_class.perform_now }
      .to have_enqueued_job(warm_job).with(pages[0].id).and have_enqueued_job(warm_job).with(pages[1].id)

    expect(renderer).not_to have_received(:png)
  end
end
