require 'rails_helper'

# "Sempre a chave de cada conta. Sempre!" (Rodrigo): o motor, o começo da mensagem e a leitura da foto só usam a chave da
# própria conta (hook crm_kanban_ai). A conta sem o hook não cai na chave da instalação, mesmo com ela configurada: nada
# vai ao modelo, e o resultado é `no_credential`.
RSpec.describe Crm::MetaAds::ComentariosIa::ChaveDaConta do
  let(:account) { create(:account) }

  before do
    account.enable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: 'chave-da-instalacao')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::ResponsesClient).to receive(:new)
  end

  it 'a chave da conta, pelo hook crm_kanban_ai' do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })

    expect(described_class.de(account)).to include(api_key: 'chave-da-conta', source: :hook)
  end

  it 'sem o hook, nunca a da instalação: nil' do
    expect(Crm::Ai::CredentialResolver.new(account: account).resolve).to include(source: :system)
    expect(described_class.de(account)).to be_nil
  end

  describe 'conta sem o hook, com a chave da instalação configurada' do
    it 'Classificador: Bloqueado no_credential, sem chamar o modelo (o comentário vai para o dono)' do
      care = create(:crm_meta_ads_comment_care, account: account)

      expect { Crm::MetaAds::ComentariosIa::Classificador.new(care: care).avaliar!('Quanto custa?') }
        .to raise_error(Crm::MetaAds::ComentariosIa::Classificador::Bloqueado) { |erro| expect(erro.code).to eq('no_credential') }
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'Rascunho: no_credential, sem chamar o modelo nem guardar' do
      resultado = Crm::MetaAds::ComentariosIa::Rascunho.new(account: account, target_kind: 'post', target_id: '1790',
                                                            legenda: 'E-book de bolos por R$ 29').call

      expect(resultado).to eq(status: 'no_credential')
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(Crm::MetaAdsCommentDraft.count).to eq(0)
    end

    it 'Foto: no_credential, sem chamar o modelo nem guardar' do
      foto = Crm::MetaAds::ComentariosIa::Foto.new(account: account, network: 'instagram', post_id: '1790',
                                                   imagens: -> { ['https://cdn.exemplo/1.jpg'] })

      expect(foto.ler).to eq(status: 'no_credential')
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(Crm::MetaAdsPostReading.count).to eq(0)
    end
  end
end
