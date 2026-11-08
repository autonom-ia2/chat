require 'rails_helper'

# Mitigação temporária (#2454, Issue #2455): o job antigo do Resumo só existe para não matar o que estiver na fila low na
# hora do deploy. Não faz nada.
RSpec.describe Crm::MetaAds::ComentariosIa::ResumoJob do
  it 'o perform não chama nada e não levanta erro, com os argumentos de antes' do
    allow(Crm::MetaAds::ComentariosIa::Resumo).to receive(:new)
    allow(Account).to receive(:find_by)

    expect { described_class.perform_now(1, { 'kind' => 'post', 'perfil' => 'instagram-1', 'post_id' => '1790' }) }.not_to raise_error

    expect(Crm::MetaAds::ComentariosIa::Resumo).not_to have_received(:new)
    expect(Account).not_to have_received(:find_by)
  end
end
