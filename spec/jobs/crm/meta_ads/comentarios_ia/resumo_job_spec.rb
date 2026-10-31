require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::ResumoJob do
  let(:account) { create(:account) }
  let(:alvo) { { 'kind' => 'ad', 'ad_id' => '120', 'networks' => ['instagram'] } }

  it 'conta o resumo do alvo' do
    resumo = instance_double(Crm::MetaAds::ComentariosIa::Resumo, contar!: true)
    allow(Crm::MetaAds::ComentariosIa::Resumo).to receive(:new).with(account: account, alvo: alvo).and_return(resumo)

    described_class.perform_now(account.id, alvo)

    expect(resumo).to have_received(:contar!)
  end

  it 'sem nova tentativa: repetir a conta gastaria de novo a Meta e a IA' do
    expect(described_class.get_sidekiq_options['retry']).to be(false)
  end

  it 'conta que não existe mais: nada' do
    expect { described_class.perform_now(0, alvo) }.not_to raise_error
  end
end
