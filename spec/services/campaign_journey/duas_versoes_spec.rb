require 'rails_helper'

# #3099: duas versões da mensagem na campanha com público. O plano do teste (o mesmo da tela), o sorteio fixo, o
# envio do teste com a versão de cada pessoa e o resto com a versão escolhida, uma vez só.
RSpec.describe CampaignJourney::DuasVersoes, :aggregate_failures do
  describe '.plano' do
    it 'testa 20% do público, com pelo menos 100 por versão, e manda o resto depois' do
      expect(described_class.plano(1350, 50)).to eq(modo: 'teste', teste: 270, versao1: 135, versao2: 135, resto: 1080,
                                                    pequeno: false, minimo: 200)
      expect(described_class.plano(1000, 70)).to include(modo: 'teste', teste: 334, versao1: 234, versao2: 100, resto: 666, minimo: 334)
      expect(described_class.plano(300, 50)).to include(modo: 'teste', teste: 200, resto: 100)
    end

    it 'sem resto que valha, todo mundo recebe uma das duas; abaixo do mínimo do teste, avisa que é pequeno' do
      expect(described_class.plano(299, 50)).to include(modo: 'todos', teste: 299, versao1: 150, versao2: 149, resto: 0, pequeno: false)
      expect(described_class.plano(120, 50)).to include(modo: 'todos', teste: 120, versao1: 60, versao2: 60, pequeno: true, minimo: 200)
      expect(described_class.plano(0, 50)).to include(modo: 'todos', teste: 0, versao1: 0, versao2: 0)
    end
  end

  describe '.regra' do
    it 'leva a espera ao padrão do critério e desliga sem regra' do
      expect(described_class.regra({ criterio: 'compras' })).to eq(teste_criterio: 'compras', teste_divisao: 50, teste_espera_horas: 24)
      expect(described_class.regra({ criterio: 'eu_escolho', divisao: '70', espera_horas: '2' }))
        .to eq(teste_criterio: 'eu_escolho', teste_divisao: 70, teste_espera_horas: 2)
      expect(described_class.regra(nil)).to be_nil
    end
  end

  describe 'campanha de SMS' do
    let(:account_and_user) { create_account_and_user }
    let(:account) { account_and_user.first }
    let(:user) { account_and_user.last }
    let!(:inbox) { journey_twilio_sms_inbox(account) }
    let(:content) do
      linhas = (0...10).map { |i| "Pessoa #{i},1198765#{format('%04d', i)}" }
      "Nome,Celular\n#{linhas.join("\n")}\n"
    end
    let!(:audience) { saved_audience(account: account, user: user, content: content) }

    # Com mínimos pequenos, 10 pessoas já dão teste e resto: 4 no teste (2 + 2) e 6 depois.
    before do
      stub_const('CampaignJourney::DuasVersoes::MINIMO_POR_VERSAO', 2)
      stub_const('CampaignJourney::DuasVersoes::MINIMO_NO_RESTO', 2)
    end

    def criar(duas_versoes, **outros)
      CampaignJourney::SmsCampaignCreator.new(
        account: account, campaign_import: audience, channel: 'sms',
        attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi {{contact.first_name}}, versão 1', duas_versoes: duas_versoes,
                      **outros }
      ).perform
    end

    let(:segunda) { { message_body: 'Oi {{contact.first_name}}, versão 2' } }

    it 'sorteia o teste sempre igual, sem o grupo de controle' do
      campaign = criar({ criterio: 'respostas', segunda: segunda }, grupo_de_controle_pct: 20)
      link = CampaignAudienceLink.for_campaign(campaign)
      fora = link.campaign_control_contacts.pluck(:contact_id)
      versoes = link.campaign_version_contacts.pluck(:contact_id, :versao)

      expect(fora.size).to eq(2)
      expect(link).to have_attributes(teste_estado: 'testando', teste_resto: 4, teste_criterio: 'respostas', teste_espera_horas: 4)
      expect(link.segunda_versao).to eq('message_body' => 'Oi {{contact.first_name}}, versão 2', 'variable_defaults' => {})
      expect(versoes.map(&:last).tally).to eq(1 => 2, 2 => 2)
      expect(versoes.map(&:first) & fora).to be_empty
      expect(CampaignJourney::AudienceContacts.contacts_for(link, channel: :sms).pluck(:id)).to match_array(versoes.map(&:first))

      publico = CampaignJourney::Medicao.publico(link, 'sms') - fora
      described_class.new(link).configurar!({ criterio: 'respostas' }, link.segunda_versao)
      described_class.new(link.reload).sortear!(publico.reverse)
      expect(link.campaign_version_contacts.pluck(:contact_id, :versao)).to match_array(versoes)
    end

    it 'manda o teste com a versão de cada pessoa e, escolhida a versão, o resto uma vez só' do
      sent = stub_twilio_sms
      campaign = criar({ criterio: 'respostas', segunda: segunda })
      link = CampaignAudienceLink.for_campaign(campaign)
      telefones = lambda do |versao|
        account.contacts.where(id: link.campaign_version_contacts.where(versao: versao).select(:contact_id)).pluck(:phone_number)
      end

      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform

      expect(sent.size).to eq(4)
      expect(sent.select { |body| body['Body'].end_with?('versão 2') }.pluck('To')).to match_array(telefones.call(2))
      expect(sent.select { |body| body['Body'].end_with?('versão 1') }.pluck('To')).to match_array(telefones.call(1))

      expect(described_class.new(link).mandar_resto!(2, por: :voce, user: user)).to be(true)
      expect(described_class.new(link.reload).mandar_resto!(1, por: :sistema)).to be(false)
      CampaignJourney::EnviarRestoJob.perform_now(link.id)
      CampaignJourney::EnviarRestoJob.perform_now(link.id)

      expect(sent.size).to eq(10)
      expect(sent.last(6).pluck('Body')).to all(end_with('versão 2'))
      expect(link.reload).to have_attributes(teste_estado: 'escolhida', teste_vencedora: 2, teste_escolhida_por: 'voce',
                                             teste_escolhida_por_user_id: user.id, teste_resto: 6)
      expect(link.campaign_version_contacts.where(fase: 'resto', versao: 2).count).to eq(6)
      expect(CampaignRecipient.where(campaign: campaign).sent.count).to eq(10)
    end

    # O envio pergunta a versão pessoa por pessoa: uma consulta por pessoa pesava no caminho do envio.
    it 'lê as versões do teste uma vez só e, escolhida a versão com o objeto em uso, dá a escolhida ao resto' do
      campaign = criar({ criterio: 'respostas', segunda: segunda })
      link = CampaignAudienceLink.for_campaign(campaign)
      teste = link.campaign_version_contacts.pluck(:contact_id, :versao).to_h
      resto = account.contacts.where.not(id: teste.keys).pluck(:id)
      duas_versoes = described_class.new(link)
      consultas = 0
      contar = ->(*, payload) { consultas += 1 if payload[:sql].include?('campaign_version_contacts') }

      ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
        expect(teste.keys.map { |id| duas_versoes.versao_de(id) }).to eq(teste.values)
      end
      expect(consultas).to eq(1)
      expect(resto.map { |id| duas_versoes.versao_de(id) }).to all(eq(1))

      described_class.new(CampaignAudienceLink.find(link.id)).mandar_resto!(2, por: :voce, user: user)
      expect(resto.map { |id| duas_versoes.versao_de(id) }).to all(eq(2))
      expect(teste.keys.map { |id| duas_versoes.versao_de(id) }).to eq(teste.values)
    end

    it 'no público pequeno, todo mundo recebe uma das duas e não há resto para escolher' do
      stub_const('CampaignJourney::DuasVersoes::MINIMO_POR_VERSAO', 100)
      sent = stub_twilio_sms
      campaign = criar({ criterio: 'respostas', segunda: segunda })
      link = CampaignAudienceLink.for_campaign(campaign)

      Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform

      expect(link.reload).to have_attributes(teste_estado: 'todos', teste_resto: 0)
      expect(sent.size).to eq(10)
      expect(described_class.new(link).mandar_resto!(1, por: :voce)).to be(false)
    end

    it 'recusa a versão 2 vazia, igual à 1 ou com campo que o público não tem' do
      expect { criar({ segunda: { message_body: '  ' } }) }.to raise_error(
        an_instance_of(CampaignJourney::AudienceCampaignCreator::Error).and(having_attributes(code: 'segunda_versao_vazia'))
      )
      expect { criar({ segunda: { message_body: 'Oi {{contact.first_name}}, versão 1 ' } }) }.to raise_error(
        an_instance_of(CampaignJourney::AudienceCampaignCreator::Error).and(having_attributes(code: 'segunda_versao_igual'))
      )
      expect { criar({ segunda: { message_body: 'Vence {{publico.vencimento}}' } }) }.to raise_error(
        an_instance_of(CampaignJourney::AudienceCampaignCreator::Error).and(having_attributes(code: 'unknown_audience_column'))
      )
      expect(account.campaigns.count).to eq(0)
    end

    it 'sem duas versões, a campanha segue como sempre' do
      campaign = criar(nil)
      link = CampaignAudienceLink.for_campaign(campaign)

      expect(link).to have_attributes(teste_criterio: nil, teste_estado: nil)
      expect(link.campaign_version_contacts).to be_empty
      expect(CampaignJourney::AudienceContacts.contacts_for(link, channel: :sms).count).to eq(10)
    end
  end
end
