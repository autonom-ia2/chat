require 'rails_helper'

# E5 (#2898) — a rotina da renovação de uma conta: o card de cada seguro que entra em renovação hoje nasce no funil e na
# etapa que a conta escolheu, uma vez só. Tudo fictício.
RSpec.describe Carteira::Renovacao::DaContaJob do
  # 23h30 de 12/11/2026 em São Paulo: no servidor (UTC) já é dia 13.
  let(:agora) { Time.utc(2026, 11, 13, 2, 30) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Renovação') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:config) { create(:carteira_renovacao_config, account: account, pipeline: funil, stage: etapa, dias_antes: 60) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    config
  end

  def rodar(conta = account)
    described_class.perform_now(conta.id)
  end

  def cards(conta = account)
    Crm::Card.where(account_id: conta.id)
  end

  it 'cria o card do seguro que termina dentro dos dias escolhidos, no funil e na etapa da conta, e liga os dois' do
    seguro = criar_apolice(marina, seguradora: 'Seguradora Exemplo', numero: 'EX-000001', fim_vigencia: hoje + 60)

    rodar

    card = cards.sole
    expect(card).to have_attributes(pipeline_id: funil.id, stage_id: etapa.id, contact_id: marina.id, owner_id: nil, status: 'open',
                                    title: 'Renovação · Seguradora Exemplo')
    expect(card.expected_close_at.in_time_zone('America/Sao_Paulo').to_date).to eq(hoje + 60)
    expect(seguro.reload.crm_card_id).to eq(card.id)
    expect(seguro.eventos.sole).to have_attributes(tipo: 'card_nasceu', quando: agora, user_id: nil)
    expect(card.activities.find_by(event_type: 'create').payload).to include('by' => 'automacao', 'origem' => 'carteira')
  end

  it 'o dia de hoje é o da conta: às 23h30 de São Paulo ainda não entra quem só entraria amanhã' do
    amanha = criar_apolice(marina, numero: 'EX-000002', fim_vigencia: hoje + 61)

    rodar

    expect(amanha.reload.crm_card_id).to be_nil
  end

  it 'deixa de fora o que já venceu, o cancelado, o que tem desfecho e o que termina depois dos dias escolhidos' do
    fora = {
      'vencido' => criar_apolice(marina, numero: 'EX-000010', fim_vigencia: hoje - 1),
      'cancelado' => criar_apolice(marina, numero: 'EX-000011', fim_vigencia: hoje + 10, cancelado_em: agora),
      'renovado' => criar_apolice(marina, numero: 'EX-000012', fim_vigencia: hoje + 10, renovado_em: agora),
      'não renovou' => criar_apolice(marina, numero: 'EX-000013', fim_vigencia: hoje + 10, nao_renovou_em: agora),
      'longe' => criar_apolice(marina, numero: 'EX-000014', fim_vigencia: hoje + 200)
    }
    criar_apolice(marina, numero: 'EX-000015', fim_vigencia: hoje)

    rodar

    expect(fora.transform_values { |seguro| seguro.reload.crm_card_id }.compact).to eq({})
    expect(cards.count).to eq(1)
  end

  it 'rodar duas vezes no mesmo dia não cria card repetido' do
    seguros = Array.new(3) { |i| criar_apolice(marina, numero: "EX-00002#{i}", fim_vigencia: hoje + 30 + i) }

    rodar
    primeiros = seguros.map { |seguro| seguro.reload.crm_card_id }
    rodar

    expect(cards.count).to eq(3)
    expect(seguros.map { |seguro| seguro.reload.crm_card_id }).to eq(primeiros)
    expect(Carteira::ApoliceEvento.where(apolice_id: seguros.map(&:id), tipo: 'card_nasceu').count).to eq(3)
  end

  it 'quem apagou o card de propósito não o vê voltar nesta vigência' do
    seguro = criar_apolice(marina, numero: 'EX-000030', fim_vigencia: hoje + 30, renovacao_card_removido_em: agora - 1.day)

    rodar

    expect([cards.count, seguro.reload.crm_card_id]).to eq([0, nil])
  end

  it 'não cria nada sem a carteira, sem o CRM, sem escolha ou com o funil arquivado' do
    seguro = criar_apolice(marina, numero: 'EX-000040', fim_vigencia: hoje + 30)

    account.disable_features!('carteira_seguros')
    rodar
    account.enable_features!('carteira_seguros')
    with_modified_env(CRM_KANBAN_ENABLED: 'false') { rodar }
    config.update!(pipeline: nil, stage: nil)
    rodar
    config.update!(pipeline: funil, stage: etapa)
    funil.update!(status: :archived)
    rodar
    described_class.perform_now(0)

    expect([cards.count, seguro.reload.crm_card_id]).to eq([0, nil])
  end

  it 'só mexe na conta pedida' do
    outra = conta_com_carteira
    dona = create(:user, account: outra, role: :administrator)
    funil_de_fora, etapa_de_fora = create_crm_pipeline(account: outra, user: dona, name: 'Renovação')
    create(:carteira_renovacao_config, account: outra, pipeline: funil_de_fora, stage: etapa_de_fora)
    de_fora = criar_apolice(create(:contact, account: outra), numero: 'EX-000050', fim_vigencia: hoje + 30)
    criar_apolice(marina, numero: 'EX-000051', fim_vigencia: hoje + 30)

    rodar

    expect([cards.count, cards(outra).count, de_fora.reload.crm_card_id]).to eq([1, 0, nil])
  end

  it 'o seguro que falha não para os outros, e o job falha no fim para aparecer' do
    seguros = Array.new(3) { |i| criar_apolice(marina, numero: "EX-00006#{i}", fim_vigencia: hoje + 30 + i) }
    allow(Rails.logger).to receive(:error)
    original = Crm::Cards::Creator.method(:new)
    allow(Crm::Cards::Creator).to receive(:new) do |**dados|
      raise ActiveRecord::StatementTimeout, 'canceling statement' if dados.dig(:automacao, :id) == seguros.second.id

      original.call(**dados)
    end

    expect { rodar }.to raise_error(ActiveRecord::StatementTimeout)

    expect(seguros.map { |seguro| seguro.reload.crm_card_id.present? }).to eq([true, false, true])
    expect(seguros.second.eventos).to be_empty
    expect(Rails.logger).to have_received(:error)
      .with("[carteira][renovacao] card não nasceu conta=#{account.id} seguro=#{seguros.second.id} ActiveRecord::StatementTimeout")
  end

  # O aceite "carteira de 2 mil apólices: a rotina termina". As consultas crescem com o número de cards (cada card é
  # criado, ligado e anotado), nunca mais que isso: a carteira 200 vezes maior não custa mais que 200 vezes a pequena.
  describe 'com volume' do
    def encher(conta, pessoa, quantas)
      agora_do_banco = Time.current
      linhas = Array.new(quantas) do |i|
        { account_id: conta.id, contact_id: pessoa.id, tipo: 'auto', seguradora: 'Seguradora Exemplo', seguradora_chave: 'seguradoraexemplo',
          numero: "VOL-#{i}", numero_chave: "VOL#{i}", fim_vigencia: hoje + (i % 60), origem: 'planilha', created_at: agora_do_banco,
          updated_at: agora_do_banco }
      end
      Carteira::Apolice.insert_all!(linhas) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'termina com 2 mil seguros entrando no mesmo dia, um card para cada, sem custo que cresça mais que a carteira' do
      pequena = conta_com_carteira(reporting_timezone: 'America/Sao_Paulo')
      dona = create(:user, account: pequena, role: :administrator)
      funil_pequeno, etapa_pequena = create_crm_pipeline(account: pequena, user: dona, name: 'Renovação')
      create(:carteira_renovacao_config, account: pequena, pipeline: funil_pequeno, stage: etapa_pequena)
      encher(pequena, create(:contact, account: pequena), 10)
      encher(account, marina, 2_000)

      da_pequena = consultas_da_carteira { rodar(pequena) }
      da_grande = consultas_da_carteira { rodar }

      expect([cards(pequena).count, cards.count]).to eq([10, 2_000])
      expect(Carteira::Apolice.where(account_id: account.id, crm_card_id: nil)).to be_empty
      expect(Carteira::Apolice.where(account_id: account.id).distinct.count(:crm_card_id)).to eq(2_000)
      expect(da_grande).to be <= da_pequena * 200
    end
  end
end
