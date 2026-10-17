require 'rails_helper'

# #1691 caso 1: agente em "Sempre", conversa esperando uma pessoa, fora do horário da caixa. A IA recebe, no contexto do
# turno (`developer`, só com a Fase 2), que a conversa espera alguém da equipe e quando a equipe volta (próxima abertura
# do horário da caixa, no fuso que o Chatwoot usa para ele). Ela decide como dizer; nada de mensagem automática.
RSpec.describe Autonomia::Agents::Operate::EsperaForaDoHorario do
  let(:account) { conta_da_fase2 }
  # Horário padrão da caixa: seg a sex, 9h às 17h; sábado e domingo fechados.
  let(:inbox) { create(:inbox, account: account, timezone: 'America/Sao_Paulo', working_hours_enabled: true) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:zona) { Time.find_zone('America/Sao_Paulo') }

  def esperando!(conversa = conversation)
    conversa.update!(ai_assignee: agent_bot, additional_attributes: { 'bot_handoff_waiting_since' => Time.current.iso8601 })
  end

  def em(*hora, &)
    travel_to(zona.local(*hora), &)
  end

  describe '#texto' do
    it 'quinta 22h: espera pessoa e a equipe volta amanhã, sexta, às 09:00' do
      em(2026, 10, 15, 22, 10) do
        esperando!
        texto = described_class.new(conversation: conversation).texto

        expect(texto).to include('o cliente está esperando alguém da equipe')
        expect(texto).to include('fora do horário de atendimento agora (quinta-feira, 15/10, 22:10)')
        expect(texto).to include('A equipe volta amanhã (sexta-feira, 16/10) às 09:00.')
        expect(texto).to include('Você decide se e como contar isso ao cliente')
      end
    end

    it 'sexta 18h: a equipe volta na segunda às 09:00 (pula o fim de semana)' do
      em(2026, 10, 16, 18, 0) do
        esperando!
        expect(described_class.new(conversation: conversation).texto).to include('A equipe volta segunda-feira, 19/10, às 09:00.')
      end
    end

    it 'quinta 7h: a equipe volta hoje às 09:00' do
      em(2026, 10, 15, 7, 0) do
        esperando!
        expect(described_class.new(conversation: conversation).texto).to include('A equipe volta hoje (quinta-feira, 15/10) às 09:00.')
      end
    end

    it 'sem nenhum dia aberto: diz que não há data de volta, sem inventar' do
      inbox.working_hours.update_all(closed_all_day: true, open_all_day: false) # rubocop:disable Rails/SkipsModelValidations
      em(2026, 10, 15, 22, 0) do
        esperando!
        texto = described_class.new(conversation: conversation).texto

        expect(texto).to include(described_class::SEM_DATA_DE_VOLTA)
        expect(texto).not_to include('A equipe volta')
      end
    end

    it 'a marca do motor de entrega (#1454) também conta como esperando pessoa' do
      em(2026, 10, 15, 22, 0) do
        conversation.update!(ai_assignee: agent_bot, additional_attributes: { Crm::Entrega::Marca::CHAVE => { 'modo' => 'segurando' } })
        expect(described_class.new(conversation: conversation).texto).to include('A equipe volta amanhã')
      end
    end

    it 'no horário: nil' do
      em(2026, 10, 15, 10, 0) do
        esperando!
        expect(described_class.new(conversation: conversation).texto).to be_nil
      end
    end

    it 'caixa sem horário de atendimento ligado: nil' do
      inbox.update!(working_hours_enabled: false)
      em(2026, 10, 15, 22, 0) do
        esperando!
        expect(described_class.new(conversation: conversation).texto).to be_nil
      end
    end

    it 'fora do horário, mas a conversa não espera pessoa: nil' do
      em(2026, 10, 15, 22, 0) do
        conversation.update!(ai_assignee: agent_bot)
        expect(described_class.new(conversation: conversation).texto).to be_nil
      end
    end

    it 'com pessoa no nome: nil' do
      em(2026, 10, 15, 22, 0) do
        esperando!
        conversation.update!(assignee: create(:user, account: account, role: :agent))
        expect(described_class.new(conversation: conversation).texto).to be_nil
      end
    end
  end

  # Revisão do 95d90020ad, item 1 e item 6: a volta não vira promessa, a IA não fala pela equipe e a hora que vale é a do
  # horário de atendimento, mesmo que outra mensagem (a de fora do horário da caixa) cite outra.
  it 'o texto proíbe prometer resposta no horário exato da volta e falar em nome da equipe, e diz qual hora vale' do
    em(2026, 10, 15, 22, 0) do
      esperando!
      texto = described_class.new(conversation: conversation).texto

      expect(texto).to include('prometa que alguém responde nesse horário exato nem antes dele')
      expect(texto).to include('não fale em nome da equipe')
      expect(texto).to include('se outra mensagem da conversa citar outra hora, siga esta')
      expect(texto).to include('Diga quando a equipe volta uma vez só')
      expect(texto).to include('não repita ressalvas')
    end
  end

  # Item 3 da revisão: dia "aberto o dia todo" é gravado como 00:00-23:59, mas o WorkingHour#open_at? devolve true antes
  # de olhar a hora, então às 23:59:30 a caixa segue aberta e não há contexto (nem volta anunciada para a meia-noite).
  it 'dia aberto o dia todo, às 23:59:30: a caixa segue aberta e não há contexto' do
    inbox.working_hours.find_by(day_of_week: 4).update!(open_all_day: true)
    travel_to(zona.local(2026, 10, 15, 23, 59, 30)) do
      esperando!
      expect(inbox.reload.out_of_office?).to be(false)
      expect(described_class.new(conversation: conversation).texto).to be_nil
    end
  end

  it 'calendário do CRM com o dia inteiro (0 a 1440), às 23:59:30: aberto e sem contexto' do
    create(:crm_service_schedule, account: account, owner: inbox, weekdays: [4], hours: [['00:00', '24:00']])
    travel_to(zona.local(2026, 10, 15, 23, 59, 30)) do
      esperando!
      expect(Autonomia::Agents::Operate::HorarioDaCaixa.new(conversation: conversation).aberta_agora).to be(true)
      expect(described_class.new(conversation: conversation).texto).to be_nil
    end
  end

  # Item 2: a mesma fonte de horário do EngagementGate.
  describe 'a mesma fonte do EngagementGate' do
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                       instruction: 'Atenda.', config: { 'response_window' => 'business_hours' })
    end

    def gate
      Autonomia::Agents::Operate::EngagementGate.new(agent: agent, conversation: conversation).blocked_reason
    end

    # Calendário do CRM da caixa: seg a sex, 8h às 12h (o horário do Chatwoot segue 9h às 17h).
    before { create(:crm_service_schedule, account: account, owner: inbox, weekdays: [1, 2, 3, 4, 5], hours: [['08:00', '12:00']]) }

    it 'sem a flag horario_unico_caixa, o calendário do CRM manda: quinta 13h está fechada e a volta é sexta às 08:00' do
      em(2026, 10, 15, 13, 0) do
        esperando!
        expect(inbox.out_of_office?).to be(false)
        expect(gate).to eq('schedule')
        expect(described_class.new(conversation: conversation).texto).to include('A equipe volta amanhã (sexta-feira, 16/10) às 08:00.')
      end
    end

    it 'sem a flag, quinta 10h: o gate deixa atender no horário e o contexto não aparece' do
      em(2026, 10, 15, 10, 0) do
        esperando!
        expect(gate).to be_nil
        expect(described_class.new(conversation: conversation).texto).to be_nil
      end
    end

    context 'with the horario_unico_caixa flag' do
      before { account.enable_features!(Autonomia::HorarioUnicoCaixa::FEATURE) }

      it 'o calendário do CRM é ignorado: quinta 13h está aberta (Chatwoot, 9h às 17h) para o gate e para o contexto' do
        em(2026, 10, 15, 13, 0) do
          esperando!
          expect(gate).to be_nil
          expect(described_class.new(conversation: conversation).texto).to be_nil
        end
      end

      it 'quinta 22h: fechada para os dois, e a volta é a do Chatwoot, sexta às 09:00' do
        em(2026, 10, 15, 22, 0) do
          esperando!
          expect(gate).to eq('schedule')
          expect(described_class.new(conversation: conversation).texto).to include('A equipe volta amanhã (sexta-feira, 16/10) às 09:00.')
        end
      end
    end
  end

  describe Autonomia::Agents::Operate::HorarioDaCaixa do
    it 'no fuso da caixa: quinta 22h em São Paulo é sexta 01h em UTC, e a volta é sexta às 09:00 de São Paulo' do
      em(2026, 10, 15, 22, 0) do
        expect(Time.now.utc.hour).to eq(1)
        expect(described_class.new(conversation: conversation).proxima_abertura).to eq(zona.local(2026, 10, 16, 9, 0))
      end
    end

    it 'sem a flag, o fuso é o gravado na caixa (aqui UTC), não o da conta' do
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      inbox.update!(timezone: 'UTC')
      em(2026, 10, 15, 22, 0) do # sexta 01h em UTC
        horario = described_class.new(conversation: conversation)

        expect(horario.fuso).to eq('UTC')
        expect(horario.proxima_abertura).to eq(Time.find_zone('UTC').local(2026, 10, 16, 9, 0))
      end
    end

    it 'sem nenhuma fonte de horário: aberta_agora é nil e não há próxima abertura' do
      inbox.update!(working_hours_enabled: false)
      em(2026, 10, 15, 22, 0) do
        horario = described_class.new(conversation: conversation)

        expect(horario.aberta_agora).to be_nil
        expect(horario.proxima_abertura).to be_nil
      end
    end
  end
end
