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
    expect(seguro.eventos.sole).to have_attributes(tipo: 'renovacao_card_nasceu', quando: agora, user_id: nil, valores: { 'funil' => funil.id })
    expect(card.activities.find_by(event_type: 'create').payload).to include('by' => 'automacao', 'origem' => 'carteira')
  end

  # O card sem dono e sem caixa só apareceria para o administrador: quem escolheu o funil é quem cuida.
  it 'quem escolheu o funil cuida do card, e a história do seguro guarda o nome' do
    bia = create(:user, account: account, role: :agent, name: 'Bia Exemplo')
    config.update!(user: bia)
    seguro = criar_apolice(marina, numero: 'EX-000001', fim_vigencia: hoje + 10)

    rodar

    expect(cards.sole.owner_id).to eq(bia.id)
    expect(seguro.eventos.sole).to have_attributes(tipo: 'renovacao_card_nasceu', user_id: nil,
                                                   valores: { 'funil' => funil.id, 'cuida' => 'Bia Exemplo' })
  end

  it 'quem escolheu e já saiu da conta não vira dono: o card nasce sem dono' do
    bia = create(:user, account: account, role: :agent, name: 'Bia Exemplo')
    config.update!(user: bia)
    AccountUser.where(account_id: account.id, user_id: bia.id).delete_all
    seguro = criar_apolice(marina, numero: 'EX-000001', fim_vigencia: hoje + 10)

    rodar

    expect([cards.sole.owner_id, seguro.eventos.sole.valores.to_h]).to eq([nil, { 'funil' => funil.id }])
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
    expect(Carteira::ApoliceEvento.where(apolice_id: seguros.map(&:id), tipo: 'renovacao_card_nasceu').count).to eq(3)
  end

  it 'avisa no sino quantos seguros entraram em renovação hoje, e a passada que não cria card não avisa de novo' do
    Array.new(2) { |i| criar_apolice(marina, numero: "EX-00007#{i}", fim_vigencia: hoje + 30 + i) }

    rodar
    rodar

    aviso = Notification.where(notification_type: 'carteira_renovacao').sole
    expect(aviso).to have_attributes(user_id: admin.id, primary_actor: config, meta: { 'quantos' => 2 })
  end

  it 'o aviso que falha não desfaz os cards nem derruba a rotina' do
    criar_apolice(marina, numero: 'EX-000080', fim_vigencia: hoje + 30)
    allow(Rails.logger).to receive(:error)
    allow(Carteira::Aviso).to receive(:new).and_raise(ActiveRecord::StatementTimeout, 'canceling statement')

    rodar

    expect(cards.count).to eq(1)
    expect(Rails.logger).to have_received(:error).with("[carteira][renovacao] aviso não saiu conta=#{account.id} ActiveRecord::StatementTimeout")
  end

  it 'quem apagou o card de propósito não o vê voltar nesta vigência' do
    seguro = criar_apolice(marina, numero: 'EX-000030', fim_vigencia: hoje + 30, renovacao_card_removido_em: agora - 1.day)

    rodar

    expect([cards.count, seguro.reload.crm_card_id]).to eq([0, nil])
  end

  # O card de renovação que saiu do quadro não volta nesta vigência, pelos dois caminhos do CRM: "apagar" (que arquiva)
  # e excluir de vez (que apaga a linha; o banco anula o vínculo no seguro sem avisar ninguém).
  describe 'o card de renovação que saiu do quadro' do
    let(:seguro) { criar_apolice(marina, numero: 'EX-000090', fim_vigencia: hoje + 30) }
    let(:card) { por_em_renovacao(seguro, config) }

    before { card }

    def excluir_de_vez(**opcoes)
      Crm::Cards::Excluidor.new(account: account, card_ids: [card.id], **opcoes).perform
    end

    # A conta escolhe outro funil para as renovações.
    def escolher_outro_funil
      create_crm_pipeline(account: account, user: admin, name: 'Renovação nova').tap do |novo_funil, nova_etapa|
        Carteira::RenovacaoConfig.find_by(account_id: account.id).update!(pipeline: novo_funil, stage: nova_etapa)
      end
    end

    it 'apagado no lote do quadro (arquivado) não renasce' do
      feito = Crm::Cards::BulkAction.new(account: account, user: admin, account_user: AccountUser.find_by(account: account, user: admin),
                                         ids: [card.id], action: 'delete').perform

      rodar

      expect(feito).to eq(updated: [card.id], failed: [])
      expect(seguro.reload).to have_attributes(crm_card_id: card.id, renovacao_card_removido_em: agora)
      expect(cards.pluck(:id, :status)).to eq([[card.id, 'archived']])
    end

    # O banco anula o vínculo e nada marca o seguro: quem impede o card novo é o passo da história, enquanto o funil
    # em que o card nasceu existir. Escolher outro funil depois não muda isso: excluir o card foi escolha.
    it 'excluído de vez sozinho não renasce, nem no funil de antes nem em outro que a conta escolha' do
      excluir_de_vez(somente_arquivados: false)
      solto = seguro.reload.slice(:crm_card_id, :renovacao_card_removido_em).values

      rodar
      escolher_outro_funil
      rodar

      expect(solto).to eq([nil, nil])
      expect([cards.count, seguro.reload.crm_card_id, seguro.eventos.pluck(:tipo)]).to eq([0, nil, ['renovacao_card_nasceu']])
    end

    # O funil arquivado continua existindo e pode ser restaurado: não libera o card novo.
    it 'excluído de vez, com o funil dele arquivado depois, também não renasce' do
      excluir_de_vez(somente_arquivados: false)
      novo_funil, = escolher_outro_funil
      funil.update!(status: :archived)

      rodar

      expect([novo_funil.reload.status, cards.count, seguro.reload.crm_card_id]).to eq(['active', 0, nil])
    end

    # Apagar o funil com os cards dentro (Crm::Pipelines::Excluidor) leva o card junto, sem ninguém ter pedido para
    # tirar aquela renovação: a conta que escolhe outro funil vê a renovação em andamento nascer nele.
    it 'apagado junto com o funil, nasce de novo no funil que a conta escolher depois' do
      funil.update!(status: :archived)
      Crm::Pipelines::Excluidor.new(pipeline: Crm::Pipeline.find(funil.id), actor: admin, modo: 'delete').perform

      rodar
      sem_funil = cards.count
      novo_funil, = escolher_outro_funil
      rodar
      rodar

      novo_card = cards.sole
      expect([sem_funil, novo_card.pipeline_id, seguro.reload.crm_card_id]).to eq([0, novo_funil.id, novo_card.id])
      expect(seguro.eventos.order(:id).pluck(:tipo, :valores))
        .to eq([['renovacao_card_nasceu', { 'funil' => funil.id }], ['renovacao_card_nasceu', { 'funil' => novo_funil.id }]])
    end

    # O passo gravado sem o funil (não há como saber onde o card nasceu) impede sempre.
    it 'o passo da história sem o funil guardado impede o card novo' do
      excluir_de_vez(somente_arquivados: false)
      seguro.eventos.sole.update!(valores: {})

      rodar

      expect([cards.count, seguro.reload.crm_card_id]).to eq([0, nil])
    end

    it 'arquivado e depois excluído de vez também não renasce' do
      Crm::Cards::Archiver.new(card: card, actor: admin).perform
      excluir_de_vez

      rodar

      expect([cards.count, seguro.reload.crm_card_id]).to eq([0, nil])
    end

    # A vigência é a linha: a renovação é outra apólice, e ganha o card dela quando chegar a hora.
    it 'na vigência seguinte o card nasce' do
      excluir_de_vez(somente_arquivados: false)
      seguinte = criar_apolice(marina, numero: 'EX-000090', fim_vigencia: hoje + 395, apolice_anterior: seguro)

      rodar
      cedo = cards.count
      travel_to(agora + 365.days)
      rodar

      expect([cedo, cards.sole.id, seguro.reload.crm_card_id]).to eq([0, seguinte.reload.crm_card_id, nil])
    end
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

  it 'o funil restaurado volta a receber os cards, sem ninguém escolher de novo' do
    seguro = criar_apolice(marina, numero: 'EX-000041', fim_vigencia: hoje + 30)
    funil.update!(status: :archived)
    rodar
    com_o_funil_arquivado = cards.count
    funil.update!(status: :active)

    rodar

    expect([com_o_funil_arquivado, cards.sole.id]).to eq([0, seguro.reload.crm_card_id])
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
