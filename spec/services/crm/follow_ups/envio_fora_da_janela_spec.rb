require 'rails_helper'

# Lembrete de Atender fora das 24h (#1498): só com modelo aprovado do Garantir (#1518). Sem ele, avisa a equipe.
RSpec.describe Crm::FollowUps::EnvioForaDaJanela do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:user) { create(:user, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:contact) { account.contacts.create!(name: 'Júlia Ramos', phone_number: '+5511955554444') }
  let(:conversation) do
    contact_inbox = ContactInbox.create!(contact: contact, inbox: channel.inbox, source_id: '5511955554444')
    account.conversations.create!(inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox, assignee: user)
  end
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Cobrança')
    pipeline.update!(counts_as_sale: false)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Mensalidade de outubro',
                              value_cents: 35_000, expected_close_at: Date.new(2026, 10, 20))
  end
  let(:kind) { 'payment_due' }
  let(:follow_up) do
    account.crm_follow_ups.create!(card: card, conversation: conversation, contact: contact, title: 'Lembrar do pagamento',
                                   due_at: 1.hour.from_now, metadata: { 'source' => 'service_reminder', 'kind' => kind })
  end
  let(:pronto) do
    { status: :pronto, nome: 'cobranca_vencimento', idioma: 'pt_BR', categoria: 'UTILITY',
      campos: { '2' => 'negocio.valor', '1' => 'cliente.primeiro_nome', '3' => 'negocio.titulo' } }
  end

  def envio
    described_class.new(follow_up: follow_up, card: card).call
  end

  # Dublê do Garantir (#1518) com a assinatura combinada; guarda o que recebeu.
  def com_garantir(resposta)
    chamadas = []
    garantir = Class.new do
      define_singleton_method(:call) do |inbox:, finalidade:, momento:, com_valor:, idioma:|
        chamadas << { inbox: inbox, finalidade: finalidade, momento: momento, com_valor: com_valor, idioma: idioma }
        resposta
      end
    end
    stub_const('Whatsapp::Templates::Garantir', garantir)
    chamadas
  end

  it 'com o modelo pronto e enviável, preenche os campos com os dados do card' do
    chamadas = com_garantir(pronto)
    verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: nil, source: 'meta', details: {})
    allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(instance_double(Whatsapp::Templates::DispatchCheck, call: verdict))

    result = envio

    expect(chamadas.sole).to eq(inbox: channel.inbox, finalidade: :cobranca_vencimento, momento: :no_dia, com_valor: true,
                                idioma: nil)
    expect(result).to be_enviar
    expect(result.metadata).to include(
      'template_name' => 'cobranca_vencimento', 'template_language' => 'pt_BR', 'template_params_category' => 'UTILITY',
      'template_processed_params' => {
        'body' => { '2' => 'R$ 350,00', '1' => 'Júlia', '3' => 'Mensalidade de outubro' }
      }
    )
  end

  # O prazo ('4' => 'negocio.prazo') entra no catálogo junto com o Garantir (#1518); aqui só os campos que já existem.
  it 'sem valor, pede o modelo sem valor e segue a numeração que o Garantir devolve' do
    card.update!(value_cents: 0)
    chamadas = com_garantir(pronto.merge(campos: { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' }))
    verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: nil, source: 'meta', details: {})
    allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(instance_double(Whatsapp::Templates::DispatchCheck, call: verdict))

    result = envio

    expect(chamadas.sole).to include(com_valor: false, idioma: nil)
    expect(result.metadata['template_processed_params']).to eq('body' => { '1' => 'Júlia', '2' => 'Mensalidade de outubro' })
  end

  it 'modelo em análise ou que não passa na conferência: avisa a equipe' do
    com_garantir(status: :em_analise, nome: 'cobranca_vencimento', idioma: 'pt_BR')
    expect(envio.motivo).to eq('modelo_em_analise')

    com_garantir(status: :indisponivel, motivo: 'recusado')
    expect(envio.motivo).to eq('modelo_indisponivel:recusado')

    com_garantir(pronto)
    verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: 'template_not_approved', source: 'meta', details: {})
    allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(instance_double(Whatsapp::Templates::DispatchCheck, call: verdict))
    expect(envio.motivo).to eq('modelo_template_not_approved')
  end

  it 'modelo que a Meta classificou como propaganda: não manda, avisa a equipe' do
    com_garantir(pronto.merge(categoria: 'MARKETING'))
    expect(envio.motivo).to eq('categoria_propaganda')

    com_garantir(pronto)
    verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: nil, source: 'meta', details: {},
                                                              template: { 'category' => 'MARKETING' })
    allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(instance_double(Whatsapp::Templates::DispatchCheck, call: verdict))
    expect(envio.motivo).to eq('categoria_propaganda')
  end

  it 'campo sem valor (ou fora do catálogo) não manda nada' do
    com_garantir(pronto.merge(campos: { '1' => 'cliente.cpf' }))
    expect(envio.motivo).to eq('campo_sem_valor')
  end

  context 'when it is the progress reminder (no template purpose)' do
    let(:kind) { 'progress' }

    it 'avisa a equipe' do
      com_garantir(pronto)
      expect(envio.motivo).to eq('sem_finalidade_de_modelo')
    end
  end

  it 'explica o motivo à equipe em linguagem simples, para todo motivo conhecido' do
    I18n.with_locale(:pt_BR) do
      expect(described_class.aviso('modelo_indisponivel:recusado')).to include('O WhatsApp recusou o modelo')
      expect(described_class.aviso('modelo_em_analise')).to include('está em análise')
      expect(described_class.aviso('motivo_novo')).to eq('A mensagem ao cliente não saiu sozinha: fale com ele.')
      %w[modelo_em_analise sem_finalidade_de_modelo canal_sem_modelo_oficial campo_sem_valor meta_fora
         closure no_template not_composable send_failed_3 unverified_quote_2 whatsapp_api_unavailable
         modelo_template_missing modelo_template_not_approved modelo_template_category_changed
         modelo_template_structure_changed modelo_template_format_unsupported modelo_templates_not_synced
         modelo_template_unverifiable categoria_propaganda modelo_template_offer_expired no_conversation].each do |motivo|
        expect(described_class.aviso(motivo)).not_to eq('A mensagem ao cliente não saiu sozinha: fale com ele.'), motivo
      end
      %w[sem_whatsapp_oficial idioma_sem_pronto formato recusado pausado desativado situacao_desconhecida meta_fora
         sem_permissao meta_recusou texto_diferente perfil_invalido].each do |motivo|
        expect(described_class.aviso("modelo_indisponivel:#{motivo}")).to include(' '), motivo
        expect(I18n.t("crm.service_reminders.aviso.#{motivo}", default: nil)).to be_present, motivo
      end
    end
  end
end
