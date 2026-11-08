require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 6 dos termos de aceite: "Aniversário que vira horário marcado".
#
# > "No aniversário da cliente eu quero mandar um parabéns com um mimo e ela já marcar o horário. Se ela vier, quero uma
# > foto pro Instagram." — Jéssica, dona do salão
#
# Começa quando: é o dia do aniversário gravado no contato.
#   1. A IA escreve um parabéns no jeito do salão, citando o último serviço que ela fez.
#   2. Manda pelo modelo aprovado "Aniversário", com o presente: hidratação grátis este mês, e o link da agenda.
#   3. Põe a etiqueta "aniversariante do mês" e cria um card no quadro "Aniversário".
#   4. A IA decide a resposta: "vai marcar", "agradeceu" ou "não pode este mês".
#   5. Não pode este mês: estende o presente para o mês seguinte e grava a nova data no card.
#   6. Marcou: avisa a profissional e grava no card "hidratação de presente".
#   7. Não marcou em 10 dias: lembra uma vez, pelo modelo aprovado.
#   8. Atendida: no dia seguinte pede, pelo modelo aprovado, uma foto do resultado e autorização para postar.
#   9. A IA extrai se ela autorizou. Autorizou: põe a etiqueta "pode postar" e avisa a Jéssica.
#  10. Fim do mês sem marcar (ou fim do mês seguinte, se ela adiou): fecha o card e coloca a cliente na campanha "Saudade".
# Resultado: todo mês as aniversariantes recebem o parabéns no dia certo. A Jéssica vê quem marcou, quem adiou para o mês
# seguinte e quais clientes já autorizaram foto para o Instagram.
#
# Montado como a Jéssica montaria, pela API da tela, em quatro automações:
# - a do aniversário (passos 1 a 7): o gatilho de data do contato (`contato.data`, G6) no campo da data de nascimento,
#   com `repete: todo_ano`, às 9h. O alvo é o contato. O último serviço é o campo do contato que o salão preenche
#   (`ultimo_servico`), e a IA o lê com `le: contato`; o parabéns é o "escrever" que só guarda, e a "mensagem" com o
#   modelo aprovado o leva (`ia.parabens`, G28). A etiqueta vai no contato; o card nasce pelo passo "card" (G4), ligado
#   ao contato. A conversa é a do WhatsApp do salão, que a receita escolhe no gatilho (`conversa_nova`, G33, #2680): a
#   mensagem a abre, e a espera e a IA leem nela. A resposta é o "esperar até" `conversa.cliente_respondeu` (G11) antes
#   do "decidir"; o termo não dá prazo
#   e o esquema exige um: 7 dias. "Não pode" estende a data do presente no card (`$data` hoje + 1 mês, no fim do mês,
#   #2705) e para. "Marcou" é a reunião marcada (`contato.tem_reuniao_marcada`), esperada 10 dias: vencido, o lembrete
#   pelo modelo aprovado (passo 7);
# - a do card novo no quadro "Aniversário" (`card.criado`, G5): grava no card a data do presente, o fim deste mês;
# - a da data do presente (`card.data` no `presente_ate`, G6), passo 10: fecha o card (G25) e põe a cliente na campanha
#   "Saudade", que é pôr a etiqueta do público dela (G14);
# - a da cliente atendida (passos 8 e 9): começa quando a reunião da página do salão é registrada como atendida
#   ("Aconteceu", `outcome: held`); no dia seguinte, o pedido da foto pelo modelo aprovado, a resposta (7 dias), o
#   extrair da autorização para o contato e o "se".
# Nome de etiqueta na plataforma não tem espaço: "aniversariante do mês" é `aniversariante-do-mes`, "pode postar" é
# `pode-postar` e o público da campanha "Saudade" é `saudade` (como `cliente-fiel` no exemplo 5). A cliente tem uma
# conversa antiga no WhatsApp oficial, com a janela de 24 h fechada. A IA é o dublê. Desenho e lacunas:
# docs/automacao/F9-fechamento-20-exemplos.md.
#
# O que ainda não monta, cada um no exemplo do passo, escrito como o termo pede:
# - Passo 2 (G44): o link da agenda é do responsável do card ou da pessoa da conversa; no contato não há nenhum dos
#   dois, e uma página escolhida (a do salão) não existe. O salvar recusa `card.link_da_agenda` no gatilho do contato, e o
#   modelo de 4 variáveis não salva com 3. Por isso a receita dos outros passos vem sem o passo 2.
# - Passos 5 e 6, "grava no card" (G18): o card é o do passo 3, outro registro; o salvar recusa `card.id` no gatilho do
#   contato. Por isso a receita dos outros passos vem sem eles.
# - Passos 8 e 9 (G56, "reunião atendida gera evento", lacuna nova): o "Aconteceu" grava `outcome: held` na reunião, mas
#   nenhum evento sai dele, e não há gatilho de reunião atendida; o salvar recusa `card.reuniao_atendida`. A etapa
#   "Atendida" no lugar da reunião adaptaria o termo.
# - Passos 6 e 7 (G32): a reunião marcada como condição do "esperar até" (`contato.tem_reuniao_marcada`) não existe
#   nesta base, nem o aviso a quem atende a reunião (`para.da_reuniao`: o esquema recusa; mesmo com a G32 ele só vale
#   nos gatilhos de reunião, e o "avisar" sem conversa pula, G22).
# Cada pendente monta só o passo dele por cima da receita dos outros passos, para falhar pelo motivo do passo.
# - Passo 10, "sem marcar" (G32): sem o valor da reunião marcada, a automação da data fecha o card de quem marcou também;
#   a receita dos outros passos vem sem o "se". "Fim do mês seguinte, se adiou" espera o passo 5 (G18).
RSpec.describe 'Fechamento #2414 · exemplo 6: aniversário que vira horário marcado', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  def parabens_escrito = 'Feliz aniversário, Bia! Que este ano seja lindo como ficou a sua escova progressiva.'
  def presente = 'hidratação grátis este mês'

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:jessica) { create(:user, account: account, role: :administrator, name: 'Jéssica Dona') }
  let(:profissional) { create(:user, account: account, role: :agent, name: 'Carla Cabeleireira') }
  let(:cliente) do
    create(:contact, account: account, name: 'Bia', phone_number: '+5511900000060',
                     custom_attributes: { 'data_de_nascimento' => '1994-11-12', 'ultimo_servico' => 'escova progressiva' })
  end
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: salao, contact: cliente, source_id: '5511900000060')
    create(:conversation, account: account, inbox: salao, contact: cliente, contact_inbox: contact_inbox, status: :resolved)
  end
  let(:aniversario) { account.crm_pipelines.create!(name: 'Aniversário', created_by: jessica, status: :active) }
  let(:presente_oferecido) { account.crm_pipeline_stages.create!(pipeline: aniversario, name: 'Presente oferecido', position: 0) }
  let(:agenda) do
    create_booking_profile(account: account, host: profissional, pipeline: aniversario, stage: presente_oferecido, title: 'Hidratação')
  end
  let(:roteiro) do
    { 'automacao_escrever' => { 'texto' => parabens_escrito },
      'automacao_decidir' => { 'caminho' => 'vai_marcar', 'motivo' => 'disse que vai marcar' },
      'automacao_extrair' => { 'pode_postar' => true } }
  end
  # O exemplo monta a receita do aniversário com o passo que o salvar recusa (2, 4, 5, 6 e 7); sem ele, a dos outros passos.
  let(:receita_no_exemplo) { false }
  # A data do presente com o "sem marcar" (G32). Sem ele, a dos outros passos.
  let(:sem_marcar) { false }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def salao = canal.inbox
  def nome = { '$valor' => 'contato.nome' }
  def contato_id = { '$valor' => 'contato.id' }
  def card_id = { '$valor' => 'card.id' }
  def modelo(nome_do_modelo, *variaveis) = { nome: nome_do_modelo, idioma: 'pt_BR', variaveis: [[nome], *variaveis] }
  def reuniao_marcada = { campo: { '$valor' => 'contato.tem_reuniao_marcada' }, op: 'igual', valor: true }

  def etiqueta(id, nome_da_etiqueta)
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: "Pôr a etiqueta #{nome_da_etiqueta}",
      caminho: { contact_id: contato_id }, corpo: { por: [nome_da_etiqueta] } }
  end

  def no_card(id, descricao, atributos)
    { id: id, tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: descricao, caminho: { id: card_id },
      corpo: { card: { custom_attributes: atributos } } }
  end

  def resposta_da_cliente(id)
    { id: id, tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
      prazo: { valor: 7, unidade: 'dias' } }
  end

  # Passos 1 a 7, no aniversário gravado no contato. `extras`: os passos que o salvar recusa (:parabens, :resposta,
  # :estende, :marcou); sem eles, a receita dos outros passos.
  def gatilho_do_aniversario
    { tipo: 'contato.data', campo: 'data_de_nascimento', dias: 0, quando: 'antes', repete: 'todo_ano', hora: 9,
      conversa_nova: { caixa_id: salao.id } }
  end

  def receita_do_aniversario(extras = [])
    { gatilho: gatilho_do_aniversario, passos: [
      { id: 'parabens', tipo: 'escrever', le: %w[contato], destino: 'guardar',
        instrucao: 'Escreva um parabéns curto pelo aniversário da cliente, no jeito carinhoso do salão, citando o último serviço que ela fez aqui.' },
      *([manda_o_parabens] if extras.include?(:parabens)),
      etiqueta('aniversariante', 'aniversariante-do-mes'),
      { id: 'card_do_aniversario', tipo: 'card', etapa_id: presente_oferecido.id },
      *([resposta_da_cliente('resposta')] if extras.include?(:resposta)),
      decidir_a_resposta(extras),
      *(marcou if extras.include?(:marcou))
    ] }
  end

  # Passo 2.
  def manda_o_parabens
    link = { '$valor' => 'card.link_da_agenda' }
    { id: 'manda_parabens', tipo: 'mensagem', texto: [{ '$valor' => 'ia.parabens' }, " De presente: #{presente}. Marque seu horário: ", link],
      modelo: modelo('aniversario', [{ '$valor' => 'ia.parabens' }], [presente], [link]) }
  end

  # Passos 4 e 5.
  def decidir_a_resposta(extras)
    estende = no_card('estende', 'Estender o presente até o fim do mês que vem', presente_ate: {
                        '$data' => { de: 'hoje', mais: { valor: 1, unidade: 'meses' }, fim_do: 'mes' }
                      })
    { id: 'resposta_da_cliente', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que a cliente respondeu ao parabéns?', caminhos: [
      { nome: 'Vai marcar', chave: 'vai_marcar', descricao: 'vai marcar o horário da hidratação', passos: [] },
      { nome: 'Agradeceu', chave: 'agradeceu', descricao: 'só agradeceu o parabéns', passos: [] },
      { nome: 'Não pode este mês', chave: 'nao_pode', descricao: 'não pode vir este mês', passos: [
        *([estende] if extras.include?(:estende)), { id: 'adiou', tipo: 'parar' }
      ] }
    ], nenhum: [] }
  end

  # Passos 6 e 7.
  def marcou
    [{ id: 'marcou', tipo: 'esperar_ate', condicao: reuniao_marcada, prazo: { valor: 10, unidade: 'dias' }, se_vencer: [
      { id: 'lembrete', tipo: 'mensagem', texto: ['Seu presente de aniversário ainda está esperando você!'], modelo: modelo('aniversario_lembrete') }
    ] },
     { id: 'se_marcou', tipo: 'se', condicao: reuniao_marcada, entao: [
       { id: 'avisa_profissional', tipo: 'avisar', texto: [nome, ' marcou a hidratação de presente de aniversário.'], para: { da_reuniao: true } },
       no_card('hidratacao', 'Gravar a hidratação de presente', presente: 'hidratação de presente')
     ] }]
  end

  # A data do presente, no card novo do quadro "Aniversário": o fim deste mês.
  def receita_do_card_novo
    { gatilho: { tipo: 'card.criado', funil_id: aniversario.id }, passos: [
      no_card('presente_do_mes', 'Gravar o presente até o fim do mês', presente_ate: { '$data' => { de: 'hoje', fim_do: 'mes' } })
    ] }
  end

  # Passo 10.
  def receita_do_fim_do_presente
    fecha_e_saudade = [
      { id: 'fecha', tipo: 'acao', acao: 'POST crm/cards/:id/close', descricao: 'Fechar o card', caminho: { id: card_id },
        corpo: { result: 'lost', lost_reason: 'Não marcou o presente de aniversário' } },
      etiqueta('saudade', 'saudade')
    ]
    sem_reuniao = { campo: { '$valor' => 'card.tem_reuniao_marcada' }, op: 'diferente', valor: true }
    passos = sem_marcar ? [{ id: 'sem_marcar', tipo: 'se', condicao: sem_reuniao, entao: fecha_e_saudade }] : fecha_e_saudade
    { gatilho: { tipo: 'card.data', campo: 'presente_ate', dias: 0, quando: 'antes', hora: 9 }, passos: passos }
  end

  # Passos 8 e 9.
  def receita_da_atendida
    autorizou = { campo: { '$valor' => 'contato.atributos.pode_postar' }, op: 'igual', valor: true }
    { gatilho: { tipo: 'card.reuniao_atendida', pagina_id: agenda.id, conversa_nova: { caixa_id: salao.id } }, passos: [
      { id: 'dia_seguinte', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
      { id: 'pede_a_foto', tipo: 'mensagem', texto: ['Como ficou? Manda uma foto do resultado? Podemos postar no Instagram?'],
        modelo: modelo('aniversario_foto') },
      resposta_da_cliente('resposta_da_foto'),
      { id: 'autorizou', tipo: 'extrair', le: %w[mensagens_recentes anexos], campos: [
        { chave: 'pode_postar', descricao: 'se a cliente autorizou o salão a postar a foto no Instagram', destino: 'contato.atributos.pode_postar' }
      ] },
      { id: 'se_autorizou', tipo: 'se', condicao: autorizou, entao: [
        etiqueta('pode_postar', 'pode-postar'),
        { id: 'avisa_jessica', tipo: 'avisar', texto: [nome, ' autorizou postar a foto no Instagram.'], para: { pessoas: [jessica.id] } }
      ] }
    ] }
  end

  def modelos_aprovados
    { 'aniversario' => 'Parabéns, {{1}}! {{2}} De presente: {{3}}. Marque seu horário: {{4}}',
      'aniversario_lembrete' => 'Oi {{1}}, seu presente de aniversário ainda está esperando você!',
      'aniversario_foto' => 'Oi {{1}}, como ficou? Manda uma foto do resultado? Podemos postar no Instagram?' }.map do |nome_do_modelo, corpo|
      { 'name' => nome_do_modelo, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => corpo }] }
    end
  end

  def atributo(chave, modelo_do_atributo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo_do_atributo, attribute_display_type: tipo)
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [jessica, profissional].each { |pessoa| create(:inbox_member, user: pessoa, inbox: salao) }
    canal.update!(message_templates: modelos_aprovados)
    criar_campos_e_etiquetas
    [presente_oferecido, agenda]
  end

  def criar_campos_e_etiquetas
    { 'data_de_nascimento' => 'date', 'ultimo_servico' => 'text', 'pode_postar' => 'checkbox' }.each do |chave, tipo|
      atributo(chave, 'contact_attribute', tipo)
    end
    { 'presente_ate' => 'date', 'presente' => 'text' }.each { |chave, tipo| atributo(chave, 'card_attribute', tipo) }
    { 'aniversariante-do-mes' => 'Aniversariante do mês', 'pode-postar' => 'Autorizou foto no Instagram',
      'saudade' => 'Público da campanha Saudade' }.each do |titulo, descricao|
      create(:label, account: account, title: titulo, description: descricao)
    end
  end

  # A cliente esteve no salão em setembro: a conversa existe, com a janela de 24 h fechada.
  def conversa_antiga
    as('2026-09-05 15:00') do
      create(:message, conversation: conversa, account: account, inbox: salao, message_type: :incoming, sender: cliente,
                       content: 'Amei a escova, obrigada!')
    end
  end

  def ligada(nome_da_automacao, receita)
    automacao = montar_automacao(jessica, account, nome: nome_da_automacao, receita: receita)
    ligar_automacao(jessica, account, automacao)
    clear_enqueued_jobs
    automacao
  end

  def ligar_tudo
    as('2026-11-01 10:00') do
      ligada('Aniversário', receita_do_aniversario) unless receita_no_exemplo
      ligada('Aniversário: presente do mês', receita_do_card_novo)
      ligada('Aniversário: fim do presente', receita_do_fim_do_presente) unless sem_marcar
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

  # A varredura dos gatilhos de tempo, e os jobs que ela abre.
  def chega_o_dia(hora)
    as(hora) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      drenar
    end
  end

  def varredura_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def aniversario_dela = chega_o_dia('2026-11-12 09:30')

  def cliente_escreve_as(hora, texto)
    as(hora) do
      create(:message, conversation: conversa, account: account, inbox: salao, message_type: :incoming, sender: cliente_do_banco, content: texto)
      drenar
    end
  end

  def resposta(caminho, motivo) = roteiro['automacao_decidir'] = { 'caminho' => caminho, 'motivo' => motivo }

  # A cliente marca pela página de agendamento do salão.
  def cliente_marca_as(hora)
    inicio = fuso.parse('2026-11-18 14:00')
    as(hora) do
      Crm::Meetings::InternalCreator.new(account: account, card: card_do_aniversario, inbox: nil, scheduled_by: profissional, params: {
                                           title: 'Hidratação de presente', starts_at: inicio, ends_at: inicio + 1.hour, timezone: fuso.name,
                                           extra_guests: [], location_type: 'in_person', booking_profile_id: agenda.id
                                         }).perform
      drenar
    end
  end

  # A profissional registra o "Aconteceu" da reunião (outcome held), depois do fim dela.
  def reuniao_atendida_as(hora)
    as(hora) do
      reuniao = account.crm_meetings.where(card_id: card_do_aniversario.id).order(:id).last
      Crm::Meetings::RecordOutcomeService.new(meeting: reuniao, outcome: 'held', actor: profissional).perform
      drenar
    end
  end

  # Passos 8 e 9: a automação da cliente atendida, que o salvar ainda recusa (G56).
  def atendida_e_dia_seguinte
    as('2026-11-01 10:00') { ligada('Aniversário: cliente atendida', receita_da_atendida) }
    cliente_marca_as('2026-11-10 10:00')
    reuniao_atendida_as('2026-11-18 15:30')
    varredura_as('2026-11-19 15:35')
  end

  def whatsapp = chamadas_para('graph.facebook.com')
  def modelos_enviados = whatsapp.filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }
  # O contato relido a cada uso: o objeto em memória guarda a lista de etiquetas de quando foi lido.
  def cliente_do_banco = account.contacts.find(cliente.id)
  def etiquetas_da_cliente = cliente_do_banco.label_list
  def card_do_aniversario = aniversario.cards.sole
  def automacao_id(nome_da_automacao) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: nome_da_automacao).id

  def historico(nome_da_automacao)
    Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome_da_automacao)).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-01 09:00') { preparar_conta }
    conversa_antiga
    ligar_tudo
  end

  after { Current.reset }

  it 'gatilho: no dia do aniversário gravado no contato, a automação roda nela; na véspera, não', :aggregate_failures do
    chega_o_dia('2026-11-11 09:30')
    expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao_id('Aniversário'))).to be_empty

    aniversario_dela

    execucao = Autonomia::Automacao::Execucao.where(automacao_id: automacao_id('Aniversário')).sole
    expect(execucao).to have_attributes(alvo_type: 'Contact', alvo_id: cliente.id)
  end

  it 'passo 1: a IA escreve o parabéns no jeito do salão, citando o último serviço que ela fez', :aggregate_failures do
    aniversario_dela

    expect(pedidos_da_ia('automacao_escrever').sole.to_json).to include('escova progressiva', 'último serviço')
    expect(historico('Aniversário').first).to eq(['parabens', 'ok', nil])
  end

  context 'with o passo que o salvar recusa na receita do aniversário (passos 2, 4, 5, 6 e 7)' do
    let(:receita_no_exemplo) { true }

    # A receita dos outros passos com os passos `extras`, cada pendente com os do passo dele.
    def ligar_com(*extras) = as('2026-11-01 10:00') { ligada('Aniversário', receita_do_aniversario(extras)) }

    it 'passo 2: manda pelo modelo aprovado "Aniversário" o parabéns, o presente e o link da agenda', :aggregate_failures do
      pending 'G44: o contato não tem link da agenda; o salvar recusa card.link_da_agenda no gatilho do contato'
      ligar_com(:parabens)
      aniversario_dela

      expect(modelos_enviados).to eq(%w[aniversario])
      parametros = whatsapp.sole.corpo.dig('template', 'components', 0, 'parameters').pluck('text')
      expect(parametros).to eq(['Bia', parabens_escrito, presente, Crm::BookingV2::ShortLink.url_for(agenda)])
    end

    it 'passo 4: a IA decide a resposta da cliente lendo o que ela escreveu', :aggregate_failures do
      ligar_com(:resposta)
      aniversario_dela
      expect(historico('Aniversário').last).to eq(['resposta', 'ok', nil])

      cliente_escreve_as('2026-11-12 11:00', 'Que amor, obrigada! Vou marcar sim.')

      expect(pedidos_da_ia('automacao_decidir').sole.to_json).to include('Vou marcar sim')
      expect(historico('Aniversário').map(&:first)).to include('resposta_da_cliente')
    end

    it 'passo 5: não pode este mês; o presente vai até o fim do mês seguinte, gravado no card', :aggregate_failures do
      pending 'G18: o card do passo 3 é outro registro; o salvar recusa card.id no gatilho do contato'
      resposta('nao_pode', 'viaja este mês')
      ligar_com(:estende)
      aniversario_dela

      cliente_escreve_as('2026-11-12 11:00', 'Obrigada! Este mês estou viajando, não consigo ir.')

      expect(card_do_aniversario.reload.custom_attributes).to include('presente_ate' => '2026-12-31')
      expect(historico('Aniversário').last(2)).to eq([['estende', 'ok', nil], ['adiou', 'ok', nil]])
    end

    it 'passo 6: marcou; a profissional é avisada e o card grava "hidratação de presente"', :aggregate_failures do
      pending 'G32: a reunião marcada não é condição do "esperar até" nesta base (contato.tem_reuniao_marcada)'
      ligar_com(:marcou)
      aniversario_dela
      cliente_escreve_as('2026-11-12 11:00', 'Que amor, obrigada! Vou marcar sim.')

      cliente_marca_as('2026-11-13 10:00')

      expect(mencoes_para(profissional).count).to eq(1)
      expect(card_do_aniversario.reload.custom_attributes).to include('presente' => 'hidratação de presente')
    end

    it 'passo 7: não marcou em 10 dias; lembra uma vez, pelo modelo aprovado', :aggregate_failures do
      pending 'G32: a reunião marcada não é condição do "esperar até" nesta base (contato.tem_reuniao_marcada)'
      ligar_com(:marcou)
      aniversario_dela
      cliente_escreve_as('2026-11-12 11:00', 'Que amor, obrigada!')

      varredura_as('2026-11-22 11:05')
      varredura_as('2026-11-25 11:05')

      expect(modelos_enviados.count('aniversario_lembrete')).to eq(1)
    end

    it 'passo 10: adiou; o card fecha no fim do mês seguinte, não no deste mês', :aggregate_failures do
      pending 'G18: estender o presente (passo 5) é gravar no card a partir do contato'
      resposta('nao_pode', 'viaja este mês')
      ligar_com(:estende)
      aniversario_dela
      cliente_escreve_as('2026-11-12 11:00', 'Obrigada! Este mês estou viajando, não consigo ir.')

      chega_o_dia('2026-11-30 09:30')
      expect(card_do_aniversario.reload.status).to eq('open')

      chega_o_dia('2026-12-31 09:30')
      expect(card_do_aniversario.reload.status).to eq('lost')
      expect(etiquetas_da_cliente).to include('saudade')
    end
  end

  context 'with o card do aniversário (passo 3)' do
    before { aniversario_dela }

    it 'passo 3: a cliente ganha a etiqueta aniversariante-do-mes' do
      expect(etiquetas_da_cliente).to eq(['aniversariante-do-mes'])
    end

    it 'passo 3: o card nasce no quadro "Aniversário", ligado à cliente', :aggregate_failures do
      expect(card_do_aniversario).to have_attributes(stage_id: presente_oferecido.id, contact_id: cliente.id, status: 'open')
      expect(historico('Aniversário')).to include(['aniversariante', 'ok', nil], ['card_do_aniversario', 'ok', nil])
    end

    it 'passo 10: o card novo guarda o presente até o fim do mês' do
      expect(card_do_aniversario.custom_attributes).to include('presente_ate' => '2026-11-30')
    end

    it 'passo 10: fim do mês sem marcar; o card fecha e a cliente entra na campanha "Saudade"', :aggregate_failures do
      chega_o_dia('2026-11-29 09:30')
      expect(card_do_aniversario.reload.status).to eq('open')

      chega_o_dia('2026-11-30 09:30')

      expect(card_do_aniversario.reload).to have_attributes(status: 'lost', lost_reason: 'Não marcou o presente de aniversário')
      expect(etiquetas_da_cliente).to contain_exactly('aniversariante-do-mes', 'saudade')
      expect(historico('Aniversário: fim do presente')).to eq([['fecha', 'ok', nil], ['saudade', 'ok', nil]])
    end

    it 'passos 8 e 9: atendida; no dia seguinte, pede pelo modelo aprovado a foto e a autorização para postar', :aggregate_failures do
      pending 'G56: a reunião atendida não gera evento nem gatilho'
      atendida_e_dia_seguinte

      expect(modelos_enviados).to eq(%w[aniversario_foto])
      expect(whatsapp.sole.corpo.dig('template', 'components', 0, 'parameters').pluck('text')).to eq(['Bia'])
    end

    it 'passo 9: autorizou; a cliente ganha a etiqueta pode-postar e a Jéssica é avisada', :aggregate_failures do
      pending 'G56: a reunião atendida não gera evento nem gatilho'
      atendida_e_dia_seguinte

      cliente_escreve_as('2026-11-19 18:00', 'Ficou lindo! Pode postar sim.')

      expect(cliente_do_banco.custom_attributes).to include('pode_postar' => true)
      expect(etiquetas_da_cliente).to include('pode-postar')
      expect(mencoes_para(jessica).count).to eq(1)
    end
  end

  context 'with o "sem marcar" no fim do presente (passo 10)' do
    let(:sem_marcar) { true }

    it 'passo 10: fim do mês com horário marcado; o card fica aberto e a cliente fora da campanha', :aggregate_failures do
      pending 'G32: a reunião marcada não é valor da receita nesta base (card.tem_reuniao_marcada)'
      as('2026-11-01 10:00') { ligada('Aniversário: fim do presente', receita_do_fim_do_presente) }
      aniversario_dela
      cliente_marca_as('2026-11-13 10:00')

      chega_o_dia('2026-11-30 09:30')

      expect(card_do_aniversario.reload.status).to eq('open')
      expect(etiquetas_da_cliente).not_to include('saudade')
    end
  end
end
