require 'rails_helper'

RSpec.describe Autonomia::Automacao::Contexto do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }

  def card(principal, contact: contato)
    Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Seguro auto', currency: 'BRL',
                      primary_conversation: principal, contact: contact)
  end

  it 'liga cada alvo aos outros dois pelas pontes', :aggregate_failures do
    do_card = card(conversa)

    expect([described_class.de(conversa).conversa, described_class.de(conversa).contato]).to eq([conversa, contato])
    expect([described_class.de(do_card).card, described_class.de(do_card).conversa, described_class.de(do_card).contato])
      .to eq([do_card, conversa, contato])
    expect([described_class.de(contato).conversa, described_class.de(contato).card]).to eq([nil, nil])
    expect(described_class.de(card(conversa, contact: nil)).contato).to eq(contato)
  end

  it 'rótulo e link saem do registro na hora, sem nada gravado', :aggregate_failures do
    do_card = card(nil)

    I18n.with_locale(:pt_BR) { expect(described_class.de(conversa).rotulo).to eq("Conversa ##{conversa.display_id}") }
    expect(described_class.de(do_card).rotulo).to include("##{do_card.id}", 'Seguro auto')
    expect(described_class.de(do_card).link).to eq("accounts/#{account.id}/crm?pipeline_id=#{do_card.pipeline_id}&card_id=#{do_card.id}")
    expect(described_class.de(contato).rotulo).to eq('Maria')
  end

  it 'visível para quem a política deixa ver; quem não é da conta não vê nada', :aggregate_failures do
    de_fora = create(:user)

    expect(described_class.de(conversa).visivel_para?(admin)).to be(true)
    expect(described_class.de(card(conversa)).visivel_para?(admin)).to be(true)
    expect(described_class.de(conversa).visivel_para?(de_fora)).to be(false)
    expect(described_class.de(contato).visivel_para?(nil)).to be(false)
  end

  # G43 x G53: depois do envio ao número novo, `conversa` é a do número novo, mas `falhou.*` continua lendo a mensagem
  # que falhou na conversa do gatilho.
  it 'a mensagem que falhou continua achada depois do envio ao número novo', :aggregate_failures do
    falhou = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :outgoing,
                              content: 'Seu boleto vence sexta', status: :failed)
    nova = create(:conversation, account: account, inbox: conversa.inbox, contact: contato)
    versao = create(:autonomia_automacao_versao, automacao: create(:autonomia_automacao, account: account))
    execucao = create(:autonomia_automacao_execucao, versao: versao, alvo: conversa,
                                                     chave_gatilho: Autonomia::Automacao::MensagemQueFalhou::TIPO,
                                                     evento: "#{Autonomia::Automacao::MensagemQueFalhou::TIPO}:#{falhou.id}")
    create(:autonomia_automacao_registro, execucao: execucao, passo: 'retomar',
                                          dados: { 'numero_novo' => true, 'conversa_aberta' => nova.display_id })

    contexto = described_class.de(conversa, execucao: execucao)

    expect(contexto.conversa).to eq(nova)
    expect(contexto.mensagem_que_falhou).to eq(falhou)
  end
end
