require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::LerAntigosJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:alvo) { { 'kind' => 'post', 'perfil' => 'instagram-1', 'post_id' => '1790', 'networks' => ['instagram'], 'inbox_id' => inbox.id } }
  let(:fonte) { instance_double(Crm::MetaAds::ComentariosIa::Fonte) }
  let!(:care) do
    create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '1790', inbox: inbox, started_at: 2.days.ago,
                                       read_old_at: Time.current)
  end

  def linha(id, dias:)
    { id: id, network: 'instagram', author: "pessoa#{id}", text: "texto #{id}", momento: dias.days.ago, inbox_id: inbox.id, post_id: '1790' }
  end

  before { allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:do_alvo).and_return(fonte) }

  it 'põe na fila só os de até 7 dias que chegaram antes de ligar' do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', dias: 3), linha('2', dias: 1), linha('3', dias: 9)],
                                               escondidas: [] })

    described_class.perform_now(account.id, alvo)

    cuidar = enqueued_jobs.select { |job| job['job_class'] == 'Crm::MetaAds::ComentariosIa::CuidarJob' }
    expect(cuidar.map { |job| job['arguments'].first['comment_id'] }).to eq(%w[1])
  end

  it 'Meta fora do ar: tenta de novo poucas vezes e, esgotado, solta o "Ler e mandar" para o dono tentar de novo' do
    allow(fonte).to receive(:ler).and_return({ status: 'meta_unavailable', linhas: [], escondidas: [] })
    allow(Rails.logger).to receive(:warn)

    perform_enqueued_jobs { described_class.perform_later(account.id, alvo) }

    expect(fonte).to have_received(:ler).exactly(described_class::TENTATIVAS).times
    expect(care.reload.read_old_at).to be_nil
    expect(Rails.logger).to have_received(:warn).with(a_string_including("care=#{care.id}").and(satisfy { |log| log.exclude?('texto') }))
  end

  it 'recusa que não passa com o tempo (sem permissão): solta na hora, sem tentar de novo' do
    allow(fonte).to receive(:ler).and_return({ status: 'needs_permission', linhas: [], escondidas: [] })

    perform_enqueued_jobs { described_class.perform_later(account.id, alvo) }

    expect(fonte).to have_received(:ler).once
    expect(care.reload.read_old_at).to be_nil
  end

  it 'o perfil, a conexão ou o anúncio não existem mais: solta na hora, sem tentar de novo' do
    allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:do_alvo).and_return(nil)

    perform_enqueued_jobs { described_class.perform_later(account.id, alvo) }

    expect(Crm::MetaAds::ComentariosIa::Fonte).to have_received(:do_alvo).once
    expect(care.reload.read_old_at).to be_nil
  end

  it 'a leitura do anúncio falha antes dos comentários: Meta fora do ar tenta de novo; o resto solta na hora' do
    allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:do_alvo).and_raise(Crm::MetaAds::AdManagement::Error.new('meta_unavailable'))

    perform_enqueued_jobs { described_class.perform_later(account.id, alvo) }

    expect(Crm::MetaAds::ComentariosIa::Fonte).to have_received(:do_alvo).exactly(described_class::TENTATIVAS).times
    expect(care.reload.read_old_at).to be_nil

    care.update!(read_old_at: Time.current)
    allow(Crm::MetaAds::ComentariosIa::Fonte).to receive(:do_alvo).and_raise(Crm::MetaAds::AdManagement::Error.new('needs_login'))

    perform_enqueued_jobs { described_class.perform_later(account.id, alvo) }

    expect(care.reload.read_old_at).to be_nil
  end
end
