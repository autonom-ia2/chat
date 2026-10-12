require 'rails_helper'

# Pré-aquecimento da imagem de prévia do link (#1303): o desenho sai do pedido web e vai para job. O desenho é trocado
# por um PNG pronto, menos no exemplo que usa a libvips de verdade.
RSpec.describe Crm::BookingV2::PreviewImageWarmJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account, host_name: 'Ana Souza') }
  let(:profile) { world.profile }
  let(:draw_limit) { Crm::BookingV2::PreviewImage::DrawLimit }
  let(:renderer) { Crm::BookingV2::PreviewImage::Renderer }
  let(:drawn) { Rails.root.join('spec/assets/avatar.png').binread }
  # Criada antes de os jobs rodarem: criar a página dentro do bloco rodaria também os jobs de quem atende.
  let!(:page_id) { profile.id }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://chat.exemplo.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    clear_slots
    allow(renderer).to receive(:png).and_return(drawn)
  end

  after { clear_slots }

  def clear_slots
    draw_limit::MAX_LIMIT.times { |index| Redis::Alfred.delete(draw_limit.slot_key(index)) }
    Redis::Alfred.delete(draw_limit.account_key(account.id))
    Redis::Alfred.delete(Crm::BookingV2::PreviewImage::Warmup.queued_key(page_id))
  end

  def fill_slots
    draw_limit.limit.times { |index| Redis::Alfred.set(draw_limit.slot_key(index), 'outro-processo', nx: true, ex: 30) }
  end

  def content_for(slug)
    Crm::BookingV2::PreviewImage::Content.new(Crm::BookingV2::LinkPreview.for_slug(slug))
  end

  it 'later_once: um job só esperando por página; a marca sai quando o job começa' do
    warmup = Crm::BookingV2::PreviewImage::Warmup

    expect { 3.times { warmup.later_once(profile) } }.to have_enqueued_job(described_class).with(page_id).once
    described_class.perform_now(page_id)
    expect(Redis::Alfred.exists?(warmup.queued_key(page_id))).to be(false)
    expect { warmup.later_once(profile) }.to have_enqueued_job(described_class).with(page_id).once
  end

  it 'entra na fila de baixa prioridade pelo perform_later' do
    expect { described_class.perform_later(profile.id) }.to have_enqueued_job(described_class).with(profile.id).on_queue('low')
  end

  it 'desenha e guarda a imagem na versão atual: quem pedir depois só lê' do
    perform_enqueued_jobs(only: described_class) { described_class.perform_later(page_id) }

    expect(profile.reload.preview_image.filename.to_s).to eq("preview-#{content_for(profile.slug).version}.png")
    expect(Crm::BookingV2::PreviewImage::Store.new(content_for(profile.slug)).stored).to eq(drawn)
    expect(renderer).to have_received(:png).once
  end

  it 'desenha de verdade com a libvips' do
    begin
      require 'image_processing/vips'
    rescue LoadError => e
      skip "libvips indisponível nesta máquina: #{e.class}"
    end
    allow(renderer).to receive(:png).and_call_original

    described_class.perform_now(profile.id)

    image = Vips::Image.new_from_buffer(profile.reload.preview_image.download, '')
    expect([image.width, image.height]).to eq([1200, 630])
  end

  it 'é idempotente: imagem já guardada na versão atual não é desenhada de novo' do
    2.times { described_class.perform_now(profile.id) }

    expect(renderer).to have_received(:png).once
    expect(ActiveStorage::Attachment.where(record: profile, name: 'preview_image').count).to eq(1)
  end

  it 'redesenha quando a página muda' do
    described_class.perform_now(profile.id)
    profile.update!(title: 'Outro nome')

    described_class.perform_now(profile.id)

    expect(renderer).to have_received(:png).twice
    expect(profile.reload.preview_image.filename.to_s).to eq("preview-#{content_for(profile.slug).version}.png")
  end

  it 'desenha a imagem de cada link por pessoa' do
    colleague = create(:user, account: account, role: :agent, name: 'Bruno Lima')
    Crm::BookingV2::PagePeople.new(profile).assign!([world.host.id, colleague.id])

    described_class.perform_now(profile.id)

    expect(profile.reload.agent_booking_links.map { |link| link.preview_image.attached? }).to eq([true, true])
    expect(profile.preview_image).not_to be_attached
  end

  it 'não faz nada para página pausada, antiga, apagada ou de conta sem a flag' do
    paused = create_booking_profile(account: account, host: world.host, enabled: false)
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    legacy = create_booking_profile(account: account, host: world.host, page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox)

    [paused.id, legacy.id, 0].each { |id| described_class.perform_now(id) }
    account.disable_features('crm_booking_v2')
    account.save!
    described_class.perform_now(profile.id)

    expect(renderer).not_to have_received(:png)
  end

  describe 'teto global de desenhos' do
    it 'cheio: não desenha e volta para a fila para tentar depois' do
      fill_slots

      expect { described_class.perform_now(profile.id) }.to have_enqueued_job(described_class).with(profile.id)

      expect(renderer).not_to have_received(:png)
      expect(profile.reload.preview_image).not_to be_attached
    end

    it 'cheio o tempo todo: desiste depois das tentativas, com registro, sem desenhar' do
      fill_slots
      allow(Rails.logger).to receive(:warn)
      allow(Crm::BookingV2::PreviewImage::Warmup).to receive(:page).and_call_original

      perform_enqueued_jobs(only: described_class) { described_class.perform_later(page_id) }

      expect(Crm::BookingV2::PreviewImage::Warmup).to have_received(:page).exactly(described_class::ATTEMPTS).times
      expect(renderer).not_to have_received(:png)
      expect(Rails.logger).to have_received(:warn).with("Booking preview warmup gave up: draw limit still full for page #{profile.id}").once
    end

    it 'desenha quando a vaga abre, e solta a vaga ao terminar' do
      fill_slots
      described_class.perform_now(profile.id)
      clear_slots

      perform_enqueued_jobs

      expect(profile.reload.preview_image).to be_attached
      expect(Redis::Alfred.exists?(draw_limit.slot_key(0))).to be(false)
    end
  end

  describe 'falha no desenho' do
    let(:store) { Crm::BookingV2::PreviewImage::Store.new(content_for(profile.slug)) }

    after { Redis::Alfred.delete(store.failure_key) }

    it 'registra, solta a vaga e não tenta de novo a cada job' do
      allow(renderer).to receive(:png).and_raise(LoadError, 'cannot load such file -- vips')
      allow(Rails.logger).to receive(:error)

      2.times { described_class.perform_now(profile.id) }

      expect(renderer).to have_received(:png).once
      expect(Rails.logger).to have_received(:error).with('Booking preview warmup failed: LoadError').once
      expect(Redis::Alfred.exists?(draw_limit.slot_key(0))).to be(false)
      expect(Redis::Alfred.exists?(store.lock_key)).to be(false)
    end
  end
end
