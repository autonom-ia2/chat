require 'rails_helper'

# #3101 (§4.3): o "Mandar de novo" escolhido na criação. Confere o que cada canal pede — "não leu" só no WhatsApp Oficial
# (D2), o texto no SMS e no WhatsApp API, o assunto no e-mail (D3), outro modelo aprovado no WhatsApp Oficial — e grava
# aguardando, sem hora (a hora sai do fim do envio da primeira).
RSpec.describe CampaignJourney::Reenvio, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }

  def opcoes_de(campaign)
    Autonomia::CampanhaOpcoesDeEnvio.find_by(campanha: campaign)
  end

  def recusa(campaign, dados)
    described_class.guardar!(campaign, dados)
    nil
  rescue described_class::Invalido => e
    e.code
  end

  context 'with SMS' do
    let!(:inbox) { journey_twilio_sms_inbox(account) }
    let!(:audience) { saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\n") }
    let(:campaign) do
      CampaignJourney::SmsCampaignCreator.new(
        account: account, campaign_import: audience, channel: 'sms',
        attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi {{contact.first_name}}' }
      ).perform
    end

    it 'saves who, how many days and the text, waiting and without a time yet' do
      described_class.guardar!(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: '5', reenvio_mensagem: { texto: ' Ainda aí? ' })

      expect(opcoes_de(campaign)).to have_attributes(
        account_id: account.id, melhor_horario: false, reenvio_quem: 'nao_respondeu', reenvio_dias: 5,
        reenvio_mensagem: { 'texto' => 'Ainda aí?' }, reenvio_status: 'aguardando', reenvio_em: nil
      )
    end

    it 'refuses "did not read" outside WhatsApp Oficial (D2), days off the list and an empty or unknown text' do
      expect(recusa(campaign, reenvio_quem: 'nao_leu', reenvio_dias: 3, reenvio_mensagem: { texto: 'Oi' })).to eq('reenvio_quem_invalido')
      expect(recusa(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 4, reenvio_mensagem: { texto: 'Oi' })).to eq('reenvio_dias_invalido')
      expect(recusa(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 3, reenvio_mensagem: { texto: '  ' })).to eq('reenvio_sem_texto')
      expect(recusa(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 3, reenvio_mensagem: { texto: 'Oi {{publico.plano}}' }))
        .to eq('reenvio_unknown_audience_column')
      expect(opcoes_de(campaign)).to be_nil
    end

    it 'turns off without reenvio_quem, and creates no row when it was never on' do
      described_class.guardar!(campaign, {})
      expect(opcoes_de(campaign)).to be_nil

      described_class.guardar!(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 3, reenvio_mensagem: { texto: 'Oi' })
      described_class.guardar!(campaign, {})
      expect(opcoes_de(campaign)).to have_attributes(reenvio_quem: nil, reenvio_status: nil, reenvio_mensagem: nil)
    end
  end

  context 'with WhatsApp Oficial' do
    let(:lembrete) do
      { 'name' => 'lembrete', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, ainda quer renovar?' }] }
    end
    let(:cupom) do
      { 'name' => 'cupom', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Seu cupom' },
                         { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'example' => 'X' }] }] }
    end
    let(:channel) do
      journey_cloud_channel(account).tap do |canal|
        canal.update!(message_templates: [CampaignJourneyHelpers::JOURNEY_TEMPLATE, lembrete, cupom])
      end
    end
    let(:audience) { saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\n") }
    let(:campaign) do
      CampaignJourney::WhatsappCampaignCreator.new(
        account: account, campaign_import: audience, channel: 'whatsapp_cloud',
        attributes: { title: 'Renovação', inbox_id: channel.inbox.id, template_params: journey_template_params,
                      variable_bindings: { '1' => { source: 'contact', value: 'first_name' }, '2' => { source: 'fixed', value: 'outubro' },
                                           '3' => { source: 'fixed', value: 'Equipe' } } }
      ).perform
    end

    def modelo(nome, ligacoes = { '1' => { source: 'contact', value: 'first_name' } })
      { reenvio_quem: 'nao_leu', reenvio_dias: 1,
        reenvio_mensagem: { modelo_id: "id-#{nome}", ligacoes: ligacoes,
                            template_params: { name: nome, language: 'pt_BR', processed_params: { body: { '1' => '' } } } } }
    end

    it 'saves "did not read" with another approved template and its bindings' do
      described_class.guardar!(campaign, modelo('lembrete'))

      expect(opcoes_de(campaign)).to have_attributes(reenvio_quem: 'nao_leu', reenvio_status: 'aguardando')
      expect(opcoes_de(campaign).reenvio_mensagem).to include(
        'modelo_id' => 'id-lembrete', 'ligacoes' => { '1' => { 'source' => 'contact', 'value' => 'first_name' } }
      )
      expect(opcoes_de(campaign).reenvio_mensagem['template_params']).to include('name' => 'lembrete')
    end

    it 'refuses the same template, one not approved, one with a coupon, and missing bindings' do
      expect(recusa(campaign, modelo('renovacao'))).to eq('reenvio_modelo_igual')
      expect(recusa(campaign, modelo('nao_existe'))).to eq('reenvio_modelo_nao_aprovado')
      expect(recusa(campaign, modelo('cupom', {}))).to eq('reenvio_modelo_com_oferta')
      expect(recusa(campaign, modelo('lembrete', {}))).to eq('reenvio_invalid_variable_bindings')
    end
  end

  context 'with e-mail' do
    let(:campaign) { create(:email_campaign, account: account) }

    it 'keeps only the new subject (D3)' do
      described_class.guardar!(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 7, reenvio_mensagem: { assunto: 'Viu?', texto: 'x' })

      expect(opcoes_de(campaign).reenvio_mensagem).to eq('assunto' => 'Viu?')
      expect(recusa(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 7, reenvio_mensagem: { assunto: '' })).to eq('reenvio_sem_assunto')
    end
  end

  it 'cancels only the second messages still waiting' do
    inbox = journey_twilio_sms_inbox(account)
    audience = saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\n")
    campaign = CampaignJourney::SmsCampaignCreator.new(account: account, campaign_import: audience, channel: 'sms',
                                                       attributes: { title: 'Parcela', inbox_id: inbox.id, message: 'Oi' }).perform
    described_class.guardar!(campaign, reenvio_quem: 'nao_respondeu', reenvio_dias: 3, reenvio_mensagem: { texto: 'De novo' })
    opcoes_de(campaign).update!(reenvio_status: 'enviado')

    described_class.cancelar!(campaign)

    expect(opcoes_de(campaign).reenvio_status).to eq('enviado')
  end
end
