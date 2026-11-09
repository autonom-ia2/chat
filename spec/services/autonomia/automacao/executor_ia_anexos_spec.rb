require 'rails_helper'

# G20 (#2669): os passos de IA com `le: anexos`, de ponta a ponta no executor. O modelo é a OpenAI simulada no HTTP: o que
# o pedido levou (a foto, o PDF, a regra dos anexos) e o que o passo fez com a resposta.
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Bruno') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:corpos) { [] }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
  end

  after { Current.reset }

  def openai_devolve(resposta)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: resposta.to_json, usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def rodar(*passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, passos), conversa) }
  end

  def rodar_como(quem, *passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, quem, passos), conversa) }
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  def mensagem_com(arquivo, tipo, content_type, texto: nil)
    mensagem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: texto)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: tipo)
    anexo.file.attach(io: Rails.root.join("spec/assets/#{arquivo}").open, filename: arquivo, content_type: content_type)
    anexo.save!
  end

  def conteudo(corpo) = corpo['input'].first['content']

  def decidir(leituras)
    { 'id' => 'p1', 'tipo' => 'decidir', 'le' => leituras, 'pergunta' => 'O currículo tem o perfil da vaga?',
      'caminhos' => [{ 'nome' => 'Tem o perfil', 'chave' => 'perfil', 'descricao' => 'experiência na área', 'passos' => [prioridade_passo('p2')] },
                     { 'nome' => 'Sem o perfil', 'chave' => 'sem_perfil', 'descricao' => 'sem experiência', 'passos' => [] }],
      'nenhum' => [] }
  end

  # G46: `anexos_novos` passa pelo mesmo portão de `anexos` (NaConversa#sem_acesso, Acesso.alcanca?) antes de ler.
  it 'com anexos_novos, quem ligou sem acesso à conversa não manda anexo nenhum à IA; a automação pausa', :aggregate_failures do
    agente = create(:user, account: account, role: :agent)
    funcao = create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage])
    account.account_users.find_by(user: agente).update!(custom_role: funcao)
    create(:inbox_member, user: agente, inbox: conversa.inbox)
    openai_devolve('caminho' => 'perfil', 'motivo' => 'tem experiência')
    execucao = rodar_como(agente, esperar_passo('espera'), decidir(%w[anexos_novos]))
    mensagem_com('sample.pdf', :file, 'application/pdf')
    InboxMember.find_by(user: agente, inbox: conversa.inbox).destroy!

    travel(1.day + 1.minute) { varrer }

    expect(corpos).to be_empty
    expect([execucao.reload.estado, registros(execucao).last.last]).to eq(%w[parada quem_ligou_sem_acesso])
  end

  # G46: o que sai da leitura para sempre fica no histórico da execução, com qual anexo e por quê.
  it 'com anexos_novos, o registro do passo lista o anexo que ficou de fora e guarda o marco', :aggregate_failures do
    openai_devolve('caminho' => 'perfil', 'motivo' => 'tem experiência')
    execucao = rodar_como(admin, esperar_passo('espera'), decidir(%w[anexos_novos]))
    mensagem_com('sample.pdf', :file, 'application/pdf')
    audio = create(:message, conversation: conversa, account: account, message_type: :incoming, content: nil)
    fora = audio.attachments.new(account_id: account.id, file_type: :audio)
    fora.file.attach(io: Rails.root.join('spec/assets/sample.ogg').open, filename: 'sample.ogg', content_type: 'audio/ogg')
    fora.save!

    travel(1.day + 1.minute) { varrer }

    expect(conteudo(corpos.sole).pluck('type')).to include('input_file')
    dados = Autonomia::Automacao::Registro.find_by(execucao: execucao, passo: 'p1').dados
    expect(dados['anexos_fora']).to eq([{ 'message_id' => audio.id, 'attachment_id' => fora.id, 'motivo' => 'nao_e_foto_nem_pdf' }])
    expect(dados['marco_dos_anexos']).to include('lido_ate')
  end

  it 'o currículo em PDF, sem uma palavra, vai inteiro à IA e decide o caminho', :aggregate_failures do
    mensagem_com('sample.pdf', :file, 'application/pdf')
    openai_devolve('caminho' => 'perfil', 'motivo' => 'tem experiência')

    execucao = rodar(decidir(%w[mensagens_recentes anexos]))

    expect(registros(execucao)).to eq([['p1', 'ok', nil], ['p2', 'ok', nil]])
    partes = conteudo(corpos.sole)
    expect(partes.first['type']).to eq('input_text')
    expect(partes.last).to include('type' => 'input_file', 'filename' => 'sample.pdf')
    expect(partes.last['file_data']).to start_with('data:application/pdf;base64,')
    expect(corpos.sole['instructions']).to include(Autonomia::Automacao::AnexosDaConversa::REGRA)
  end

  it 'a foto do documento vai como imagem ao extrair, com o texto da conversa junto', :aggregate_failures do
    create(:custom_attribute_definition, account: account, attribute_key: 'cpf', attribute_model: 'contact_attribute',
                                         attribute_display_type: 'text')
    mensagem_com('avatar.png', :image, 'image/png', texto: 'Segue meu documento')
    openai_devolve('cpf' => '123.456.789-09')

    execucao = rodar({ 'id' => 'p1', 'tipo' => 'extrair', 'le' => %w[anexos],
                       'campos' => [{ 'chave' => 'cpf', 'descricao' => 'o CPF do documento', 'destino' => 'contato.atributos.cpf' }] })

    expect(registros(execucao)).to eq([['p1', 'ok', nil]])
    expect(contato.reload.custom_attributes['cpf']).to eq('123.456.789-09')
    partes = conteudo(corpos.sole)
    expect(partes.first['text']).to include('Segue meu documento')
    expect(partes.last['type']).to eq('input_image')
  end

  it 'sem pedir os anexos, nada muda: o pedido vai só com o texto, e o PDF sozinho não é lido', :aggregate_failures do
    mensagem_com('sample.pdf', :file, 'application/pdf', texto: 'Meu currículo')
    openai_devolve('caminho' => 'perfil', 'motivo' => 'ok')

    rodar(decidir(%w[mensagens_recentes]))

    expect(conteudo(corpos.sole).pluck('type')).to eq(%w[input_text])
    expect(corpos.sole['instructions']).not_to include(Autonomia::Automacao::AnexosDaConversa::REGRA)
  end

  it 'anexo que não pode ir à IA: o resumir pula com o motivo, sem chamar a IA', :aggregate_failures do
    mensagem_com('contacts.csv', :file, 'text/csv', texto: 'Planilha dos dependentes')
    openai_devolve('resumo' => 'nunca chega aqui')

    execucao = rodar({ 'id' => 'p1', 'tipo' => 'resumir', 'le' => %w[anexos], 'linhas' => 2, 'destino' => 'nota' })

    expect(registros(execucao)).to eq([%w[p1 pulado anexo_fora_do_formato]])
    expect(corpos).to be_empty
    expect(conversa.messages.where(private: true)).to be_empty
  end

  it 'no decidir, o anexo que não pode ir à IA segue por "nenhum se aplica", com o motivo no histórico', :aggregate_failures do
    mensagem_com('sample.mp3', :audio, 'audio/mpeg', texto: 'Mandei um áudio')
    openai_devolve('caminho' => 'perfil', 'motivo' => 'nunca chega aqui')
    passo = decidir(%w[anexos]).merge('nenhum' => [prioridade_passo('p9')])

    execucao = rodar(passo)

    expect(registros(execucao)).to eq([%w[p1 pulado anexo_sem_leitura], ['p9', 'ok', nil]])
    expect(corpos).to be_empty
  end

  it 'modelo do passo sem visão: pula com modelo_sem_imagem, sem trocar de modelo nem chamar a IA', :aggregate_failures do
    stub_const('Autonomia::Automacao::AnexosDaConversa::MODELOS_COM_IMAGEM', ['outro-modelo'])
    mensagem_com('avatar.png', :image, 'image/png', texto: 'Foto do RG')
    openai_devolve('resumo' => 'nunca chega aqui')

    execucao = rodar({ 'id' => 'p1', 'tipo' => 'resumir', 'le' => %w[anexos], 'linhas' => 2, 'destino' => 'nota' })

    expect(registros(execucao)).to eq([%w[p1 pulado modelo_sem_imagem]])
    expect(corpos).to be_empty
  end

  it 'o conteúdo do anexo nunca vai para o log' do
    mensagem_com('sample.pdf', :file, 'application/pdf')
    openai_devolve('caminho' => 'perfil', 'motivo' => 'ok')
    log = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))

    rodar(decidir(%w[anexos]))

    expect(log.string).not_to include(Base64.strict_encode64(Rails.root.join('spec/assets/sample.pdf').binread).first(40))
  end
end
