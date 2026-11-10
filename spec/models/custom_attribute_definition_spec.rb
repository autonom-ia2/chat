# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomAttributeDefinition do
  let(:account) { create(:account) }

  describe 'validations' do
    describe 'attribute_key format' do
      it 'allows alphanumeric keys with underscores' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'order_date_1')
        expect(cad).to be_valid
      end

      it 'allows hyphens and dots' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'order-date.v2')
        expect(cad).to be_valid
      end

      it 'allows Unicode letters' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: '客户类型')
        expect(cad).to be_valid
      end

      it 'rejects keys with single quotes' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: "x'||(SELECT 1)||'")
        expect(cad).not_to be_valid
        expect(cad.errors[:attribute_key]).to be_present
      end

      it 'rejects keys with spaces' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'order date')
        expect(cad).not_to be_valid
      end

      it 'rejects keys with semicolons' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'key; DROP TABLE users--')
        expect(cad).not_to be_valid
      end

      it 'rejects keys with parentheses' do
        cad = build(:custom_attribute_definition, account: account, attribute_key: 'key()')
        expect(cad).not_to be_valid
      end

      it 'allows company custom attributes' do
        cad = build(:custom_attribute_definition, account: account, attribute_model: 'company_attribute')
        expect(cad).to be_valid
      end

      it 'rejects company custom attributes that conflict with standard company fields' do
        cad = build(:custom_attribute_definition, account: account, attribute_model: 'company_attribute', attribute_key: 'domain')
        expect(cad).not_to be_valid
        expect(cad.errors[:attribute_key]).to be_present
      end
    end
  end

  describe 'callbacks' do
    describe '#strip_attribute_key' do
      it 'strips leading and trailing whitespace from attribute_key' do
        cad = create(:custom_attribute_definition, account: account, attribute_key: '  order_date  ')
        expect(cad.attribute_key).to eq('order_date')
      end

      it 'strips leading and trailing whitespace from attribute_display_name' do
        cad = create(:custom_attribute_definition, account: account, attribute_display_name: '  Order Date  ')
        expect(cad.attribute_display_name).to eq('Order Date')
      end
    end

    describe 'filtered unread count invalidation' do
      let(:invalidator) { instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, custom_attribute_definition_changed!: true) }

      before do
        allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).with(account).and_return(invalidator)
        allow(Rails.configuration.dispatcher).to receive(:dispatch)
      end

      it 'invalidates conversation filters when a conversation custom attribute definition changes' do
        cad = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute')

        cad.update!(attribute_display_name: 'Updated Order Date')

        expect(invalidator).to have_received(:custom_attribute_definition_changed!).with(cad)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          'account.cache_invalidated',
          kind_of(Time),
          account: account,
          cache_keys: account.cache_keys
        )
      end

      it 'invalidates conversation filters when a conversation custom attribute definition is deleted' do
        cad = create(:custom_attribute_definition, account: account, attribute_model: 'conversation_attribute')

        cad.destroy!

        expect(invalidator).to have_received(:custom_attribute_definition_changed!).with(cad)
        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          'account.cache_invalidated',
          kind_of(Time),
          account: account,
          cache_keys: account.cache_keys
        )
      end

      it 'ignores contact custom attribute definition changes' do
        cad = create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute')

        cad.update!(attribute_display_name: 'Updated Contact Field')

        expect(invalidator).not_to have_received(:custom_attribute_definition_changed!)
        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      end
    end
  end

  describe 'card attribute (#1146)' do
    it 'não mexe no formulário de pré-chat do widget, mesmo com a chave de um campo de contato' do
      definition = create(:custom_attribute_definition, account: account, attribute_key: 'cidade', attribute_model: 'card_attribute')

      expect { definition.update!(attribute_display_name: 'Cidade do pedido') }
        .not_to have_enqueued_job(Inboxes::UpdateWidgetPreChatCustomFieldsJob)
      expect { definition.destroy! }.not_to have_enqueued_job(Inboxes::SyncWidgetPreChatCustomFieldsJob)
    end

    it 'recusa chave que é campo padrão do card' do
      definition = build(:custom_attribute_definition, account: account, attribute_key: 'title', attribute_model: 'card_attribute')

      expect(definition).not_to be_valid
    end
  end

  # Decisão 16 (ex. 11): o tipo Contato só existe no card, e o campo que uma automação ligada lê para achar o contato
  # ligado não troca de tipo nem é apagado.
  describe 'tipo contato' do
    def campo(modelo = :card_attribute)
      create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_model: modelo,
                                           attribute_display_type: :contato)
    end

    def automacao_que_le(chave, ativa: true)
      passo = { 'id' => 'outro', 'tipo' => 'em_outro_registro', 'passos' => [],
                'registro' => { 'de' => 'contato_do_campo', 'campo' => { '$valor' => "card.atributos.#{chave}" }, 'usar' => 'conversa' } }
      automacao = create(:autonomia_automacao, account: account, nome: 'Indicação', ativa: ativa)
      versao = create(:autonomia_automacao_versao, automacao: automacao, receita: { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [passo] })
      automacao.update!(versao_ativa: versao)
      automacao
    end

    let(:em_uso) { I18n.t('errors.custom_attribute_definition.contato_em_uso', automacoes: 'Indicação') }

    it 'só no card: no contato, na conversa e na empresa é recusado', :aggregate_failures do
      expect(build(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_display_type: :contato))
        .to be_valid
      %i[contact_attribute conversation_attribute company_attribute].each do |modelo|
        definicao = build(:custom_attribute_definition, account: account, attribute_model: modelo, attribute_display_type: :contato)
        expect(definicao).not_to be_valid
        expect(definicao.errors[:attribute_display_type]).to eq([I18n.t('errors.custom_attribute_definition.contato_so_no_card')])
      end
    end

    it 'lido por automação ligada: não troca de tipo, de chave, nem é apagado', :aggregate_failures do
      definicao = campo
      automacao_que_le('indicado_por')

      expect(definicao.update(attribute_display_type: :number)).to be(false)
      expect(definicao.errors[:base]).to eq([em_uso])
      expect(definicao.reload.update(attribute_key: 'quem_indicou')).to be(false)
      expect(definicao.reload.destroy).to be(false)
      expect(definicao.errors[:base]).to eq([em_uso])
      expect(described_class.exists?(definicao.id)).to be(true)
      expect(definicao.reload.update(attribute_display_name: 'Quem indicou')).to be(true)
    end

    it 'com a automação desligada, ou lendo outro campo, troca e apaga', :aggregate_failures do
      definicao = campo
      automacao_que_le('indicado_por', ativa: false)
      automacao_que_le('outro_campo')

      expect(definicao.update(attribute_display_type: :number)).to be(true)
      expect(definicao.destroy).to be_truthy
    end
  end
end
