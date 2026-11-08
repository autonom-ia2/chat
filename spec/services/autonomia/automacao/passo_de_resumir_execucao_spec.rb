require 'rails_helper'

# G42 (#2721, exemplo 1, passo 12): o "resumir" conta tudo o que a execução tentou. Lê a conversa do alvo e as conversas
# em que a própria execução mandou mensagem (o e-mail abre uma conversa própria), só as que quem ligou vê, com o envio
# recusado marcado. O modelo é a OpenAI simulada no HTTP.
RSpec.describe Autonomia::Automacao::PassoDeResumir, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:whatsapp) { create(:inbox, account: account) }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Carla', email: 'cliente@exemplo.com') }
  let(:conversa) { create(:conversation, account: account, contact: contato, inbox: whatsapp) }
  let(:corpos) { [] }
  let(:destino) { { 'avisar' => { 'pessoas' => [admin.id] } } }
  let(:passos) do
    [{ 'id' => 'p1', 'tipo' => 'email', 'caixa_id' => caixa_de_email.id, 'assunto' => ['Sua renovação'],
       'texto' => ['Oi, sua apólice vence em 5 dias.'] },
     mensagem_passo('p2', 'Oi, viu o e-mail da renovação?'),
     esperar_passo('p3'),
     { 'id' => 'p4', 'tipo' => 'resumir', 'le' => %w[mensagens_com_respostas], 'linhas' => 3, 'destino' => destino },
     esperar_passo('p5')]
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
      payload = { id: 'resp_1', output_text: { resumo: 'Tentamos e-mail e WhatsApp.' }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  after { Current.reset }

  # Começa a automação, faz o que o bloco disser enquanto ela espera, e roda o resumo no dia seguinte.
  def rodar
    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, passos), conversa) }
    yield execucao if block_given?
    travel(2.days) { varrer }
    execucao
  end

  # O que foi à IA: o JSON do texto da entrada.
  def entrada = JSON.parse(corpos.sole['input'].first['content'].first['text'])['conversa']

  def conversa_de_email = Conversation.find_by!(inbox: caixa_de_email)

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado)

  it 'o e-mail que a execução mandou, em conversa própria, entra no resumo com a resposta que veio nela', :aggregate_failures do
    execucao = rodar do
      create(:message, conversation: conversa_de_email, account: account, message_type: :incoming, content: 'Recebi, vou ver amanhã')
    end

    expect(registros(execucao)).to include(%w[p4 ok])
    expect(corpos.sole['input'].to_s).to include('Oi, sua apólice vence em 5 dias.', 'Sua renovação', 'Recebi, vou ver amanhã')
    expect(corpos.sole['input'].to_s).to include('Oi, viu o e-mail da renovação?', 'Quero renovar o seguro do carro')
    expect(corpos.sole['instructions']).to include('automation_sends', 'not_delivered')
  end

  # A nota todos da conversa do alvo leem: a resposta de outra caixa não entra, e o histórico diz qual ficou de fora.
  context 'when o resumo vai numa nota' do
    let(:destino) { 'nota' }

    it 'lê só outra conversa da mesma caixa do alvo; a do e-mail fica de fora e vai ao histórico', :aggregate_failures do
      execucao = rodar do
        create(:message, conversation: conversa_de_email, account: account, message_type: :incoming, content: 'Resposta por e-mail')
      end

      expect(corpos.sole['input'].to_s).not_to include('Resposta por e-mail')
      expect(corpos.sole['input'].to_s).to include('Oi, sua apólice vence em 5 dias.')
      registro = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p4')
      expect(registro.dados).to include('conversas_fora' => [conversa_de_email.display_id])
      expect(execucao.reload.textos).to include('p4' => 'Tentamos e-mail e WhatsApp.')
    end
  end

  it 'o resumo que leu outra conversa não fica guardado para um passo seguinte', :aggregate_failures do
    execucao = rodar do
      create(:message, conversation: conversa_de_email, account: account, message_type: :incoming, content: 'Recebi, vou ver amanhã')
    end

    expect(registros(execucao)).to include(%w[p4 ok])
    expect(execucao.reload.textos).not_to have_key('p4')
  end

  # No OSS só o administrador liga automação, e ele vê toda caixa: a pergunta à política da conversa (a mesma do
  # "avisar") responde que não para a conversa do e-mail.
  it 'a conversa de uma caixa que quem ligou não vê fica de fora', :aggregate_failures do
    execucao = rodar do
      create(:message, conversation: conversa_de_email, account: account, message_type: :incoming, content: 'Resposta escondida')
      allow(Autonomia::Automacao::Acesso).to receive(:alcanca?).and_call_original
      allow(Autonomia::Automacao::Acesso).to receive(:alcanca?).with(admin, conversa_de_email).and_return(false)
    end

    expect(registros(execucao)).to include(%w[p4 ok])
    expect(corpos.sole['input'].to_s).not_to include('Oi, sua apólice vence em 5 dias.', 'Resposta escondida', 'Sua renovação')
    expect(corpos.sole['input'].to_s).to include('Oi, viu o e-mail da renovação?')
  end

  it 'o envio que o canal recusou vai marcado como não entregue', :aggregate_failures do
    rodar do
      conversa.messages.outgoing.find_by!(content: 'Oi, viu o e-mail da renovação?').update!(status: :failed)
    end

    envios = entrada['automation_sends']
    expect(envios.find { |envio| envio['text'] == 'Oi, viu o e-mail da renovação?' }).to include('not_delivered' => true)
    expect(envios.find { |envio| envio['text'] == 'Oi, sua apólice vence em 5 dias.' }).not_to have_key('not_delivered')
  end

  it 'outras conversas do contato, que a execução não tocou, não entram' do
    outra = create(:conversation, account: account, contact: contato, inbox: whatsapp)
    create(:message, conversation: outra, account: account, message_type: :outgoing, content: 'Conversa antiga de outro assunto')

    rodar

    expect(corpos.sole['input'].to_s).not_to include('Conversa antiga de outro assunto')
  end
end
