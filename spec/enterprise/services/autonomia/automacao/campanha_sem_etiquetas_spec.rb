require 'rails_helper'

# Lote 5 (#2681): a campanha disparada pela automação deixa de fora quem tem uma etiqueta excluída (ExcludeLabel no
# `audience`), sem mudar quem recusou mensagens ativas nem a campanha da tela. Fica em spec/enterprise: o envio com
# destinatário (CampaignRecipient) é o do overlay do EE.
RSpec.describe Autonomia::Automacao::CampanhaSemEtiquetas do
  let(:account) { create(:account) }
  let(:canal) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:publico) { create(:label, account: account, title: 'clientes') }
  let(:ja_comprou) { create(:label, account: account, title: 'ja_comprou') }
  # O modelo que o canal de teste já traz (a trava do disparo, #1329, confere o modelo na lista do canal).
  let(:template_params) do
    { 'name' => 'ticket_status_updated', 'namespace' => '23423423_2342423_324234234_2343224', 'category' => 'UTILITY',
      'language' => 'en', 'processed_params' => { 'body' => { 'name' => 'Ana', 'ticket_id' => '1' } } }
  end
  let(:enviados) { [] }

  before do
    account.enable_features!(:whatsapp_campaign)
    stub_meta_template_lookup
    allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(canal) # rubocop:disable RSpec/AnyInstance
    allow(canal).to receive(:send_template) do |para, *_resto|
      enviados << para
      "wamid.#{para}"
    end
  end

  def cliente(telefone, *etiquetas)
    create(:contact, account: account, phone_number: telefone).tap { |contato| contato.update_labels(etiquetas) }
  end

  def campanha(audiencia)
    create(:campaign, inbox: canal.inbox, account: account, audience: audiencia, template_params: template_params)
  end

  def disparar(audiencia) = Whatsapp::OneoffCampaignService.new(campaign: campanha(audiencia)).perform

  it 'manda para o público menos quem tem a etiqueta excluída' do
    cliente('+5511900000031', 'clientes')
    cliente('+5511900000032', 'clientes', 'ja_comprou')

    disparar([{ 'type' => 'Label', 'id' => publico.id }, *described_class.audiencia([ja_comprou.id])])

    expect(enviados).to eq(['+5511900000031'])
  end

  it 'quem recusou mensagens ativas continua de fora' do
    cliente('+5511900000041', 'clientes')
    cliente('+5511900000042', 'clientes').opt_out!(source: 'manual')

    disparar([{ 'type' => 'Label', 'id' => publico.id }, *described_class.audiencia([ja_comprou.id])])

    expect(enviados).to eq(['+5511900000041'])
  end

  it 'campanha sem etiqueta excluída (a da tela) manda para o mesmo público de antes' do
    cliente('+5511900000051', 'clientes')
    cliente('+5511900000052', 'clientes', 'ja_comprou')

    disparar([{ 'type' => 'Label', 'id' => publico.id }])

    expect(enviados).to contain_exactly('+5511900000051', '+5511900000052')
  end

  # 🟡 da qualidade (#2686): a campanha ligada a um público importado tira o público do CampaignJourney::AudienceContacts,
  # sem passar pelas etiquetas. A exclusão vale ali também. O público importado é trocado por todos os contatos da
  # conta: a regra de quem entra pela planilha é do spec da jornada.
  describe 'campanha ligada a um público importado' do
    before do
      link = instance_double(CampaignAudienceLink, campaign_import: nil, variable_bindings: {}, variable_defaults: {})
      allow(CampaignAudienceLink).to receive(:for_campaign).and_return(link)
      allow(CampaignJourney::AudienceContacts).to receive(:contacts_for) { account.contacts }
      allow(CampaignJourney::AudienceContacts).to receive(:whatsapp_enabled?).and_return(true)
    end

    it 'manda para o público importado menos quem tem a etiqueta excluída' do
      cliente('+5511900000061')
      cliente('+5511900000062', 'ja_comprou')

      disparar(described_class.audiencia([ja_comprou.id]))

      expect(enviados).to eq(['+5511900000061'])
    end

    it 'sem etiqueta excluída, manda para o público importado inteiro' do
      cliente('+5511900000071')
      cliente('+5511900000072', 'ja_comprou')

      disparar([])

      expect(enviados).to contain_exactly('+5511900000071', '+5511900000072')
    end
  end

  # A exclusão só alcança o caminho do público importado se o módulo estiver por cima do da jornada: a ordem vem do
  # nome do initializer (carrega depois do campaign_journey.rb).
  it 'fica por cima da jornada de campanhas no envio' do
    ancestrais = Whatsapp::OneoffCampaignService.ancestors

    expect(ancestrais.index(described_class)).to be < ancestrais.index(CampaignJourney::AudienceContacts)
  end
end
