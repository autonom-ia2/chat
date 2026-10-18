require 'rails_helper'

# Lembrete de cobrança fora das 24h e retorno (#1498, #1624): o elo do Followup com o ponto único (Whatsapp::Templates::EnvioForaDaJanela).
# O ponto único roda de verdade (planejar e enviar, com os prontos da cobrança); só a conferência na Meta (DispatchCheck) é dublê.
RSpec.describe Crm::FollowUps::EnvioForaDaJanela do
  include CrmHybridHelpers

  before { travel_to Time.utc(2026, 10, 16, 14) }

  let(:pronto) { Whatsapp::Templates::Finalidades.pronto(:cobranca_vencimento, momento: :no_dia, com_valor: true) }
  let(:modelo) { pronto.corpo.deep_stringify_keys.merge('id' => '9', 'status' => 'APPROVED', 'language' => 'pt_BR') }
  let(:checagem) { instance_double(Whatsapp::Templates::DispatchCheck) }
  let(:kind) { 'payment_due' }
  let!(:scenario) { build_crm_hybrid_scenario(templates: [modelo], hybrid: false) }
  let(:card) { scenario[:card].tap { |created| created.update!(value_cents: 35_000, expected_close_at: Date.new(2026, 10, 16)) } }
  let!(:follow_up) do
    card
    create_crm_hybrid_follow_up(scenario, source: 'service_reminder', metadata: { 'kind' => kind, 'key' => "#{kind}:2026-10-16" })
  end

  def envio(**opcoes)
    described_class.new(follow_up: follow_up.reload, card: card, **opcoes).call
  end

  def conferencia(categoria: 'UTILITY', motivo: nil)
    template = modelo.merge('category' => categoria)
    verdict = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: motivo, source: nil, template: template,
                                                              details: { lookup_source: 'meta' })
    allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(checagem)
    allow(checagem).to receive(:call).and_return(verdict)
  end

  def marca(plano:, due_at: Crm::FollowUps::Preflight.horario(follow_up))
    follow_up.update!(metadata: follow_up.metadata.merge('preflight' => { 'estado' => 'pronto', 'due_at' => due_at, 'plano' => plano }))
  end

  def plano_do_pronto
    Whatsapp::Templates::EnvioForaDaJanela.planejar(inbox: scenario[:inbox], tipo: 'cobranca_no_dia', com_valor: true, criar: false)
  end

  describe '.tipo_de' do
    it 'mapeia o momento da cobrança e o retorno; o resto não tem modelo' do
      expect(described_class.tipo_de(follow_up)).to eq('cobranca_no_dia')
      follow_up.update!(metadata: follow_up.metadata.merge('kind' => 'payment_before'))
      expect(described_class.tipo_de(follow_up)).to eq('cobranca_antes')
      follow_up.update!(metadata: follow_up.metadata.merge('kind' => 'payment_after'))
      expect(described_class.tipo_de(follow_up)).to eq('cobranca_depois')
      follow_up.update!(metadata: follow_up.metadata.merge('source' => 'ai_callback'))
      expect(described_class.tipo_de(follow_up)).to eq('retorno')
      follow_up.update!(metadata: follow_up.metadata.merge('source' => 'service_reminder', 'kind' => 'progress'))
      expect(described_class.tipo_de(follow_up)).to be_nil
    end
  end

  describe 'cobrança sem pré-voo' do
    it 'planeja sem criar, preenche os campos com os dados do card de agora e devolve o metadata de envio com o registro' do
      conferencia
      allow(Whatsapp::Templates::EnvioForaDaJanela).to receive(:planejar).and_call_original

      result = envio

      expect(Whatsapp::Templates::EnvioForaDaJanela).to have_received(:planejar)
        .with(hash_including(tipo: 'cobranca_no_dia', com_valor: true, criar: false, ja_recusado: false))
      expect(result).to be_enviar
      expect(result.metadata).to include('template_name' => pronto.nome, 'template_language' => 'pt_BR', 'template_params_category' => 'UTILITY')
      expect(result.metadata['template_processed_params']['body']).to include('2' => 'R$ 350,00', '1' => 'Lead')
      expect(result.metadata['envio_fora_da_janela']).to include('tipo' => 'cobranca_no_dia', 'modelo' => pronto.nome, 'categoria' => 'UTILITY')
    end

    it 'sem valor no card, pede o pronto sem valor' do
      card.update!(value_cents: 0)
      allow(Whatsapp::Templates::EnvioForaDaJanela).to receive(:planejar).and_call_original

      envio

      expect(Whatsapp::Templates::EnvioForaDaJanela).to have_received(:planejar).with(hash_including(com_valor: false)).at_least(:once)
    end

    it 'o modelo ainda não existe na caixa e não houve pré-voo: nunca cria no horário, avisa a equipe' do
      scenario[:inbox].channel.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations
      allow(Whatsapp::Templates::MetaClient).to receive(:new)

      result = envio

      expect(result).to have_attributes(status: :lembrar_equipe, motivo: 'no_template')
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
    end
  end

  describe 'plano gravado pelo pré-voo' do
    it 'usa o plano gravado, sem planejar de novo' do
      conferencia
      marca(plano: plano_do_pronto)
      allow(Whatsapp::Templates::EnvioForaDaJanela).to receive(:planejar)

      expect(envio).to be_enviar
      expect(Whatsapp::Templates::EnvioForaDaJanela).not_to have_received(:planejar)
    end

    it 'o plano é de outro horário (o follow-up foi remarcado): ignora e planeja de novo' do
      conferencia
      marca(plano: plano_do_pronto, due_at: '2026-10-15T14:00:00.000000Z')
      allow(Whatsapp::Templates::EnvioForaDaJanela).to receive(:planejar).and_call_original

      expect(envio).to be_enviar
      expect(Whatsapp::Templates::EnvioForaDaJanela).to have_received(:planejar)
    end

    it 'o plano gravado ainda estava criando (formato real, sem campos) e a Meta já aprovou: replaneja e envia com os campos do modelo de agora' do
      conferencia
      marca(plano: plano_do_pronto.except('campos', 'texto').merge('caminho' => 'criando'))

      result = envio

      expect(result).to be_enviar
      expect(result.metadata['template_processed_params']['body'].keys).to match_array(pronto.campos.keys)
    end

    it 'o plano gravado era de outro modelo (campos diferentes): os valores saem do modelo do plano de agora, nunca trocados' do
      conferencia
      marca(plano: plano_do_pronto.merge('caminho' => 'criando', 'campos' => { '1' => 'negocio.titulo', '2' => 'cliente.primeiro_nome' }))

      body = envio.metadata['template_processed_params']['body']

      expect(body).to include('1' => 'Lead')
      expect(body.keys).to match_array(pronto.campos.keys)
      expect(pronto.campos.values).to include('negocio.valor')
      expect(body.values).to include('R$ 350,00')
    end

    it 'plano da equipe gravado pelo pré-voo (sem campos) e o modelo já aprovado no horário: envia, sem motivo falso de campo sem valor' do
      conferencia
      marca(plano: { 'versao' => 1, 'tipo' => 'cobranca_no_dia', 'caminho' => 'equipe', 'motivo' => 'meta_fora', 'ja_recusado' => false })

      expect(envio).to be_enviar
    end

    it 'sem modelo no horário e o pré-voo tinha o motivo de autorização: o aviso conserva o motivo mais específico' do
      scenario[:inbox].channel.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations
      marca(plano: { 'versao' => 1, 'tipo' => 'cobranca_no_dia', 'caminho' => 'equipe', 'motivo' => 'sem_consentimento', 'ja_recusado' => false })

      expect(envio).to have_attributes(status: :lembrar_equipe, motivo: 'sem_consentimento')
    end

    it 'campo do plano sem valor (ou fora do catálogo): não manda nada' do
      marca(plano: plano_do_pronto.merge('campos' => { '1' => 'cliente.cpf' }))

      expect(envio).to have_attributes(status: :lembrar_equipe, motivo: 'campo_sem_valor')
    end
  end

  describe 'o que não vai ao cliente' do
    it 'conferência na Meta recusa o modelo: avisa a equipe com o motivo' do
      conferencia(motivo: 'template_not_approved')
      marca(plano: plano_do_pronto)

      expect(envio).to have_attributes(status: :lembrar_equipe, motivo: 'template_not_approved')
    end

    it 'modelo que a Meta classificou como propaganda: não manda, avisa a equipe' do
      conferencia(categoria: 'MARKETING')
      marca(plano: plano_do_pronto.merge('nome' => 'modelo_da_conta', 'categoria' => 'MARKETING', 'origem' => 'conta'))

      expect(envio).to have_attributes(status: :lembrar_equipe, motivo: 'categoria_propaganda')
    end

    it 'lembrete que não é de cobrança (andamento): sem modelo, avisa a equipe' do
      follow_up.update!(metadata: follow_up.metadata.merge('kind' => 'progress'))

      expect(envio).to have_attributes(status: :lembrar_equipe, motivo: 'sem_finalidade_de_modelo')
    end

    it 'o número não é o oficial: avisa a equipe' do
      scenario[:inbox].update_columns(channel_type: 'Channel::Api') # rubocop:disable Rails/SkipsModelValidations

      expect(envio).to have_attributes(status: :lembrar_equipe, motivo: 'canal_sem_modelo_oficial')
    end

    it 'a Meta fora do ar levanta erro: avisa a equipe em vez de repetir a cada minuto' do
      marca(plano: plano_do_pronto)
      allow(Whatsapp::Templates::EnvioForaDaJanela).to receive(:enviar).and_raise(Faraday::ConnectionFailed, 'meta fora')

      expect(envio).to have_attributes(status: :lembrar_equipe, motivo: 'meta_fora')
    end
  end

  it 'explica o motivo à equipe em linguagem simples, para todo motivo conhecido' do
    I18n.with_locale(:pt_BR) do
      expect(described_class.aviso('modelo_indisponivel:recusado')).to include('O WhatsApp recusou o modelo')
      expect(described_class.aviso('modelo_em_analise')).to include('está em análise')
      expect(described_class.aviso('em_analise')).to include('está em análise')
      expect(described_class.aviso('motivo_novo')).to eq('A mensagem ao cliente não saiu sozinha: fale com ele.')
      %w[sem_finalidade_de_modelo canal_sem_modelo_oficial campo_sem_valor meta_fora
         closure no_template not_composable send_failed_3 unverified_quote_2 whatsapp_api_unavailable
         modelo_template_missing modelo_template_not_approved modelo_template_category_changed
         modelo_template_structure_changed modelo_template_format_unsupported modelo_templates_not_synced
         modelo_template_unverifiable categoria_propaganda modelo_template_offer_expired no_conversation].each do |motivo|
        expect(described_class.aviso(motivo)).not_to eq('A mensagem ao cliente não saiu sozinha: fale com ele.'), motivo
      end
      Whatsapp::Templates::EnvioForaDaJanela::MOTIVOS.each do |motivo|
        expect(I18n.t("crm.service_reminders.aviso.#{motivo}", default: nil)).to be_present, motivo
      end
    end
  end
end
