require 'rails_helper'

# #2499 (PR3a): os gatilhos de tempo. O TempoJob enfileira um job por automação; cada um acha os alvos da janela de
# 1 dia no fuso da conta e chama a Partida com a marca do fato, que não deixa repetir.
RSpec.describe 'Automação livre: gatilhos de tempo', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:novo) { funil_e_etapa.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: funil, name: 'Proposta', position: 1) }
  let(:card) { account.crm_cards.create!(pipeline: funil, stage: proposta, title: 'Pedido', currency: 'BRL') }
  let(:execucoes) { Autonomia::Automacao::Execucao }
  # Fora de America/Sao_Paulo de propósito: a hora do gatilho é a da conta.
  let(:fuso) { ActiveSupport::TimeZone['Asia/Tokyo'] }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    account.update!(reporting_timezone: fuso.name)
  end

  # Ligada há uma semana: os casos que não são sobre o instante de ligar não dependem dele.
  def de_tempo(tipo, ligada: 1.week.ago, **parametros)
    gatilho = { 'tipo' => tipo, **parametros.transform_keys(&:to_s) }
    travel_to(ligada) { automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: gatilho) }
  end

  # Uma varredura completa: o TempoJob e os jobs de cada automação que ele enfileirou.
  def varrer_tempo
    Autonomia::Automacao::TempoJob.perform_now
    perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
  end

  def parado_desde(momento) = card.update_columns(entered_stage_at: momento) # rubocop:disable Rails/SkipsModelValidations

  def fechar_execucoes
    execucoes.update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  describe 'card parado' do
    let!(:definicao) { de_tempo('card.parado', etapa_id: proposta.id, dias: 3) }

    # O revisor do PR3a: o mesmo card achado de novo a cada rodada não passa pela cadeia (a marca no Redis) nem pelo INSERT.
    it 'dispara uma vez em 10 varreduras seguidas, e as outras 9 nem entram na cadeia', :aggregate_failures do
      parado_desde(3.days.ago - 1.hour)
      allow(Autonomia::Automacao::Cadeia).to receive(:entrar).and_call_original
      10.times { |vez| travel(15.minutes * vez) { varrer_tempo } }

      expect(execucoes.where(automacao: definicao).pluck(:alvo_id, :chave_gatilho)).to eq([[card.id, 'card.parado']])
      expect(Autonomia::Automacao::Cadeia).to have_received(:entrar).once
    end

    it 'o card que sai da etapa e volta dispara de novo' do
      parado_desde(3.days.ago - 1.hour)
      varrer_tempo
      fechar_execucoes
      parado_desde(3.days.ago - 30.minutes)
      travel(15.minutes) { varrer_tempo }

      expect(execucoes.where(automacao: definicao).count).to eq(2)
    end

    it 'pane: o que passou do prazo há mais de 1 dia não entra, mesmo ligada antes' do
      parado_desde(5.days.ago)
      varrer_tempo

      expect(execucoes.count).to eq(0)
    end

    # Qualidade, PR3a: ligar não age no passado. O card que chegou ao prazo 1 hora antes de ligar fica de fora; o que
    # chega ao prazo depois de ligar entra.
    it 'ligar não age no passado: só o card que chega ao prazo depois de ligar', :aggregate_failures do
      definicao.update!(ativa: false)
      definicao.update!(ativa: true)
      parado_desde(3.days.ago - 1.hour)
      varrer_tempo
      expect(execucoes.count).to eq(0)

      parado_desde(3.days.ago + 10.minutes)
      travel(15.minutes) { varrer_tempo }
      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([card.id])
    end

    it 'só o card aberto, na etapa escolhida, com dias suficientes', :aggregate_failures do
      parado_desde(2.days.ago)
      varrer_tempo
      expect(execucoes.count).to eq(0)

      parado_desde(3.days.ago - 1.hour)
      card.update_columns(status: Crm::Card.statuses[:won]) # rubocop:disable Rails/SkipsModelValidations
      travel(15.minutes) { varrer_tempo }
      expect(execucoes.count).to eq(0)
    end
  end

  describe 'data do contato e do card' do
    let(:contato) { create(:contact, account: account) }

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'vencimento', attribute_display_name: 'Vencimento',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'date')
      create(:custom_attribute_definition, account: account, attribute_key: 'renovacao', attribute_display_name: 'Renovação',
                                           attribute_model: 'card_attribute', attribute_display_type: 'date')
    end

    def com_data(alvo, campo, dia) = alvo.update!(custom_attributes: alvo.custom_attributes.merge(campo => dia))

    # 09:00 em Tóquio; o servidor está em outro fuso.
    def as_9h_da_conta(&) = travel_to(fuso.local(2026, 11, 10, 9, 0), &)

    it 'antes: 30 dias antes da data, a partir da hora, no fuso da conta', :aggregate_failures do
      definicao = de_tempo('contato.data', campo: 'vencimento', dias: 30, quando: 'antes', hora: 8)
      com_data(contato, 'vencimento', '2026-12-10')
      outro = create(:contact, account: account, custom_attributes: { 'vencimento' => '2026-12-11' })

      as_9h_da_conta { varrer_tempo }

      expect(execucoes.where(automacao: definicao).pluck(:alvo_type, :alvo_id)).to eq([['Contact', contato.id]])
      expect(execucoes.where(alvo_id: outro.id)).to be_empty
    end

    # Qualidade, PR3a: ligar às 8h um "às 9h" não manda o de ontem; a primeira ocorrência é a de hoje às 9h.
    def ligada_as_8h(**parametros) = de_tempo('contato.data', ligada: fuso.local(2026, 11, 10, 8, 0), **parametros)

    it 'ligada às 8h com hora 9: nada até as 9h e, às 9h15, só o dia de hoje', :aggregate_failures do
      definicao = ligada_as_8h(campo: 'vencimento', dias: 0, quando: 'depois', hora: 9)
      com_data(contato, 'vencimento', '2026-11-10')
      ontem = create(:contact, account: account, custom_attributes: { 'vencimento' => '2026-11-09' })

      travel_to(fuso.local(2026, 11, 10, 8, 15)) { varrer_tempo }
      expect(execucoes.count).to eq(0)

      travel_to(fuso.local(2026, 11, 10, 9, 15)) { varrer_tempo }
      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([contato.id])
      expect(execucoes.where(alvo_id: ontem.id)).to be_empty
    end

    it 'ligada às 8h com antes 3 dias e hora 9: não manda o lembrete de ontem', :aggregate_failures do
      definicao = ligada_as_8h(campo: 'vencimento', dias: 3, quando: 'antes', hora: 9)
      com_data(contato, 'vencimento', '2026-11-13')
      de_ontem = create(:contact, account: account, custom_attributes: { 'vencimento' => '2026-11-12' })

      travel_to(fuso.local(2026, 11, 10, 8, 15)) { varrer_tempo }
      expect(execucoes.count).to eq(0)

      travel_to(fuso.local(2026, 11, 10, 9, 15)) { varrer_tempo }
      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([contato.id])
      expect(execucoes.where(alvo_id: de_ontem.id)).to be_empty
    end

    it 'religar depois da hora vale o instante novo: a de hoje, antes de religar, não roda; a de amanhã roda', :aggregate_failures do
      definicao = de_tempo('contato.data', campo: 'vencimento', dias: 0, quando: 'depois', hora: 9)
      com_data(contato, 'vencimento', '2026-11-10')
      amanha = create(:contact, account: account, custom_attributes: { 'vencimento' => '2026-11-11' })
      travel_to(fuso.local(2026, 11, 10, 8, 0)) { definicao.desligar! }
      travel_to(fuso.local(2026, 11, 10, 9, 30)) { definicao.update!(ativa: true) }

      travel_to(fuso.local(2026, 11, 10, 9, 45)) { varrer_tempo }
      expect(execucoes.count).to eq(0)

      travel_to(fuso.local(2026, 11, 11, 9, 15)) { varrer_tempo }
      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([amanha.id])
    end

    it 'antes da hora vale a ocorrência de ontem' do
      definicao = de_tempo('contato.data', campo: 'vencimento', dias: 0, quando: 'depois', hora: 10)
      com_data(contato, 'vencimento', '2026-11-09')

      as_9h_da_conta { varrer_tempo }

      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([contato.id])
    end

    it 'lê o dia escrito do valor antigo com hora e ignora outro formato, contando-o no log sem o valor', :aggregate_failures do
      definicao = de_tempo('contato.data', campo: 'vencimento', dias: 0, quando: 'depois', hora: 8)
      com_data(contato, 'vencimento', '2026-11-10T03:00:00.000Z')
      create(:contact, account: account, custom_attributes: { 'vencimento' => '10/11/2026' })
      allow(Rails.logger).to receive(:warn)

      as_9h_da_conta { varrer_tempo }

      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([contato.id])
      expect(Rails.logger).to have_received(:warn).with(
        "[automacao][tempo] datas_invalidas conta=#{account.id} automacao=#{definicao.id} quantos=1"
      )
    end

    it 'card.data: o card aberto com a data, uma vez por data' do
      definicao = de_tempo('card.data', campo: 'renovacao', dias: 7, quando: 'antes', hora: 8)
      com_data(card, 'renovacao', '2026-11-17')

      as_9h_da_conta { varrer_tempo }
      travel_to(fuso.local(2026, 11, 10, 9, 30)) { varrer_tempo }

      expect(execucoes.where(automacao: definicao).pluck(:evento)).to eq(["card.data:#{card.id}:renovacao:2026-11-17"])
    end

    # #2678: a festa, a revisão e a apólice vêm depois da venda. O card ganho dispara; o perdido, o cancelado e o
    # arquivado não (o cliente foi embora ou o card saiu de cena).
    it 'card.data: o card ganho também dispara; o perdido, o cancelado e o arquivado não', :aggregate_failures do
      definicao = de_tempo('card.data', campo: 'renovacao', dias: 7, quando: 'antes', hora: 8)
      ganho = card.tap { |c| c.update!(status: :won) }
      fechados = %i[lost cancelled archived].map do |status|
        # O status direto no banco: fechar como cancelado pede um funil com esse resultado, e aqui só importa o status.
        account.crm_cards.create!(pipeline: funil, stage: proposta, title: status.to_s, currency: 'BRL')
               .tap { |fechado| fechado.update_columns(status: status) } # rubocop:disable Rails/SkipsModelValidations
      end
      [ganho, *fechados].each { |alvo| com_data(alvo, 'renovacao', '2026-11-17') }

      as_9h_da_conta { varrer_tempo }

      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([ganho.id])
    end

    describe 'todo ano (aniversário)' do
      it 'compara só o dia e o mês: a data de outro ano dispara, uma vez por ano', :aggregate_failures do
        definicao = de_tempo('contato.data', campo: 'vencimento', dias: 0, quando: 'antes', hora: 8, repete: 'todo_ano')
        com_data(contato, 'vencimento', '1990-11-10')
        outro_dia = create(:contact, account: account, custom_attributes: { 'vencimento' => '1990-11-11' })

        as_9h_da_conta { varrer_tempo }
        travel_to(fuso.local(2026, 11, 10, 9, 30)) { varrer_tempo }

        expect(execucoes.where(automacao: definicao).pluck(:evento)).to eq(["contato.data:#{contato.id}:vencimento:2026-11-10"])
        expect(execucoes.where(alvo_id: outro_dia.id)).to be_empty
      end

      it 'sem "todo ano", a data de outro ano não dispara (o vencimento é de um dia só)' do
        definicao = de_tempo('contato.data', campo: 'vencimento', dias: 0, quando: 'antes', hora: 8)
        com_data(contato, 'vencimento', '1990-11-10')

        as_9h_da_conta { varrer_tempo }

        expect(execucoes.where(automacao: definicao)).to be_empty
      end

      it 'antes N dias atravessa a virada do ano', :aggregate_failures do
        definicao = de_tempo('contato.data', campo: 'vencimento', dias: 5, quando: 'antes', hora: 8, repete: 'todo_ano')
        com_data(contato, 'vencimento', '1985-01-02')

        travel_to(fuso.local(2026, 12, 28, 9, 0)) { varrer_tempo }

        expect(execucoes.where(automacao: definicao).pluck(:evento)).to eq(["contato.data:#{contato.id}:vencimento:2027-01-02"])
      end

      it 'quem nasceu em 29/02 é lembrado em 28/02 no ano que não é bissexto, e em 29/02 no bissexto', :aggregate_failures do
        definicao = de_tempo('contato.data', campo: 'vencimento', dias: 0, quando: 'antes', hora: 8, repete: 'todo_ano',
                                             ligada: fuso.local(2026, 1, 1, 0, 0))
        com_data(contato, 'vencimento', '2000-02-29')

        # Entre um ano e outro a execução já terminou (a receita de teste fica esperando).
        [fuso.local(2027, 2, 28, 9, 0), fuso.local(2028, 2, 28, 9, 0), fuso.local(2028, 2, 29, 9, 0)].each do |momento|
          travel_to(momento) { varrer_tempo }
          fechar_execucoes
        end

        expect(execucoes.where(automacao: definicao).pluck(:evento))
          .to eq(["contato.data:#{contato.id}:vencimento:2027-02-28", "contato.data:#{contato.id}:vencimento:2028-02-29"])
      end

      it 'card.data também repete todo ano, inclusive no card ganho' do
        definicao = de_tempo('card.data', campo: 'renovacao', dias: 0, quando: 'antes', hora: 8, repete: 'todo_ano')
        card.update!(status: :won)
        com_data(card, 'renovacao', '2025-11-10')

        as_9h_da_conta { varrer_tempo }

        expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([card.id])
      end
    end
  end

  describe 'a varredura' do
    let!(:definicao) { de_tempo('card.parado', etapa_id: proposta.id, dias: 3) }

    before { parado_desde(3.days.ago - 1.hour) }

    it 'processa cada automação uma vez por rodada, mesmo com dois jobs da mesma rodada' do
      allow(Autonomia::Automacao::Tempo).to receive(:busca).and_call_original
      rodada = Autonomia::Automacao::Tempo.rodada(Time.current).iso8601

      2.times { Autonomia::Automacao::TempoDaAutomacaoJob.perform_now(definicao.id, rodada) }

      expect(Autonomia::Automacao::Tempo).to have_received(:busca).once
    end

    it 'não processa a automação enquanto a rodada anterior ainda roda' do
      allow(Autonomia::Automacao::Tempo).to receive(:busca).and_call_original
      Redis::Alfred.set("automacao:tempo:rodando:#{definicao.id}", 'outra', ex: 60)

      Autonomia::Automacao::TempoDaAutomacaoJob.perform_now(definicao.id, Autonomia::Automacao::Tempo.rodada(Time.current).iso8601)

      expect(Autonomia::Automacao::Tempo).not_to have_received(:busca)
      Redis::Alfred.delete("automacao:tempo:rodando:#{definicao.id}")
    end

    it 'erro num alvo não para os outros, e o job falha no fim para aparecer no Sidekiq', :aggregate_failures do
      outro = account.crm_cards.create!(pipeline: funil, stage: proposta, title: 'Outro', currency: 'BRL')
      outro.update_columns(entered_stage_at: 3.days.ago - 1.hour) # rubocop:disable Rails/SkipsModelValidations
      chamadas = 0
      allow(Autonomia::Automacao::Partida).to receive(:new).and_wrap_original do |original, **opcoes|
        chamadas += 1
        raise ActiveRecord::Deadlocked if chamadas == 1

        original.call(**opcoes)
      end

      expect do
        Autonomia::Automacao::TempoDaAutomacaoJob.perform_now(definicao.id, Autonomia::Automacao::Tempo.rodada(Time.current).iso8601)
      end.to raise_error(ActiveRecord::Deadlocked)
      expect(execucoes.where(automacao: definicao).count).to eq(1)
      expect(Redis::Alfred.get("automacao:tempo:rodando:#{definicao.id}")).to be_nil
    end

    it 'sem a flag, a conta fica de fora' do
      account.disable_features!('automacao_gatilhos')

      Autonomia::Automacao::TempoJob.perform_now

      expect(enqueued_jobs.map { |job| job[:job] }).not_to include(Autonomia::Automacao::TempoDaAutomacaoJob)
    end

    it 'só enfileira as automações com gatilho de tempo' do
      de_tempo('conversa.resolvida')

      Autonomia::Automacao::TempoJob.perform_now

      expect(enqueued_jobs.select { |job| job[:job] == Autonomia::Automacao::TempoDaAutomacaoJob }.map { |job| job[:args].first })
        .to eq([definicao.id])
    end
  end
end
