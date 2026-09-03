require 'rails_helper'

# #284 (2b) — sugestão de FAQ: hash de dedupe e transições de revisão (via Approver).
RSpec.describe Autonomia::Agents::FaqSuggestion do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  def suggestion(question: 'Qual o prazo de entrega?', answer: 'Até 5 dias úteis.')
    agent.faq_suggestions.create!(account: account, question: question, answer: answer)
  end

  describe 'question_hash' do
    it 'normalizes accents, case, punctuation and spacing before hashing' do
      a = suggestion(question: 'Qual é o PRAZO de entrega?')
      b = suggestion(question: '  qual e o prazo, de entrega  ')

      expect(a.question_hash).to eq(b.question_hash)
      expect(a.question_hash).not_to eq(suggestion(question: 'Qual o valor do frete?').question_hash)
    end

    it 'requires question and answer' do
      expect(agent.faq_suggestions.new(account: account, question: '', answer: 'x')).not_to be_valid
      expect(agent.faq_suggestions.new(account: account, question: 'x', answer: '')).not_to be_valid
    end
  end

  describe 'review transitions' do
    let(:writer) { instance_double(Autonomia::Agents::Faq::KnowledgeWriter) }

    before do
      allow(Autonomia::Agents::Faq::KnowledgeWriter).to receive(:new).and_return(writer)
      allow(writer).to receive(:write!).and_return(instance_double(Autonomia::Agents::KnowledgeEntry, id: 1))
    end

    it 'approves a pending suggestion and stamps the reviewer' do
      record = suggestion

      Autonomia::Agents::Faq::Approver.new(suggestion: record, user: admin).approve!

      expect(record.reload).to be_approved
      expect(record.reviewed_by).to eq(admin)
      expect(record.reviewed_at).to be_present
    end

    it 'marks as edited when the text changed on approval' do
      record = suggestion

      Autonomia::Agents::Faq::Approver.new(suggestion: record, user: admin).approve!(answer: 'Até 3 dias úteis.')

      expect(record.reload).to be_edited
      expect(record.answer).to eq('Até 3 dias úteis.')
    end

    it 'ignores a pending suggestion without writing knowledge' do
      record = suggestion

      Autonomia::Agents::Faq::Approver.new(suggestion: record, user: admin).ignore!

      expect(record.reload).to be_ignored
      expect(writer).not_to have_received(:write!)
    end

    it 'refuses to approve or ignore a suggestion that was already reviewed' do
      record = suggestion
      Autonomia::Agents::Faq::Approver.new(suggestion: record, user: admin).ignore!

      expect { Autonomia::Agents::Faq::Approver.new(suggestion: record, user: admin).approve! }
        .to raise_error(Autonomia::Agents::Faq::Approver::NotPending)
      expect { Autonomia::Agents::Faq::Approver.new(suggestion: record, user: admin).ignore! }
        .to raise_error(Autonomia::Agents::Faq::Approver::NotPending)
    end
  end
end
