require 'rails_helper'

# Excluir de vez (#2096): o card e todo o histórico dele saem; a conversa do cliente fica.
RSpec.describe Crm::Cards::Excluidor do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990001') }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let!(:message) { create_incoming_message(conversation: conversation, content: 'Quero o orçamento') }
  let!(:card) { create_card_cheio(account: account, user: user, pipeline: pipeline, contact: contact, conversation: conversation) }

  def excluir(ids = [card.id], &)
    described_class.new(account: account, card_ids: ids).perform(&)
  end

  it 'apaga o card e tudo que aponta para ele, sem tocar a conversa, as mensagens nem o contato' do
    create_reuniao(account: account, card: card, user: user, contact: contact, starts_at: 2.days.ago)
    expect(onde_o_card_ainda_aparece(card.id)).to include('crm_activities.card_id', 'crm_meetings.card_id', 'crm_ai_usage_events.card_id')

    expect(excluir).to eq([card.id])

    expect(Crm::Card.exists?(card.id)).to be(false)
    expect(onde_o_card_ainda_aparece(card.id)).to eq([])
    expect(Crm::MeetingGuest.where(account_id: account.id)).to be_empty
    expect(conversation.reload.messages.pluck(:id)).to include(message.id)
    expect(contact.reload).to be_present
  end

  it 'mantém o custo de IA na conta, sem o vínculo com o card' do
    excluir

    usage = Crm::AiUsageEvent.find_by!(account_id: account.id)
    expect(usage.card_id).to be_nil
    expect(usage.cost_estimate).to eq(0.5)
  end

  it 'solta passagens e decisões de assunto, que são da conversa' do
    excluir

    expect(Crm::Passagem.where(conversation_id: conversation.id).pluck(:card_id)).to eq([nil])
    decisao = Crm::SubjectDecision.find_by!(conversation_id: conversation.id)
    expect([decisao.card_id, decisao.touched_card_ids]).to eq([nil, []])
  end

  it 'deixa os outros cards do mesmo contato e da mesma decisão como estavam' do
    outro = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Outro pedido')
    Crm::SubjectDecision.update_all(touched_card_ids: [card.id, outro.id]) # rubocop:disable Rails/SkipsModelValidations

    excluir

    expect(outro.reload).to be_present
    expect(Crm::SubjectDecision.first.touched_card_ids).to eq([outro.id])
  end

  it 'cancela a reunião futura no calendário antes de apagar' do
    futura = create_reuniao(account: account, card: card, user: user, contact: contact, starts_at: 2.days.from_now)
    cancelamentos = []
    allow(Crm::Meetings::CancelService).to receive(:new).and_wrap_original do |original, **args|
      cancelamentos << args[:meeting].id
      original.call(**args)
    end

    excluir

    expect(cancelamentos).to eq([futura.id])
    expect(Crm::Meeting.exists?(futura.id)).to be(false)
  end

  it 'não apaga nada quando o calendário não cancela a reunião' do
    futura = create_reuniao(account: account, card: card, user: user, contact: contact, starts_at: 2.days.from_now)
    servico = instance_double(Crm::Meetings::CancelService)
    # Google::CalendarError mora no arquivo do serviço.
    allow(servico).to receive(:perform).and_raise(Google::CalendarEventService.module_parent::CalendarError, 'indisponível')
    allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

    expect { excluir }.to raise_error(described_class::ReuniaoNaoCancelada) { |erro| expect(erro.meeting_id).to eq(futura.id) }
    expect(Crm::Card.exists?(card.id)).to be(true)
    expect(onde_o_card_ainda_aparece(card.id)).to include('crm_activities.card_id', 'crm_ai_usage_events.card_id')
  end

  it 'desiste quando uma reunião é marcada depois do cancelamento, em vez de apagá-la sem cancelar no calendário' do
    allow(Crm::Meetings::CancelarFuturas).to receive(:new).and_wrap_original do |original, **args|
      original.call(**args).tap do |cancelamento|
        allow(cancelamento).to receive(:perform).and_wrap_original do |perform|
          perform.call.tap { create_reuniao(account: account, card: card, user: user, contact: contact, starts_at: 3.days.from_now) }
        end
      end
    end

    expect { excluir }.to raise_error(Crm::ExclusaoDefinitiva::Mudou) { |erro| expect(erro.motivo).to eq('cards_changed') }
    expect(Crm::Card.exists?(card.id)).to be(true)
    expect(Crm::Meeting.where(card_id: card.id).upcoming.count).to eq(1)
  end

  it 'roda o bloco na mesma transação: se ele falhar, nada é apagado' do
    expect { excluir { raise ActiveRecord::RecordInvalid } }.to raise_error(ActiveRecord::RecordInvalid)

    expect(Crm::Card.exists?(card.id)).to be(true)
    expect(Crm::AiUsageEvent.find_by!(account_id: account.id).card_id).to eq(card.id)
  end

  it 'desiste antes do calendário quando um card não está mais arquivado, sem cancelar reunião nem apagar' do
    card.update!(status: :open)
    futura = create_reuniao(account: account, card: card, user: user, contact: contact, starts_at: 2.days.from_now)

    expect { excluir }.to raise_error(Crm::ExclusaoDefinitiva::Mudou) { |erro| expect([erro.motivo, erro.canceladas]).to eq(['not_archived', []]) }
    expect([Crm::Card.exists?(card.id), futura.reload.status]).to eq([true, 'scheduled'])
  end

  it 'apaga card aberto quando quem chama decide (contato da LGPD, funil com "apagar os cards")' do
    card.update!(status: :open)

    expect(described_class.new(account: account, card_ids: [card.id], somente_arquivados: false).perform).to eq([card.id])
    expect(onde_o_card_ainda_aparece(card.id)).to eq([])
  end

  it 'desiste quando a conferência do chamador barra, já dentro da transação' do
    conferir = ->(_ids) { raise Crm::ExclusaoDefinitiva::Mudou, 'cards_changed' }

    expect { described_class.new(account: account, card_ids: [card.id]).perform(conferir: conferir) }
      .to raise_error(Crm::ExclusaoDefinitiva::Mudou, /cards_changed/)
    expect(Crm::Card.exists?(card.id)).to be(true)
  end

  it 'ignora card de outra conta' do
    outra_conta = create(:account)
    outro_user = create(:user, account: outra_conta, role: :administrator)
    alheio = outra_conta.crm_cards.create!(pipeline: create_crm_pipeline(account: outra_conta, user: outro_user).first,
                                           stage: outra_conta.crm_pipeline_stages.first, title: 'Alheio')

    expect(excluir([alheio.id])).to eq([])
    expect(alheio.reload).to be_present
  end
end
