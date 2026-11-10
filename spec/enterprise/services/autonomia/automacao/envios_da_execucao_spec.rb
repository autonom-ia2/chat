require 'rails_helper'

# G68/G42 (parecer de Funções no #2876): a resposta de outra conversa só vai ao resumo/extrair quando toda pessoa que vê a
# conversa do alvo também a vê. Quem tem só "Ver conversas" (conversation_view) lê a conversa do alvo pela view?, então
# conta: na caixa do WhatsApp e fora da do e-mail, o e-mail fica de fora.
RSpec.describe Autonomia::Automacao::EnviosDaExecucao do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:leitor) { create(:user, account: account, role: :agent) }
  let(:whatsapp) { create(:inbox, account: account) }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:contato) { create(:contact, account: account) }
  let(:alvo) { create(:conversation, account: account, inbox: whatsapp, contact: contato) }
  let(:do_email) { create(:conversation, account: account, inbox: caixa_de_email, contact: contato) }
  let(:automacao) { create(:autonomia_automacao, account: account, ligada_por: admin) }
  let(:execucao) do
    create(:autonomia_automacao_execucao, automacao: automacao, alvo: alvo, versao: create(:autonomia_automacao_versao, automacao: automacao))
  end

  before do
    create(:inbox_member, user: leitor, inbox: whatsapp)
    role = create(:custom_role, account: account, permissions: %w[conversation_view])
    leitor.account_users.find_by!(account: account).update!(custom_role: role)
    enviado = create(:message, conversation: do_email, account: account, inbox: caixa_de_email, message_type: :outgoing, content: 'Renovação')
    create(:message, conversation: do_email, account: account, inbox: caixa_de_email, message_type: :incoming, sender: contato,
                     content: 'Resposta do e-mail')
    Autonomia::Automacao::Registro.create!(account: account, automacao: automacao, execucao: execucao, passo: 'email', resultado: 'ok',
                                           dados: { 'mensagem_id' => enviado.id })
  end

  def envios = described_class.new(execucao: execucao, conversa: alvo, leituras: %w[mensagens_recentes])

  it 'quem só lê a conversa do alvo e não vê o e-mail deixa o e-mail de fora', :aggregate_failures do
    expect(ConversationPolicy.new({ user: leitor, account: account, account_user: leitor.account_users.first }, alvo)).to be_view
    expect(envios.dados).not_to have_key(:other_conversations)
    expect(envios.outras_lidas?).to be(false)
    expect(envios.fora).to eq([do_email.display_id])
  end

  it 'com o leitor também na caixa do e-mail, a resposta entra', :aggregate_failures do
    create(:inbox_member, user: leitor, inbox: caixa_de_email)

    expect(envios.dados[:other_conversations].to_json).to include('Resposta do e-mail')
    expect(envios.fora).to eq([])
  end
end
