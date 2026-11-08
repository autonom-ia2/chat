require 'rails_helper'

# G42 (#2721) com função personalizada (parecer de Funções no #2763): o resumo em aviso só lê a resposta de outra conversa
# que todo destinatário vê. Quem vê o WhatsApp do alvo mas não a caixa do e-mail não recebe o que o cliente respondeu
# por e-mail.
RSpec.describe Autonomia::Automacao::PassoDeResumir, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:whatsapp) { create(:inbox, account: account) }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:contato) { create(:contact, account: account, name: 'Carla', email: 'cliente@exemplo.com') }
  let(:conversa) { create(:conversation, account: account, contact: contato, inbox: whatsapp) }
  let(:corpos) { [] }
  let(:atendente) do
    pessoa = create(:user, account: account, role: :agent)
    funcao = CustomRole.create!(account: account, name: 'Atende WhatsApp', permissions: %w[conversation_manage])
    AccountUser.find_by(account: account, user: pessoa).update!(custom_role: funcao)
    whatsapp.add_members([pessoa.id])
    pessoa
  end
  let(:passos) do
    [{ 'id' => 'p1', 'tipo' => 'email', 'caixa_id' => caixa_de_email.id, 'assunto' => ['Sua renovação'],
       'texto' => ['Oi, sua apólice vence em 5 dias.'] },
     esperar_passo('p2'),
     { 'id' => 'p3', 'tipo' => 'resumir', 'le' => %w[mensagens_com_respostas], 'linhas' => 3,
       'destino' => { 'avisar' => { 'pessoas' => [admin.id, atendente.id] } } },
     esperar_passo('p4')]
  end

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Quero renovar o seguro do carro')
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: 'resp_1', output_text: { resumo: 'Mandamos o e-mail.' }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  after { Current.reset }

  it 'o destinatário vê o alvo mas não a caixa do e-mail: a resposta do e-mail não vai à IA', :aggregate_failures do
    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, passos), conversa) }
    email = Conversation.find_by!(inbox: caixa_de_email)
    create(:message, conversation: email, account: account, message_type: :incoming, content: 'Meu CPF mudou, segue o novo')
    expect(Autonomia::Automacao::Acesso.alcanca?(atendente, conversa)).to be(true)
    expect(Autonomia::Automacao::Acesso.alcanca?(atendente, email)).to be(false)

    travel(2.days) { varrer }

    expect(corpos.sole['input'].to_s).not_to include('Meu CPF mudou, segue o novo')
    expect(corpos.sole['input'].to_s).to include('Quero renovar o seguro do carro')
    registro = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p3')
    expect(registro.dados).to include('pessoas' => contain_exactly(admin.id, atendente.id), 'conversas_fora' => [email.display_id])
  end
end
