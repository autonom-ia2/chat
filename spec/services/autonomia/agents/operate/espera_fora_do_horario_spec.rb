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

  describe 'no fuso da caixa (o mesmo do Inbox#out_of_office?)' do
    it 'quinta 22h em São Paulo é sexta 01h em UTC, e a volta é sexta às 09:00 de São Paulo' do
      em(2026, 10, 15, 22, 0) do
        expect(Time.now.utc.hour).to eq(1)
        esperando!
        abertura = described_class.new(conversation: conversation).proxima_abertura

        expect(abertura).to eq(zona.local(2026, 10, 16, 9, 0))
      end
    end
  end
end
