require 'rails_helper'

# E8 (#2901): o card de renovação que acabou de nascer pede a cotação, só com o portão aberto (a carteira, a chave da
# cotação e alguém escolhido para cotar). Sem a chave, a renovação é a da E5. Tudo fictício.
RSpec.describe Carteira::Cotacao::Gatilho do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, seguradora: 'Seguradora Exemplo', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def nascer(ajustes)
    por_em_renovacao(seguro, ajustes)
  end

  it 'sem a chave da cotação, o card nasce como na E5 e nada é pedido, mesmo com quem cota escolhido' do
    ajustes = escolher_funil_de_renovacao(account, user: admin, inbox: caixa, quem_cota: 'robo', quem_envia: 'sozinho')

    expect { nascer(ajustes) }.not_to have_enqueued_job(Carteira::Cotacao::ComecarJob)
    expect(seguro.reload.crm_card).to be_present
    expect(tipos_da_historia(seguro)).to eq(['renovacao_card_nasceu'])
  end

  it 'sem a carteira na conta, nada é pedido' do
    ajustes = cotacao_ligada(account, user: admin, caixa: caixa)
    sem_a_carteira!(account)

    expect(Carteira::Cotacao.aberta?(account.reload, ajustes)).to be(false)
  end

  # As seis combinações do aceite: quem cota (robo, lia, ninguem) × quem envia (pessoa, sozinho). Ninguém não pede nada;
  # o modo de envio só pesa quando a proposta fica pronta (Carteira::Cotacao::Pronta).
  [%w[robo pessoa], %w[robo sozinho], %w[lia pessoa], %w[lia sozinho], %w[ninguem pessoa], %w[ninguem sozinho]].each do |quem_cota, quem_envia|
    it "#{quem_cota} × #{quem_envia}: #{quem_cota == 'ninguem' ? 'não pede' : 'pede'} a cotação do card que nasceu" do
      ajustes = cotacao_ligada(account, user: admin, caixa: caixa, quem_cota: quem_cota, quem_envia: quem_envia)

      if quem_cota == 'ninguem'
        expect { nascer(ajustes) }.not_to have_enqueued_job(Carteira::Cotacao::ComecarJob)
      else
        expect { nascer(ajustes) }.to have_enqueued_job(Carteira::Cotacao::ComecarJob).with(seguro.id, seguro.fim_vigencia.iso8601)
      end
    end
  end

  it 'o card que não nasce (o seguro já tem card) não pede de novo' do
    ajustes = cotacao_ligada(account, user: admin, caixa: caixa)
    nascer(ajustes)

    expect { Carteira::Renovacao::CriarCard.new(account, ajustes).call(seguro.reload) }.not_to have_enqueued_job(Carteira::Cotacao::ComecarJob)
  end
end
