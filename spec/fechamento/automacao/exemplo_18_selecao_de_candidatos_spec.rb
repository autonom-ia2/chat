require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 18 dos termos de aceite: "Seleção de candidatos sem planilha".
#
# > "Abri vaga de recepcionista e chegam currículos pelo WhatsApp. Quero que o sistema separe os bons e marque a
# > entrevista." — Dra. Patrícia, dona da clínica
#
# Começa quando: mensagem com currículo (PDF ou foto) na caixa de vagas.
#   1. A IA extrai do currículo nome, bairro, experiência e se tem curso de atendimento.
#   2. Cria o card no quadro "Seleção – Recepcionista".
#   3. A IA decide: "atende o perfil", "talvez" ou "não atende", pelos requisitos que a doutora escreveu.
#   4. Atende o perfil: manda o link da agenda de entrevistas e põe a etiqueta "entrevista".
#   5. Talvez: avisa a doutora com um resumo de 3 linhas para ela decidir.
#   6. Não atende: agradece com educação e fecha o card.
#   7. Perguntas sobre salário e horário: passa para a agente de IA, que responde com o texto da vaga.
#   8. 1 dia antes da entrevista, pelo modelo aprovado: lembra a candidata do endereço.
#   9. A recepção arrasta o card para "Não compareceu": fecha o card com esse motivo.
# Resultado: a doutora abre o quadro e vê só as candidatas com perfil, já com entrevista marcada. Todas recebem resposta.
# Convive: na caixa de vagas, a IA de assunto fica desligada (ela é configurada por caixa), e o quadro de seleção fica
# sem "Mover automaticamente", para a IA não arquivar o currículo como "não é negócio".
#
# Montado como a Dra. Patrícia montaria, pela API da tela, em quatro automações: a da seleção (passos 1 a 6, na
# mensagem recebida na caixa de vagas), a das perguntas da vaga (passo 7, na mesma mensagem, com a agente de IA da vaga,
# G15), a do lembrete (passo 8, G32) e a do "Não compareceu" (passo 9, card que entra na etapa, G5, fechado pela G25).
# O currículo vai inteiro à IA (`le: anexos`, G20); o extraído fica no contato da candidata; o card nasce pelo passo
# "card" (G4). A IA é o dublê, que responde a cada "decidir" pela pergunta dele. Desenho e lacunas:
# docs/automacao/F9-fechamento-20-exemplos.md.
#
# O que ainda não monta, cada um no exemplo do passo, escrito como o termo pede:
# - Gatilho (G49): o filtro da mensagem só lê tipo, privada e primeira; "com currículo" (com anexo) não existe, e cada
#   mensagem da candidata roda a seleção de novo.
# - Passo 4 (G18): o link da agenda que a receita lê na conversa é o da pessoa dela (`conversa.link_da_agenda`). A conversa
#   da caixa de vagas não tem pessoa: quem atende é a agente de IA (passo 7, que pula com uma pessoa no nome). O link de
#   quem entrevista é o do card da seleção, e o card não é o alvo da automação da mensagem.
# - Passo 6 (G18): fechar o card criado no passo 2 é agir no card a partir da conversa; o salvar recusa `card.id`, e a
#   receita inteira não salva com ele. Por isso a receita dos outros passos vem sem o fechar.
# - Passo 8 (G32): o gatilho "antes da reunião" (`card.antes_da_reuniao`) ainda não está nesta base.
RSpec.describe 'Fechamento #2414 · exemplo 18: seleção de candidatos sem planilha', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true',
                      AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { exemplo.run }
  end

  def requisitos
    'Mora perto da clínica (Vila Mariana, Saúde ou Ipiranga), tem pelo menos 1 ano de atendimento ao público e ' \
      'curso de atendimento ou recepção.'
  end

  def pergunta_do_perfil = "A candidata atende o perfil da vaga de recepcionista? Requisitos da doutora: #{requisitos}"
  def pergunta_da_vaga = 'A candidata está perguntando sobre o salário ou o horário da vaga?'
  def texto_da_vaga = 'Vaga de recepcionista: segunda a sexta, das 8h às 17h, salário de R$ 2.200 mais vale-transporte.'
  def endereco = 'Rua Domingos de Morais, 1000, Vila Mariana'

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:patricia) { create(:user, account: account, role: :administrator, name: 'Dra. Patrícia') }
  let(:recepcao) { create(:user, account: account, role: :agent, name: 'Bianca Recepção') }
  # O WhatsApp não trouxe o nome: o contato nasce com o telefone, e o nome vem do currículo.
  let(:candidata) { create(:contact, account: account, name: '+5511900000018', phone_number: '+5511900000018') }
  let(:contact_inbox) { create(:contact_inbox, inbox: vagas, contact: candidata, source_id: '5511900000018') }
  let(:conversa) { create(:conversation, account: account, inbox: vagas, contact: candidata, contact_inbox: contact_inbox, status: :open) }
  let(:selecao) do
    funil = account.crm_pipelines.create!(name: 'Seleção – Recepcionista', created_by: patricia, status: :active)
    # Convive: o quadro de seleção sem "Mover automaticamente".
    funil.update!(metadata: funil.metadata.deep_merge('ai' => { 'auto_move_enabled' => false }))
    funil
  end
  let(:triagem) { account.crm_pipeline_stages.create!(pipeline: selecao, name: 'Currículo recebido', position: 0) }
  let(:nao_compareceu) { create_crm_stage(account: account, pipeline: selecao, name: 'Não compareceu', position: 1) }
  let(:entrevistas) { create_booking_profile(account: account, host: recepcao, title: 'Entrevistas', pipeline: selecao, stage: triagem) }
  let(:agente_da_vaga) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Vaga de recepcionista', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: "Responda às candidatas com o texto da vaga. #{texto_da_vaga}")
  end
  let(:respostas) do
    { 'automacao_extrair' => { 'nome' => 'Júlia Ramos', 'bairro' => 'Vila Mariana', 'experiencia' => '2 anos de recepção em consultório',
                               'curso_de_atendimento' => true },
      'automacao_resumir' => { 'resumo' => "Júlia Ramos, Ipiranga.\n8 meses de atendimento em loja.\nSem curso de atendimento." },
      pergunta_do_perfil => { 'caminho' => 'nenhum', 'motivo' => 'sem currículo' },
      pergunta_da_vaga => { 'caminho' => 'outro_assunto', 'motivo' => 'mandou o currículo' } }
  end

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def vagas = canal.inbox
  # Areas.vincular! é idempotente: chamar de novo devolve o mesmo vínculo.
  def espelho_da_agente = Autonomia::Agents::Areas.vincular!(agent: agente_da_vaga, inbox: vagas).agent_bot
  def conversa_id = { '$valor' => 'conversa.id' }
  def card_id = { '$valor' => 'card.id' }
  def da_caixa_de_vagas = { campo: { '$valor' => 'conversa.caixa_id' }, op: 'igual', valor: vagas.id }
  def recebida = { campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }

  def etiqueta(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: "Pôr a etiqueta #{nome}",
      caminho: { conversation_id: conversa_id }, corpo: { por: [nome] } }
  end

  def fechar(id, motivo)
    { id: id, tipo: 'acao', acao: 'POST crm/cards/:id/close', descricao: 'Fechar o card', caminho: { id: card_id },
      corpo: { result: 'lost', lost_reason: motivo } }
  end

  # Passos 1 a 6. `fecha_o_card`: o fechar do passo 6 (G18), que faz o salvar recusar a receita inteira.
  def receita_da_selecao(fecha_o_card: false)
    { gatilho: { tipo: 'mensagem.criada', filtros: [recebida, da_caixa_de_vagas] }, passos: [
      { id: 'curriculo', tipo: 'extrair', le: %w[mensagens_recentes anexos], campos: [
        { chave: 'nome', descricao: 'o nome completo da candidata, como está no currículo', destino: 'contato.nome' },
        { chave: 'bairro', descricao: 'o bairro onde ela mora', destino: 'contato.atributos.bairro' },
        { chave: 'experiencia', descricao: 'a experiência de trabalho com atendimento, em uma frase', destino: 'contato.atributos.experiencia' },
        { chave: 'curso_de_atendimento', descricao: 'se ela tem curso de atendimento ou de recepção',
          destino: 'contato.atributos.curso_de_atendimento' }
      ] },
      { id: 'card_da_selecao', tipo: 'card', etapa_id: triagem.id },
      decidir_o_perfil(fecha_o_card)
    ] }
  end

  def decidir_o_perfil(fecha_o_card)
    agradece = { id: 'agradece', tipo: 'mensagem',
                 texto: ['Obrigada pelo interesse, ', { '$valor' => 'contato.nome' },
                         '! Desta vez seguimos com outro perfil, mas guardamos seu currículo. Boa sorte!'] }
    { id: 'perfil', tipo: 'decidir', le: %w[mensagens_recentes anexos contato], pergunta: pergunta_do_perfil, caminhos: [
      { nome: 'Atende o perfil', chave: 'atende', descricao: 'cumpre os requisitos da doutora', passos: [
        { id: 'link_da_entrevista', tipo: 'mensagem',
          texto: ['Oi, ', { '$valor' => 'contato.nome' }, '! Gostamos do seu currículo. Escolha o horário da entrevista: ',
                  { '$valor' => 'conversa.link_da_agenda' }] },
        etiqueta('etiqueta_entrevista', 'entrevista')
      ] },
      { nome: 'Talvez', chave: 'talvez', descricao: 'cumpre parte dos requisitos; a doutora decide', passos: [
        { id: 'resumo_para_doutora', tipo: 'resumir', le: %w[mensagens_recentes anexos contato], linhas: 3,
          destino: { avisar: { pessoas: [patricia.id] } } }
      ] },
      { nome: 'Não atende', chave: 'nao_atende', descricao: 'não cumpre os requisitos', passos: [
        agradece, *([fechar('fecha_o_card', 'Não atende o perfil')] if fecha_o_card)
      ] }
    ], nenhum: [] }
  end

  # Passo 7.
  def receita_das_perguntas
    { gatilho: { tipo: 'mensagem.criada', filtros: [recebida, da_caixa_de_vagas] }, passos: [
      { id: 'pergunta', tipo: 'decidir', le: %w[ultima_mensagem], pergunta: pergunta_da_vaga, caminhos: [
        { nome: 'Salário ou horário', chave: 'salario_horario', descricao: 'pergunta sobre o salário ou o horário da vaga',
          passos: [{ id: 'agente_da_vaga', tipo: 'ia_assumir', agente_id: agente_da_vaga.id }] },
        { nome: 'Outro assunto', chave: 'outro_assunto', descricao: 'manda o currículo ou fala de outra coisa', passos: [] }
      ], nenhum: [] }
    ] }
  end

  # Passo 8, como o PR da G32 desenha o gatilho (#2709).
  def receita_do_lembrete
    { gatilho: { tipo: 'card.antes_da_reuniao', antes: { valor: 1, unidade: 'dias' }, pagina_id: entrevistas.id }, passos: [
      { id: 'lembra_o_endereco', tipo: 'mensagem', texto: ['Amanhã é a sua entrevista. Endereço: ', endereco],
        modelo: { nome: 'endereco_entrevista', idioma: 'pt_BR',
                  variaveis: [[{ '$valor' => 'contato.nome' }], [{ '$valor' => 'reuniao.inicio' }], [endereco]] } }
    ] }
  end

  # Passo 9.
  def receita_do_nao_compareceu
    { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: nao_compareceu.id }, passos: [fechar('fecha_nao_compareceu', 'Não compareceu')] }
  end

  def ligada(nome, receita)
    automacao = montar_automacao(patricia, account, nome: nome, receita: receita)
    ligar_automacao(patricia, account, automacao)
    clear_enqueued_jobs
    automacao
  end

  def atributo(chave, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: 'contact_attribute', attribute_display_type: tipo)
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [patricia, recepcao].each { |pessoa| create(:inbox_member, user: pessoa, inbox: vagas) }
    # Convive: a IA de assunto é da caixa, e na de vagas fica desligada.
    account.crm_inbox_settings.create!(inbox: vagas, crm_enabled: true, subject_ai_mode: :off)
    criar_campos_modelo_e_etiqueta
    [triagem, nao_compareceu, entrevistas]
  end

  def criar_campos_modelo_e_etiqueta
    canal.update!(message_templates: [modelo_do_endereco])
    { 'bairro' => 'text', 'experiencia' => 'text', 'curso_de_atendimento' => 'checkbox' }.each { |chave, tipo| atributo(chave, tipo) }
    create(:label, account: account, title: 'entrevista', description: 'Candidata com entrevista')
  end

  def modelo_do_endereco
    { 'name' => 'endereco_entrevista', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, sua entrevista é {{2}}, na {{3}}. Até lá!' }] }
  end

  # A agente de IA da vaga, ligada na caixa de vagas (Fase 2, como no CRM).
  def ligar_a_agente_da_vaga
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    espelho_da_agente
  end

  # O dublê da IA responde ao "decidir" pela pergunta dele (as duas automações perguntam na mesma mensagem) e aos
  # outros passos pelo nome do schema.
  def ia_por_pergunta
    stub_request(:post, FechamentoAutomacao::OPENAI).to_return do |pedido|
      corpo = JSON.parse(pedido.body)
      ia_recebeu << corpo
      nome = corpo.dig('text', 'format', 'name')
      pergunta = [pergunta_do_perfil, pergunta_da_vaga].find { |texto| corpo.to_json.include?(texto.to_json[1..-2]) }
      resposta = nome == 'automacao_decidir' ? respostas.fetch(pergunta) : respostas.fetch(nome)
      payload = { id: "resp_#{ia_recebeu.size}", output_text: resposta.to_json, usage: { input_tokens: 800, output_tokens: 120 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  # O currículo chega como o canal grava a mídia: a mensagem sem texto, com o arquivo anexado, antes de os jobs rodarem.
  def candidata_manda_o_curriculo(hora = '2026-11-10 10:00', arquivo: 'sample.pdf', tipo: :file, conteudo: 'application/pdf')
    as(hora) do
      mensagem = conversa.messages.new(account: account, inbox: vagas, message_type: :incoming, sender: candidata, content: nil)
      anexo = mensagem.attachments.new(account_id: account.id, file_type: tipo)
      anexo.file.attach(io: Rails.root.join('spec/assets', arquivo).open, filename: "curriculo#{File.extname(arquivo)}", content_type: conteudo)
      mensagem.save!
      drenar
    end
  end

  def candidata_escreve_as(hora, texto)
    as(hora) do
      create(:message, conversation: conversa, account: account, inbox: vagas, message_type: :incoming, sender: candidata, content: texto)
      drenar
    end
  end

  def perfil(caminho, motivo) = respostas[pergunta_do_perfil] = { 'caminho' => caminho, 'motivo' => motivo }

  def textos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }
  def card_da_selecao = selecao.cards.sole
  def automacao_id(nome) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: nome).id
  def historico(nome) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome)).order(:id).pluck(:passo, :resultado, :motivo)
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    receptor_whatsapp_cloud
    ia_responde(account, {})
    ia_por_pergunta
    as('2026-11-10 09:00') do
      preparar_conta
      ligar_a_agente_da_vaga
      conversa
      ligada('Seleção – Recepcionista', receita_da_selecao)
      ligada('Perguntas da vaga', receita_das_perguntas)
      ligada('Não compareceu', receita_do_nao_compareceu)
    end
  end

  after { Current.reset }

  it 'passo 1: o currículo em PDF vai inteiro à IA, e nome, bairro, experiência e curso vão para o contato', :aggregate_failures do
    candidata_manda_o_curriculo

    pdf = pedidos_da_ia('automacao_extrair').sole['input'].first['content'].find { |parte| parte['type'] == 'input_file' }
    expect(pdf).to include('filename' => 'curriculo.pdf')
    expect(candidata.reload).to have_attributes(name: 'Júlia Ramos')
    expect(candidata.custom_attributes).to include('bairro' => 'Vila Mariana', 'experiencia' => '2 anos de recepção em consultório',
                                                   'curso_de_atendimento' => true)
    expect(historico('Seleção – Recepcionista').first).to eq(['curriculo', 'ok', nil])
  end

  it 'passo 1: o currículo em foto também vai à IA, como imagem' do
    candidata_manda_o_curriculo(arquivo: 'avatar.png', tipo: :image, conteudo: 'image/png')

    partes = pedidos_da_ia('automacao_extrair').sole['input'].first['content']
    expect(partes.pluck('type')).to include('input_image')
  end

  it 'passo 2: o card nasce no quadro "Seleção – Recepcionista", ligado à conversa da candidata', :aggregate_failures do
    candidata_manda_o_curriculo

    expect(card_da_selecao).to have_attributes(stage_id: triagem.id, contact_id: candidata.id, status: 'open')
    expect(Crm::Cards::ConversationCardFinder.new(account: account).all(conversa)).to include(card_da_selecao)
  end

  it 'passo 3: a IA decide pelo currículo e pelos requisitos que a doutora escreveu', :aggregate_failures do
    perfil('talvez', 'mora longe')
    candidata_manda_o_curriculo

    pedido = pedidos_da_ia('automacao_decidir').find { |corpo| corpo.to_json.include?('Vila Mariana, Saúde ou Ipiranga') }
    expect(pedido['input'].first['content'].pluck('type')).to include('input_file')
    expect(historico('Seleção – Recepcionista').map(&:first)).to include('perfil')
  end

  it 'passo 4: atende o perfil; a conversa ganha a etiqueta "entrevista"' do
    perfil('atende', 'mora na Vila Mariana e tem curso')
    candidata_manda_o_curriculo

    expect(conversa.reload.label_list).to include('entrevista')
  end

  it 'passo 4: atende o perfil; a candidata recebe o link da agenda de entrevistas', :aggregate_failures do
    pending 'G18: o link da agenda de quem entrevista é o do card da seleção, e a conversa da caixa de vagas não tem pessoa'
    perfil('atende', 'mora na Vila Mariana e tem curso')
    candidata_manda_o_curriculo

    expect(historico('Seleção – Recepcionista')).to include(['link_da_entrevista', 'ok', nil])
    expect(textos_enviados).to contain_exactly(a_string_including(Crm::BookingV2::ShortLink.url_for(entrevistas)))
  end

  it 'passo 5: talvez; a doutora recebe no sino o resumo de 3 linhas, e nada sai para a candidata', :aggregate_failures do
    perfil('talvez', 'mora no Ipiranga, mas tem pouca experiência')
    candidata_manda_o_curriculo

    expect(mencoes_para(patricia).count).to eq(1)
    aviso = conversa.messages.where(private: true).where('content LIKE ?', "%mention://user/#{patricia.id}/%").sole
    expect(aviso.content).to include('8 meses de atendimento em loja')
    expect(pedidos_da_ia('automacao_resumir').sole.to_json).to include('em até 3 linhas curtas')
    expect(textos_enviados).to be_empty
  end

  it 'passo 6: não atende; a candidata recebe o agradecimento com o nome dela', :aggregate_failures do
    perfil('nao_atende', 'mora longe e não tem experiência')
    candidata_manda_o_curriculo

    expect(textos_enviados).to eq(['Obrigada pelo interesse, Júlia Ramos! Desta vez seguimos com outro perfil, mas guardamos seu currículo. ' \
                                   'Boa sorte!'])
    expect(conversa.reload.label_list).not_to include('entrevista')
  end

  it 'passo 6: não atende; o card da seleção é fechado' do
    pending 'G18: fechar o card criado no passo 2 é agir no card a partir da conversa'
    perfil('nao_atende', 'mora longe e não tem experiência')
    ligada('Seleção completa', receita_da_selecao(fecha_o_card: true))
    candidata_manda_o_curriculo

    expect(card_da_selecao).to have_attributes(status: 'lost', lost_reason: 'Não atende o perfil')
  end

  it 'passo 7: a candidata pergunta do salário; a conversa passa para a agente de IA da vaga', :aggregate_failures do
    candidata_manda_o_curriculo
    respostas[pergunta_da_vaga] = { 'caminho' => 'salario_horario', 'motivo' => 'pergunta o salário' }

    candidata_escreve_as('2026-11-10 10:30', 'Qual é o salário e o horário?')

    expect(conversa.reload).to have_attributes(ai_assignee: espelho_da_agente, assignee: nil)
    expect(historico('Perguntas da vaga')).to include(['agente_da_vaga', 'ok', nil])
    expect(agente_da_vaga.instruction).to include(texto_da_vaga)
  end

  # O gatilho é "mensagem com currículo": a pergunta depois do currículo não é currículo, e a seleção não roda de novo.
  it 'gatilho: a pergunta depois do currículo não roda a seleção outra vez', :aggregate_failures do
    pending 'G49: o filtro da mensagem não sabe se ela tem anexo'
    perfil('nao_atende', 'mora longe')
    candidata_manda_o_curriculo

    candidata_escreve_as('2026-11-10 10:30', 'Qual é o salário e o horário?')

    expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao_id('Seleção – Recepcionista')).count).to eq(1)
    expect(textos_enviados.size).to eq(1)
  end

  it 'passo 8: 1 dia antes da entrevista, a candidata recebe pelo modelo aprovado o endereço', :aggregate_failures do
    pending 'G32: o gatilho "antes da reunião" ainda não existe nesta base'
    ligada('Lembrete da entrevista', receita_do_lembrete)
    candidata_manda_o_curriculo
    entrevista = fuso.parse('2026-11-13 09:00')
    as('2026-11-10 11:00') do
      Crm::Meetings::InternalCreator.new(account: account, card: card_da_selecao, inbox: nil, scheduled_by: recepcao, params: {
                                           title: 'Entrevista', starts_at: entrevista, ends_at: entrevista + 30.minutes, timezone: fuso.name,
                                           extra_guests: [], location_type: 'whatsapp_video', booking_profile_id: entrevistas.id
                                         }).perform
      drenar
    end

    travel_to(entrevista - 1.day + 5.minutes) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      drenar
    end

    modelo = chamadas_para('graph.facebook.com').last.corpo['template']
    expect(modelo['name']).to eq('endereco_entrevista')
    expect(modelo.dig('components', 0, 'parameters').pluck('text')).to eq(['Júlia Ramos', '13/11/2026 às 09:00', endereco])
  end

  it 'passo 9: a recepção arrasta o card para "Não compareceu"; o card fecha com esse motivo', :aggregate_failures do
    candidata_manda_o_curriculo

    as('2026-11-13 10:00') do
      Crm::Cards::Mover.new(card: card_da_selecao, actor: recepcao, target_stage: nao_compareceu).perform
      drenar
    end

    expect(card_da_selecao.reload).to have_attributes(status: 'lost', lost_reason: 'Não compareceu')
    expect(historico('Não compareceu')).to eq([['fecha_nao_compareceu', 'ok', nil]])
  end
end
