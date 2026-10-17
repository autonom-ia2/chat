require 'rails_helper'
require_relative 'inbound_context'

# chat#1709 (revisão): as consultas SQL do pacote sobre colunas JSON leem a chave nos dois formatos em que a linha pode
# estar gravada: objeto (`{"c2y_hidden":true}`) e string JSON com o objeto dentro (a codificação dupla do
# `store ... coder: JSON`, o caso comum em produção).
describe Waha::RichNative::JsonColumn do
  include_context 'with a waha inbox and its connector'

  formats = %i[object string]

  # Grava a coluna direto no banco, no formato pedido.
  def write!(message, column, hash, format:)
    raw = format == :string ? hash.to_json.to_json : hash.to_json
    type = column == :content_attributes ? 'json' : 'jsonb'
    Message.where(id: message.id).update_all(["#{column} = ?::#{type}", raw]) # rubocop:disable Rails/SkipsModelValidations
    expect(Message.where(id: message.id).pick(Arel.sql("#{type}_typeof(#{column})"))).to eq(format == :string ? 'string' : 'object')
  end

  def incoming(content = 'oi')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content,
                     sender: conversation.contact)
  end

  describe 'the history window of the AI (AgentTurnGuard#c2y_uncounted_ids)' do
    let(:responder) { Autonomia::Agents::Operate::Responder.allocate.tap { |r| r.instance_variable_set(:@conversation, conversation) } }

    before { flag_on! }

    def uncounted
      responder.send(:c2y_uncounted_ids, conversation.messages.chat)
    end

    { 'c2y_hidden' => true, 'is_unsupported' => true, 'view_once_unavailable' => true,
      'deleted_by_contact_at' => '2026-10-17T10:00:00Z' }.each do |key, value|
      formats.each do |format|
        it "finds #{key} stored as #{format}" do
          marked = incoming
          real = incoming('real')
          write!(marked, :content_attributes, { key => value }, format: format)
          write!(real, :content_attributes, { 'outro' => true }, format: format)

          expect(uncounted).to eq([marked.id])
        end
      end
    end

    # Revisão: o SQL e o Ruby (TurnKinds.deleted?, `present?`) concordam sobre a apagada, nos dois formatos.
    it 'agrees with the Ruby predicate on what a present deleted_by_contact_at is' do
      values = [nil, false, '', '   ', [], {}, true, 0, '2026-10-17T10:00:00Z', ['x'], { 'a' => 1 }]
      formats.each do |format|
        messages = values.map do |value|
          incoming.tap { |message| write!(message, :content_attributes, { 'deleted_by_contact_at' => value }, format: format) }
        end
        # O mesmo valor lido pelo Ruby (numa mensagem em memória: a linha gravada como objeto nem é legível pelo
        # `store coder: JSON` do modelo, só pelo SQL).
        ruby = values.zip(messages).filter_map do |value, message|
          message.id if Waha::RichNative::TurnKinds.deleted?(Message.new(content_attributes: { 'deleted_by_contact_at' => value }))
        end

        expect(uncounted).to match_array(ruby), "format #{format}"
        expect(ruby.size).to eq(5)
        Message.where(id: messages.map(&:id)).delete_all
      end
    end

    it 'does not count a false flag or a null deletion' do
      a = incoming
      b = incoming
      write!(a, :content_attributes, { 'is_unsupported' => false }, format: :string)
      write!(b, :content_attributes, { 'deleted_by_contact_at' => nil }, format: :object)

      expect(uncounted).to be_empty
    end
  end

  describe 'the 24 h window (WhatsappHybrid::RichNative::WindowNeutral.opening)' do
    formats.each do |format|
      it "drops the neutral message stored as #{format} and keeps the real one" do
        neutral = incoming
        real = incoming('real')
        write!(neutral, :additional_attributes, { WhatsappHybrid::RichNative::WindowNeutral::KEY => true }, format: format)
        write!(real, :additional_attributes, { 'outro' => true }, format: format)

        expect(WhatsappHybrid::RichNative::WindowNeutral.opening(conversation.messages.incoming).pluck(:id)).to eq([real.id])
      end
    end
  end
end
