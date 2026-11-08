require 'rails_helper'

# #2681 (lote 5, parte 4): o recorrente "uma vez só", numa data e numa hora ("quinta antes da Black Friday, 9h"). Roda
# uma vez, nesse dia, e nunca mais; a data que já passou não salva.
RSpec.describe 'Automação livre: gatilho numa data única', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:execucoes) { Autonomia::Automacao::Execucao }
  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    account.update!(reporting_timezone: fuso.name)
  end

  def gatilho(tipo: 'conta.recorrente', data: '2026-11-26', hora: 9, **extra)
    { 'tipo' => tipo, 'frequencia' => 'uma_vez', 'data' => data, 'hora' => hora, **extra.transform_keys(&:to_s) }
  end

  def ligar(gatilho_da_receita = gatilho, momento: fuso.local(2026, 11, 1))
    travel_to(momento) { automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: gatilho_da_receita) }
  end

  def varrer_em(momento)
    travel_to(momento) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
    end
  end

  def concluir_todas
    execucoes.update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  describe 'a ocorrência' do
    it 'roda uma vez, no dia e na hora, no fuso da conta; antes, nada', :aggregate_failures do
      ligar
      varrer_em(fuso.local(2026, 11, 25, 9, 5)) # véspera
      varrer_em(fuso.local(2026, 11, 26, 8, 50)) # o dia, antes da hora
      expect(execucoes.count).to eq(0)

      10.times { |vez| varrer_em(fuso.local(2026, 11, 26, 9, 5) + (15.minutes * vez)) }
      expect(execucoes.pluck(:alvo_type, :evento)).to eq([['Account', 'recorrente:2026-11-26:conta.recorrente']])
    end

    # A marca é a ocorrência: concluída a execução, as varreduras seguintes (o resto da janela, o dia seguinte, o mesmo
    # dia no ano que vem) não abrem outra.
    it 'nunca repete: nem no resto da janela, nem no dia seguinte, nem no ano que vem', :aggregate_failures do
      ligar
      varrer_em(fuso.local(2026, 11, 26, 9, 5))
      concluir_todas

      [fuso.local(2026, 11, 26, 20), fuso.local(2026, 11, 27, 9, 5), fuso.local(2027, 11, 26, 9, 5)].each { |momento| varrer_em(momento) }
      expect(execucoes.count).to eq(1)
    end

    # Mudar só a hora depois do disparo (uma versão nova, religada) não manda a campanha de novo; mudar a data, sim.
    it 'mudar só a hora depois do disparo não repete; mudar a data roda na nova data', :aggregate_failures do
      definicao = ligar
      varrer_em(fuso.local(2026, 11, 26, 9, 5))
      concluir_todas

      travel_to(fuso.local(2026, 11, 26, 10)) do
        definicao.salvar_versao!(receita: { 'gatilho' => gatilho(hora: 15), 'passos' => [esperar_passo('p1')] }, autor: admin)
      end
      varrer_em(fuso.local(2026, 11, 26, 15, 5))
      expect(execucoes.count).to eq(1)

      travel_to(fuso.local(2026, 11, 26, 16)) do
        definicao.salvar_versao!(receita: { 'gatilho' => gatilho(data: '2026-11-28'), 'passos' => [esperar_passo('p1')] }, autor: admin)
      end
      varrer_em(fuso.local(2026, 11, 28, 9, 5))
      expect(execucoes.order(:id).pluck(:evento).last).to eq('recorrente:2026-11-28:conta.recorrente')
      expect(execucoes.count).to eq(2)
    end

    # A janela é de 1 dia: sem varredura no dia (uma pane longa), a data não roda depois.
    it 'a data que ficou mais de 1 dia sem varredura não roda depois' do
      ligar
      varrer_em(fuso.local(2026, 11, 27, 9, 30))

      expect(execucoes.count).to eq(0)
    end

    it 'vale também no contato: cada contato da seleção, uma vez', :aggregate_failures do
      create(:label, account: account, title: 'ja-comprou')
      clientes = create_list(:contact, 2, account: account).each { |contato| contato.update!(label_list: ['ja-comprou']) }
      create(:contact, account: account) # sem a etiqueta: fica de fora
      ligar(gatilho(tipo: 'contato.recorrente', selecao: { 'etiqueta' => 'ja-comprou' }))

      varrer_em(fuso.local(2026, 11, 26, 9, 5))
      concluir_todas
      varrer_em(fuso.local(2026, 11, 27, 9, 5))

      expect(execucoes.order(:alvo_id).pluck(:alvo_id)).to eq(clientes.map(&:id).sort)
    end
  end

  describe 'o salvar' do
    def receita(gatilho_da_receita) = { 'gatilho' => gatilho_da_receita, 'passos' => [esperar_passo('p1')] }

    def problemas(gatilho_da_receita)
      Autonomia::Automacao::Receita.new(receita(gatilho_da_receita), conta: account, account_user: nil).problemas
    end

    def no_esquema?(gatilho_da_receita) = Autonomia::Automacao::Receita.esquema_valido?(receita(gatilho_da_receita))

    it 'pede a data só no "uma vez", e uma data que existe', :aggregate_failures do
      expect(no_esquema?(gatilho)).to be(true)
      expect(no_esquema?(gatilho.except('data'))).to be(false)
      expect(no_esquema?(gatilho(data: '2026-02-30'))).to be(false)
      expect(no_esquema?(gatilho(data: '26/11/2026'))).to be(false)
      expect(no_esquema?(gatilho.merge('frequencia' => 'diaria'))).to be(false)
      expect(no_esquema?(gatilho.merge('dia_do_mes' => 26))).to be(false)
    end

    it 'recusa a data (ou a hora do dia) que já passou; aceita a que vai chegar', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 26, 10)) do
        expect(problemas(gatilho(data: '2026-11-26', hora: 9)))
          .to eq([I18n.t('autonomia.automacao.receita.data_passada', data: I18n.l(Date.new(2026, 11, 26)))])
        expect(problemas(gatilho(data: '2026-11-25'))).to be_present
        expect(problemas(gatilho(data: '2026-11-26', hora: 11))).to be_empty
        expect(problemas(gatilho(data: '2026-12-01'))).to be_empty
      end
    end
  end
end
