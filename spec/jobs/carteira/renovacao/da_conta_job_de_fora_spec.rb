require 'rails_helper'

# E6.5 (#2899) — a rotina da renovação e o seguro de outra corretora: ele só ganha card quando a pessoa quis o lembrete
# (`lembrete_aceito_em`). Sem o lembrete, nunca ganha card nem mensagem. Tudo fictício.
RSpec.describe Carteira::Renovacao::DaContaJob do
  let(:agora) { Time.utc(2026, 11, 13, 15, 0) }
  let(:hoje) { Date.new(2026, 11, 13) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Renovação') }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000051') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    create(:carteira_renovacao_config, account: account, pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, dias_antes: 60)
  end

  def de_fora(lembrete_aceito_em:)
    criar_apolice(marina, seguradora: 'Seguradora Exemplo', numero: nil, fim_vigencia: hoje + 30, de_fora: true,
                          corretora_de_fora: 'Corretora Exemplo', lembrete_aceito_em: lembrete_aceito_em)
  end

  it 'o seguro de outra corretora sem o lembrete não ganha card' do
    seguro = de_fora(lembrete_aceito_em: nil)

    described_class.perform_now(account.id)

    expect(Crm::Card.where(account_id: account.id)).to be_empty
    expect(seguro.reload.crm_card_id).to be_nil
    expect(seguro.eventos).to be_empty
  end

  it 'o seguro de outra corretora com o lembrete aceito ganha o card como os da carteira' do
    seguro = de_fora(lembrete_aceito_em: 1.day.ago)

    described_class.perform_now(account.id)

    card = Crm::Card.where(account_id: account.id).sole
    expect(seguro.reload.crm_card_id).to eq(card.id)
    expect(card.contact_id).to eq(marina.id)
  end

  it 'a conferida sob a trava também barra o seguro de fora sem lembrete' do
    sem = de_fora(lembrete_aceito_em: nil)
    com = criar_apolice(marina, seguradora: 'Seguradora Exemplo', numero: nil, fim_vigencia: hoje + 31, de_fora: true,
                                lembrete_aceito_em: 1.day.ago)

    expect(Carteira::Renovacao::EntramHoje.entra?(sem)).to be(false)
    expect(Carteira::Renovacao::EntramHoje.entra?(com)).to be(true)
  end
end
