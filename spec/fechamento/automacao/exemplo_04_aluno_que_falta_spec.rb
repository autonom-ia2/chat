require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 4 dos termos de aceite: "Aluno que começa a faltar".
#
# > "Quando o aluno falta duas aulas no mês ele acaba desistindo. Quero saber antes e tentar segurar ele."
# > — Rogério, coordenador da escola
#
# Começa quando: a recepção arrasta o card do aluno para "Faltou".
#   1. Se o aluno ainda não tem a etiqueta "faltou 1x": põe a etiqueta, manda "Sentimos sua falta! Quer remarcar?" com
#      o link da agenda e, 30 dias depois, tira a etiqueta. Para aqui.
#   2. Se já tinha: troca para a etiqueta "risco de sair" e cria um card no quadro "Retenção".
#   3. A IA escreve uma pergunta carinhosa sobre o motivo das faltas e manda pelo modelo aprovado.
#   4. A resposta vai para a Clara, a agente de IA da escola, que continua a conversa.
#   5. A IA decide o motivo: "horário", "dinheiro", "dificuldade" ou "mudou de cidade".
#   6. Horário: manda o link da agenda com as turmas de outros horários.
#   7. Dinheiro: avisa o Rogério com um resumo e cria retorno para oferecer uma condição.
#   8. Dificuldade: manda o link da agenda do professor para uma aula de reforço.
#   9. Mudou de cidade: oferece a turma online e põe a etiqueta "online".
#  10. Espera 30 dias. Se nesse tempo não entrou de novo em "Faltou", tira as etiquetas de risco e fecha o card de
#      retenção como resolvido.
# Resultado: o Rogério tem uma coluna "Retenção" com os alunos em risco antes de eles cancelarem, e já sabe o motivo de
# cada um. Por que é novo: nada no sistema conta faltas nem cria trabalho de retenção. A automação usa a própria
# etiqueta como contador.
#
# Montado como o Rogério montaria, pela API da tela, numa automação só: o card que entra em "Faltou" (G5). Nome de
# etiqueta na plataforma não tem espaço: "faltou 1x" é `faltou-1x`, "risco de sair" é `risco-de-sair` e "online" é
# `online` (como `cliente-fiel` no exemplo 5). As etiquetas ficam no contato do aluno, que é quem falta: a conversa muda,
# o aluno não. O "se" lê `contato.etiquetas`; o card de retenção nasce pelo passo "card" (G4), ligado à conversa do aluno;
# a pergunta da IA é o "escrever" que só guarda, e a "mensagem" com o modelo aprovado a leva (`ia.pergunta`, G28); a
# Clara entra pelo "ia_assumir" (G15); a resposta do aluno é o "esperar até" `conversa.cliente_respondeu` (G11) antes do
# "decidir". O termo não dá prazo para a resposta, e o esquema exige um: 7 dias. O retorno do passo 7 é do Rogério, que
# avisado decide a condição (G3). A IA é o dublê. Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
#
# A segunda falta com a primeira ainda esperando (G50, #2682): o gatilho escolhe "começa outra vez" (`se_repetir:
# comeca_outra`), e a nova entrada em "Faltou" abre outra execução no mesmo card, ao lado da que espera os 30 dias do
# passo 1. Ela acha `faltou-1x` e vai ao passo 2. O passo 10 é o "esperar até" `card.entrou_de_novo` (o card entrou de
# novo na etapa do gatilho durante a espera), com prazo de 30 dias: a nova entrada o acorda na hora e ele para; vencido
# o prazo, segue pelo `se_vencer`, que tira as etiquetas de risco. A nova falta durante o passo 10 começa outra execução,
# que não vê `faltou-1x` (o passo 2 a trocou) e volta ao passo 1, como o termo diz. Ponta a ponta da peça:
# g50_reentrada_spec.rb.
#
# Os 30 dias do passo 1 são o mesmo "esperar até" `card.entrou_de_novo`, e não um "esperar" fixo: a etiqueta-contador só
# sai se nesse tempo o aluno não faltou de novo. Se faltou, a nova execução achou `faltou-1x` e o passo 2 já a trocou; a
# execução velha acorda e para sem tirar nada. Com o "esperar" fixo, ela acordava no dia 30 e tirava a `faltou-1x` que
# uma falta mais nova tinha acabado de pôr, e a falta seguinte voltava ao passo 1 em vez de ir ao passo 2.
#
# Passos 6 e 8 (G44): "as turmas de outros horários" e "a agenda do professor" são páginas escolhidas na receita
# (`agenda.<id>`); o passo 1 manda o `card.link_da_agenda`, a página de quem cuida do card (a recepção, "Remarcar aula").
# Passo 10, fechar o card de retenção (G49): o card que o passo 2 criou (`criado.retencao`), não o do aluno, que é o alvo.
RSpec.describe 'Fechamento #2414 · exemplo 4: aluno que começa a faltar', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true',
                      AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { exemplo.run }
  end

  def pergunta_escrita = 'Lucas, sentimos sua falta nas últimas aulas. Aconteceu alguma coisa? Queremos ajudar você a continuar.'

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:rogerio) { create(:user, account: account, role: :administrator, name: 'Rogério Coordenador') }
  let(:recepcao) { create(:user, account: account, role: :agent, name: 'Bianca Recepção') }
  let(:aluno) { create(:contact, account: account, name: 'Lucas', phone_number: '+5511900000004') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: escola, contact: aluno, source_id: '5511900000004')
    create(:conversation, account: account, inbox: escola, contact: aluno, contact_inbox: contact_inbox, status: :open)
  end
  let(:alunos_e_em_aula) { create_crm_pipeline(account: account, user: rogerio, name: 'Alunos') }
  let(:faltou) { create_crm_stage(account: account, pipeline: alunos_e_em_aula.first, name: 'Faltou', position: 1) }
  let(:em_risco) do
    funil = account.crm_pipelines.create!(name: 'Retenção', created_by: rogerio, status: :active)
    account.crm_pipeline_stages.create!(pipeline: funil, name: 'Em risco', position: 0)
  end
  # A recepção cuida do card do aluno e atende numa página só: a de remarcar a aula.
  let(:card) do
    account.crm_cards.create!(pipeline: em_aula.pipeline, stage: em_aula, inbox: escola, contact: aluno, primary_conversation: conversa,
                              owner: recepcao, title: 'Lucas - inglês intermediário', currency: 'BRL')
  end
  # As páginas de agendamento: a de remarcar, da recepção; a das turmas de outros horários, do Rogério; a de reforço, do
  # professor.
  let(:paginas) do
    professor = create(:user, account: account, role: :agent, name: 'Marcos Professor')
    { remarcar: create_booking_profile(account: account, host: recepcao, title: 'Remarcar aula'),
      outros_horarios: create_booking_profile(account: account, host: rogerio, title: 'Turmas de outros horários'),
      reforco: create_booking_profile(account: account, host: professor, title: 'Aula de reforço') }
  end
  let(:clara) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Você é a Clara, da escola de idiomas. Converse com carinho com o aluno.')
  end
  let(:roteiro) do
    { 'automacao_escrever' => { 'texto' => pergunta_escrita },
      'automacao_resumir' => { 'resumo' => 'Lucas diz que ficou sem dinheiro para a mensalidade deste mês.' } }
  end

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def em_aula = alunos_e_em_aula.last
  def remarcar = paginas[:remarcar]
  def outros_horarios = paginas[:outros_horarios]
  def reforco = paginas[:reforco]
  def escola = canal.inbox
  def espelho_da_clara = Autonomia::Agents::Areas.vincular!(agent: clara, inbox: escola).agent_bot
  def link_da_agenda = { '$valor' => 'card.link_da_agenda' }
  def agenda(pagina) = { '$valor' => "agenda.#{pagina.id}" }
  def sem_faltou_1x = { campo: { '$valor' => 'contato.etiquetas' }, op: 'nao_contem', valor: 'faltou-1x' }
  def entrou_de_novo = { campo: { '$valor' => 'card.entrou_de_novo' }, op: 'igual', valor: true }

  def etiquetas(id, descricao, por: [], tirar: [])
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: descricao,
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: por, tirar: tirar }.compact_blank }
  end

  def receita
    { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: faltou.id, se_repetir: 'comeca_outra' }, passos: [
      primeira_falta,
      etiquetas('risco', 'Trocar para risco de sair', por: ['risco-de-sair'], tirar: ['faltou-1x']),
      { id: 'retencao', tipo: 'card', etapa_id: em_risco.id },
      { id: 'pergunta', tipo: 'escrever', le: %w[mensagens_recentes contato], destino: 'guardar',
        instrucao: 'Escreva uma pergunta carinhosa ao aluno sobre o motivo das faltas nas aulas.' },
      { id: 'manda_pergunta', tipo: 'mensagem', texto: [{ '$valor' => 'ia.pergunta' }],
        modelo: { nome: 'retencao_motivo', idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }], [{ '$valor' => 'ia.pergunta' }]] } },
      { id: 'clara', tipo: 'ia_assumir', agente_id: clara.id },
      { id: 'resposta', tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
        prazo: { valor: 7, unidade: 'dias' } },
      decidir_o_motivo,
      nao_entrou_de_novo
    ] }
  end

  # Passo 10.
  def nao_entrou_de_novo
    { id: 'nao_entrou_de_novo', tipo: 'esperar_ate', condicao: entrou_de_novo, prazo: { valor: 30, unidade: 'dias' }, se_vencer: [
      etiquetas('tira_risco', 'Tirar as etiquetas de risco', tirar: ['risco-de-sair']),
      fechar_a_retencao
    ] }
  end

  # Passo 1. A etiqueta sai em 30 dias só se o aluno não faltou de novo nesse tempo: se faltou, o passo 2 da nova
  # execução já a trocou, e esta não tira a de uma falta mais nova.
  def primeira_falta
    { id: 'primeira_falta', tipo: 'se', condicao: sem_faltou_1x, entao: [
      etiquetas('faltou_1x', 'Pôr faltou 1x', por: ['faltou-1x']),
      { id: 'sentimos_sua_falta', tipo: 'mensagem', texto: ['Sentimos sua falta! Quer remarcar? ', link_da_agenda] },
      { id: 'trinta_dias', tipo: 'esperar_ate', condicao: entrou_de_novo, prazo: { valor: 30, unidade: 'dias' }, se_vencer: [
        etiquetas('tira_faltou_1x', 'Tirar faltou 1x', tirar: ['faltou-1x'])
      ] },
      { id: 'fim_da_primeira', tipo: 'parar' }
    ] }
  end

  # Passos 5 a 9.
  def decidir_o_motivo
    { id: 'motivo', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'Por que o aluno está faltando às aulas?', caminhos: [
      { nome: 'Horário', chave: 'horario', descricao: 'o horário da turma não serve mais', passos: [
        { id: 'outros_horarios', tipo: 'mensagem', texto: ['Temos turmas em outros horários. Escolha a sua: ', agenda(outros_horarios)] }
      ] },
      { nome: 'Dinheiro', chave: 'dinheiro', descricao: 'está sem dinheiro para a mensalidade', passos: [
        { id: 'resumo_rogerio', tipo: 'resumir', le: %w[mensagens_recentes], destino: { avisar: { pessoas: [rogerio.id] } } },
        { id: 'condicao', tipo: 'retorno', titulo: ['Oferecer uma condição para ', { '$valor' => 'contato.nome' }],
          daqui: { valor: 1, unidade: 'dias' }, para: { quem: 'pessoas', pessoas: [rogerio.id] } }
      ] },
      { nome: 'Dificuldade', chave: 'dificuldade', descricao: 'está com dificuldade de acompanhar as aulas', passos: [
        { id: 'reforco', tipo: 'mensagem', texto: ['Vamos marcar uma aula de reforço com o professor? Escolha o horário: ', agenda(reforco)] }
      ] },
      { nome: 'Mudou de cidade', chave: 'mudou_de_cidade', descricao: 'mudou de cidade', passos: [
        { id: 'turma_online', tipo: 'mensagem', texto: ['Que tal continuar na nossa turma online? Você estuda de onde estiver.'] },
        etiquetas('online', 'Pôr online', por: ['online'])
      ] }
    ], nenhum: [] }
  end

  def fechar_a_retencao
    { id: 'fecha_retencao', tipo: 'acao', acao: 'POST crm/cards/:id/close', descricao: 'Fechar o card de retenção como resolvido',
      caminho: { id: { '$valor' => 'criado.retencao' } }, corpo: { result: 'won' } }
  end

  def modelo_da_pergunta
    { 'name' => 'retencao_motivo', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}! {{2}}' }] }
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [rogerio, recepcao, reforco.default_assignee].each { |pessoa| create(:inbox_member, user: pessoa, inbox: escola) }
    canal.update!(message_templates: [modelo_da_pergunta])
    criar_etiquetas
    [faltou, em_risco, card]
  end

  def criar_etiquetas
    { 'faltou-1x' => 'Faltou uma aula no mês', 'risco-de-sair' => 'Aluno em risco de sair', 'online' => 'Turma online' }.each do |nome, descricao|
      create(:label, account: account, title: nome, description: descricao)
    end
  end

  # A Clara, ligada na caixa da escola (Fase 2, como no CRM).
  def ligar_a_clara
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    espelho_da_clara
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

  def recepcao_move_as(hora, etapa)
    as(hora) do
      Crm::Cards::Mover.new(card: card.reload, actor: recepcao, target_stage: etapa).perform
      drenar
    end
  end

  def aluno_escreve_as(hora, texto)
    as(hora) do
      create(:message, conversation: conversa, account: account, inbox: escola, message_type: :incoming, sender: aluno_do_banco, content: texto)
      drenar
    end
  end

  def varredura_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  # O aluno já faltou uma vez neste mês: a etiqueta-contador está nele, e ninguém falou com a escola há mais de 24 h.
  def segunda_falta(motivo = nil)
    roteiro['automacao_decidir'] = { 'caminho' => motivo, 'motivo' => 'o que o aluno respondeu' } if motivo
    as('2026-11-10 09:00') { aluno_do_banco.update!(label_list: ['faltou-1x']) }
    recepcao_move_as('2026-11-10 19:00', faltou)
  end

  def link(pagina) = Crm::BookingV2::ShortLink.url_for(pagina)
  def whatsapp = chamadas_para('graph.facebook.com')
  def textos_enviados = whatsapp.filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  def modelos_enviados = whatsapp.filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }
  # O contato relido a cada uso: o objeto em memória guarda a lista de etiquetas de quando foi lido, e salvá-lo de novo
  # (a mensagem que chega toca o contato) gravaria a lista velha por cima da que a automação mudou.
  def aluno_do_banco = account.contacts.find(aluno.id)
  def etiquetas_do_aluno = aluno_do_banco.label_list
  def card_de_retencao = em_risco.pipeline.cards.sole
  def automacao_id = Autonomia::Automacao::Definicao.find_by!(account: account, nome: 'Aluno que começa a faltar').id
  def historico = Autonomia::Automacao::Registro.where(automacao_id: automacao_id).order(:id).pluck(:passo, :resultado, :motivo)
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 08:00') do
      preparar_conta
      ligar_a_clara
      conversa
      ligar_automacao(rogerio, account, montar_automacao(rogerio, account, nome: 'Aluno que começa a faltar', receita: receita))
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  context 'with a primeira falta do mês (passo 1)' do
    before do
      aluno_escreve_as('2026-11-10 09:30', 'Hoje não vou conseguir ir à aula.')
      recepcao_move_as('2026-11-10 19:00', faltou)
    end

    it 'passo 1: o aluno ganha a etiqueta faltou-1x e recebe o "Sentimos sua falta" com o link da agenda', :aggregate_failures do
      expect(etiquetas_do_aluno).to eq(['faltou-1x'])
      expect(textos_enviados).to eq(["Sentimos sua falta! Quer remarcar? #{link(remarcar)}"])
      expect(historico.last).to eq(['trinta_dias', 'ok', nil])
    end

    it 'passo 1: para aqui; nada de risco, de card de retenção nem de IA', :aggregate_failures do
      expect(em_risco.pipeline.cards).to be_empty
      expect(ia_recebeu).to be_empty
      expect(historico.map(&:first)).not_to include('risco', 'retencao', 'pergunta')
    end

    it 'passo 1: 30 dias depois, a etiqueta faltou-1x sai e a automação para', :aggregate_failures do
      varredura_as('2026-12-10 19:05')

      expect(etiquetas_do_aluno).to be_empty
      expect(historico.last(2)).to eq([['tira_faltou_1x', 'ok', nil], ['fim_da_primeira', 'ok', nil]])
      expect(em_risco.pipeline.cards).to be_empty
    end

    # O contador da etiqueta: a segunda falta no mês acha `faltou-1x` e vai para o passo 2.
    it 'passo 2: a segunda falta no mês troca a etiqueta para risco-de-sair e cria o card de retenção', :aggregate_failures do
      recepcao_move_as('2026-11-12 10:00', em_aula)
      recepcao_move_as('2026-11-17 19:00', faltou)

      expect(etiquetas_do_aluno).to eq(['risco-de-sair'])
      expect(card_de_retencao).to have_attributes(stage_id: em_risco.id, contact_id: aluno.id, status: 'open')
    end

    # Três faltas com as execuções lado a lado (dias 0, 5 e 10): a 3ª não acha `faltou-1x` (a 2ª a trocou) e a põe de
    # novo. No dia 30 a execução da 1ª não tira essa etiqueta, que é da 3ª; a 4ª falta, no dia 32, vai ao passo 2. O
    # passo 1 roda duas vezes (dias 0 e 10), o passo 2 duas (dias 5 e 32), e nenhuma execução tira a `faltou-1x`.
    it 'passo 1: a etiqueta posta por uma falta mais nova não sai nos 30 dias da 1ª, e a 4ª falta vai ao passo 2',
       :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'horario', 'motivo' => 'o que o aluno respondeu' }
      [%w[2026-11-12 2026-11-15], %w[2026-11-17 2026-11-20]].each do |aula, falta|
        recepcao_move_as("#{aula} 10:00", em_aula)
        recepcao_move_as("#{falta} 19:00", faltou)
      end
      expect(etiquetas_do_aluno).to contain_exactly('risco-de-sair', 'faltou-1x')

      varredura_as('2026-12-10 19:05')
      expect(etiquetas_do_aluno).to include('faltou-1x')

      recepcao_move_as('2026-12-11 10:00', em_aula)
      recepcao_move_as('2026-12-12 19:00', faltou)

      expect(etiquetas_do_aluno).to include('risco-de-sair')
      expect(etiquetas_do_aluno).not_to include('faltou-1x')
      expect(historico.count { |passo, resultado, _| passo == 'faltou_1x' && resultado == 'ok' }).to eq(2)
      expect(historico.count { |passo, resultado, _| passo == 'risco' && resultado == 'ok' }).to eq(2)
      expect(historico).not_to include(['tira_faltou_1x', 'ok', nil])
    end
  end

  it 'passo 2: o aluno que já tinha faltou-1x troca para risco-de-sair e ganha o card no quadro "Retenção"', :aggregate_failures do
    segunda_falta

    expect(etiquetas_do_aluno).to eq(['risco-de-sair'])
    expect(card_de_retencao).to have_attributes(stage_id: em_risco.id, contact_id: aluno.id, status: 'open')
    expect(Crm::Cards::ConversationCardFinder.new(account: account).all(conversa)).to include(card_de_retencao)
    expect(card.reload).to have_attributes(stage_id: faltou.id, status: 'open')
    expect(textos_enviados).to be_empty
  end

  it 'passo 3: a IA escreve a pergunta carinhosa, e ela sai pelo modelo aprovado', :aggregate_failures do
    segunda_falta

    expect(pedidos_da_ia('automacao_escrever').sole.to_json).to include('motivo das faltas')
    expect(modelos_enviados).to eq(%w[retencao_motivo])
    expect(whatsapp.sole.corpo.dig('template', 'components', 0, 'parameters').pluck('text')).to eq(['Lucas', pergunta_escrita])
    expect(historico).to include(['pergunta', 'ok', nil], ['manda_pergunta', 'ok', nil])
  end

  it 'passo 4: a conversa passa para a Clara, e a automação espera a resposta do aluno', :aggregate_failures do
    segunda_falta

    expect(conversa.reload).to have_attributes(ai_assignee: espelho_da_clara, assignee: nil)
    expect(historico.last(2)).to eq([['clara', 'ok', nil], ['resposta', 'ok', nil]])
  end

  it 'passo 5: a resposta do aluno fica com a Clara, e a IA decide o motivo lendo o que ele respondeu', :aggregate_failures do
    segunda_falta('horario')

    aluno_escreve_as('2026-11-11 10:00', 'Mudei de emprego e não consigo mais chegar às 19h.')

    expect(conversa.reload.ai_assignee).to eq(espelho_da_clara)
    expect(pedidos_da_ia('automacao_decidir').sole.to_json).to include('não consigo mais chegar às 19h')
    expect(historico.map(&:first)).to include('motivo')
  end

  it 'passo 6: horário; o aluno recebe o link da agenda das turmas de outros horários', :aggregate_failures do
    segunda_falta('horario')

    aluno_escreve_as('2026-11-11 10:00', 'Mudei de emprego e não consigo mais chegar às 19h.')

    expect(textos_enviados.last).to eq("Temos turmas em outros horários. Escolha a sua: #{link(outros_horarios)}")
  end

  it 'passo 7: dinheiro; o Rogério recebe no sino o resumo, e o retorno para oferecer uma condição é dele', :aggregate_failures do
    segunda_falta('dinheiro')

    aluno_escreve_as('2026-11-11 10:00', 'Fiquei sem dinheiro para a mensalidade este mês.')

    expect(mencoes_para(rogerio).count).to eq(1)
    aviso = conversa.messages.where(private: true).where('content LIKE ?', "%mention://user/#{rogerio.id}/%").sole
    expect(aviso.content).to include('sem dinheiro para a mensalidade')
    expect(Crm::FollowUp.where(card_id: card.id).sole).to have_attributes(
      title: 'Oferecer uma condição para Lucas', recipient_mode: 'users', recipient_user_ids: [rogerio.id], due_at: fuso.parse('2026-11-12 10:00')
    )
  end

  it 'passo 8: dificuldade; o aluno recebe o link da agenda do professor para a aula de reforço', :aggregate_failures do
    segunda_falta('dificuldade')

    aluno_escreve_as('2026-11-11 10:00', 'Estou com dificuldade de acompanhar a turma.')

    expect(textos_enviados.last).to eq("Vamos marcar uma aula de reforço com o professor? Escolha o horário: #{link(reforco)}")
  end

  it 'passo 9: mudou de cidade; o aluno recebe a oferta da turma online e ganha a etiqueta online', :aggregate_failures do
    segunda_falta('mudou_de_cidade')

    aluno_escreve_as('2026-11-11 10:00', 'Me mudei para Curitiba.')

    expect(textos_enviados.last).to eq('Que tal continuar na nossa turma online? Você estuda de onde estiver.')
    expect(etiquetas_do_aluno).to contain_exactly('risco-de-sair', 'online')
  end

  it 'passo 10: 30 dias sem faltar de novo, a etiqueta risco-de-sair sai', :aggregate_failures do
    segunda_falta('mudou_de_cidade')
    aluno_escreve_as('2026-11-11 10:00', 'Me mudei para Curitiba.')

    varredura_as('2026-12-11 10:05')

    expect(etiquetas_do_aluno).to eq(['online'])
    expect(historico.last(2)).to eq([['tira_risco', 'ok', nil], ['fecha_retencao', 'ok', nil]])
  end

  # "Se nesse tempo não entrou de novo em Faltou": a nova falta acorda o passo 10 na hora, e ele para sem tirar nada.
  it 'passo 10: faltou de novo nos 30 dias; a etiqueta de risco fica e o card de retenção continua aberto', :aggregate_failures do
    segunda_falta('horario')
    aluno_escreve_as('2026-11-11 10:00', 'Mudei de emprego e não consigo mais chegar às 19h.')
    recepcao_move_as('2026-11-16 10:00', em_aula)
    recepcao_move_as('2026-11-24 19:00', faltou)

    varredura_as('2026-12-11 10:05')

    expect(etiquetas_do_aluno).to include('risco-de-sair')
    expect(card_de_retencao.reload.status).to eq('open')
  end

  it 'passo 10: 30 dias sem faltar de novo, o card de retenção fecha como resolvido, e o do aluno continua aberto',
     :aggregate_failures do
    segunda_falta('mudou_de_cidade')
    aluno_escreve_as('2026-11-11 10:00', 'Me mudei para Curitiba.')

    varredura_as('2026-12-11 10:05')

    expect(card_de_retencao.reload.status).to eq('won')
    expect(card.reload.status).to eq('open')
  end
end
