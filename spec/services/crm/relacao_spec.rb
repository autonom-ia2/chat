require 'rails_helper'

# #2084/#2085: "Este contato é" — interessado (o padrão), parceiro do mercado ou não é negócio. Uma regra só, atrás da
# flag contato_relacao; desligada, todo contato é do funil.
RSpec.describe Crm::Relacao do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: ana) }
  let(:interessado) { create(:contact, account: account) }
  let(:parceiro) { create(:contact, account: account, relacao: :parceiro) }
  let(:lixo) { create(:contact, account: account, relacao: :nao_e_negocio) }

  def card(contact)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: ana, contact: contact,
                              title: "Card #{SecureRandom.hex(3)}")
  end

  it 'todo contato nasce interessado' do
    expect(create(:contact, account: account)).to be_relacao_interessado
  end

  context 'with contato_relacao off' do
    it 'ninguém fica fora do funil e todos os cards contam' do
      cards = [card(interessado), card(parceiro), card(lixo)]

      expect([interessado, parceiro, lixo].map { |c| described_class.fora_do_funil?(c) }).to all(be(false))
      expect(described_class.cards_do_funil(account)).to match_array(cards)
    end
  end

  context 'with contato_relacao on' do
    before { account.enable_features!('contato_relacao') }

    it 'parceiro e não é negócio ficam fora do funil; interessado e contato nenhum, não' do
      expect(described_class.fora_do_funil?(parceiro)).to be(true)
      expect(described_class.fora_do_funil?(lixo)).to be(true)
      expect(described_class.fora_do_funil?(interessado)).to be(false)
      expect(described_class.fora_do_funil?(nil)).to be(false)
    end

    it 'os Números contam o card de interessado e o card sem contato, e não os de quem está fora do funil' do
      do_interessado = card(interessado)
      sem_contato = card(nil)
      card(parceiro)
      card(lixo)

      expect(described_class.cards_do_funil(account)).to contain_exactly(do_interessado, sem_contato)
    end

    # O Crm::Card já recusa contato de outra conta; a conta no NOT EXISTS segura dado antigo que escapou disso.
    it 'não mistura contas: só o contato desta conta tira card dos Números desta' do
      outra = create(:account)
      outra.enable_features!('contato_relacao')
      parceiro_da_outra = create(:contact, account: outra, relacao: :parceiro)
      do_interessado = card(interessado)
      com_contato_de_fora = card(interessado)
      com_contato_de_fora.update_columns(contact_id: parceiro_da_outra.id) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.cards_do_funil(account)).to contain_exactly(do_interessado, com_contato_de_fora)
      expect(described_class.cards_do_funil(outra)).to be_empty
    end
  end
end
