require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 7 dos termos de aceite: "Black Friday para os clientes antigos primeiro".
#
# > "Quero que quem já comprou comigo veja a promoção um dia antes de todo mundo. Quem só perguntar, a moça do robô
# > responde. Quem pedir pra não receber, nunca mais recebe." — Vanessa, dona da loja
#
# Começa quando: quinta-feira antes da Black Friday (27/11/2026), às 9h.
#   1. Monta a campanha de WhatsApp para quem tem a etiqueta "já comprou" e manda o modelo aprovado "Pré-Black".
#   2. Na sexta às 8h, monta a mesma campanha para todos os outros contatos.
#   3. Cada resposta à campanha: a IA decide "quer comprar", "só dúvida" ou "não quer receber".
#   4. Quer comprar: a IA extrai peça, cor e tamanho e grava no card, para a vendedora já saber o que separar.
#   5. Só dúvida: põe a etiqueta "perguntou na Black" e passa a conversa para a Bia, agente de IA.
#   6. Não quer receber: confirma "Pronto, você não recebe mais promoções", põe a etiqueta "não enviar campanha" e tira a
#      pessoa de todas as campanhas.
#   7. Domingo às 18h: quem tem a etiqueta "perguntou na Black" e não comprou recebe a campanha "Últimas horas".
#   8. Card ganho: põe a etiqueta "comprou na Black 2026" e "já comprou".
#
# Montado como a Vanessa montaria, pela API da tela, em quatro automações (FechamentoAutomacao::Exemplo07):
# - a Pré-Black (passos 1 e 2): o gatilho que roda uma vez, na quinta às 9h (G39); a campanha da etiqueta, uma espera de
#   23 horas (sexta às 8h) e a mesma campanha, com o mesmo modelo e o mesmo nome, para todos menos quem tem "já comprou"
#   (G37). A espera na mesma automação diz "a mesma campanha, depois": as duas saem da mesma receita;
# - a resposta (passos 3 a 6): a mensagem recebida com o filtro "respondeu à campanha Pré-Black" (G38, o destinatário
#   real que o disparo gravou). O passo 4 grava peça, cor e tamanho direto nos campos do card da conversa (G70, decisão
#   20 do Rodrigo, "IA só anota campos": a única escrita no card da conversa), depois de uma espera curta que dá à IA de
#   assunto o tempo de abrir o card;
# - as Últimas horas (passo 7): o gatilho de data única no domingo às 18h, para "perguntou na Black" menos "comprou na
#   Black 2026" (G37);
# - o card ganho (passo 8, G5).
#
# A campanha sai pelo caminho de produção (Campaigns::TriggerOneoffCampaignJob, OneoffCampaignService do EE), que grava
# o destinatário e para no receptor da Graph (F9.7). O cliente responde pelo webhook real da Cloud. A IA é o dublê; o
# extrair responde pelo texto que o pedido levou a ela.
# O card de quem pede uma peça nasce da IA de assunto ("Convive"), ligada na caixa em Automática, DEPOIS da resposta do
# cliente: o Jev e o modelo maior são dublês, sem custo, que respondem o que o roteiro de cada resposta diz (pedido novo
# no funil de vendas ou sem assunto). O resto do caminho (a decisão, o card, o vínculo com a conversa) é o de produção.
# As etiquetas se escrevem como a plataforma aceita (minúsculas, sem espaço): `já_comprou`, `perguntou_na_black`,
# `não_enviar_campanha`, `comprou_na_black_2026`.
RSpec.describe 'Fechamento #2414 · exemplo 7: Black Friday para os clientes antigos primeiro', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  def ex = FechamentoAutomacao::Exemplo07

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:vanessa) { create(:user, account: account, role: :administrator, name: 'Vanessa Dona') }
  let(:vendas) { create_crm_pipeline(account: account, user: vanessa, name: 'Vendas') }
  let(:bia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Você é a Bia, da loja. Responda preço, tamanho e entrega.')
  end
  let(:roteiro) { {} }
  let(:clientes) do
    { ana: ['Ana', '5511900000701', [ex::JA_COMPROU]], elisa: ['Elisa', '5511900000702', [ex::JA_COMPROU]],
      carla: ['Carla', '5511900000703', []], hugo: ['Hugo', '5511900000704', []], duda: ['Duda', '5511900000705', []],
      gil: ['Gil', '5511900000706', []] }
  end

  def cliente(chave) = account.contacts.find_by!(phone_number: "+#{clientes.fetch(chave)[1]}")

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  # A varredura do motor na hora: o gatilho de data, a espera vencida e o disparo da campanha, um job por vez.
  def varrer_as(hora)
    as(hora) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
      perform_enqueued_jobs(only: Campaigns::TriggerOneoffCampaignJob)
    end
  end

  # `pedido`: a IA de assunto vê um pedido novo no funil de vendas (abre o card); sem ele, "sem assunto".
  def responde_as(hora, chave, texto, decide:, pedido: false)
    roteiro['automacao_decidir'] = { 'caminho' => decide, 'motivo' => 'o que o cliente respondeu' }
    roteiro['assunto'] = pedido ? "novo_#{vendas.first.id}" : Crm::Subjects::Question::SEM_ASSUNTO
    nome, telefone, = clientes.fetch(chave)
    as(hora) { cliente_escreve_pela_cloud(canal, remetente: telefone, nome: nome, texto: texto) }
  end

  # A IA de assunto decide depois da espera dela (Crm::Subjects::DEBOUNCE): o job agendado pela mensagem roda na hora.
  def assunto_decide_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Crm::Subjects::IdentifyJob)
      drenar
    end
  end

  # A resposta com tudo o que vem depois dela: a IA de assunto aos 20 s e a espera do passo 4 vencida.
  def responde_e_segue(hora, chave, texto, decide:, pedido: false)
    responde_as(hora, chave, texto, decide: decide, pedido: pedido)
    inicio = fuso.parse(hora)
    assunto_decide_as((inicio + 20.seconds).iso8601)
    varrer_as((inicio + 65.seconds).iso8601)
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

  def card_de(chave) = account.crm_cards.find_by!(contact_id: cliente(chave).id)
  def conversa_de(chave) = account.conversations.find_by!(contact_id: cliente(chave).id)
  def campanha(titulo) = account.campaigns.where(title: titulo).order(:id)
  def enviados(modelo) = chamadas_para('graph.facebook.com').select { |chamada| chamada.corpo.dig('template', 'name') == modelo }
  def para(modelo) = enviados(modelo).map { |chamada| chamada.corpo['to'] }
  def textos(chave) = conversa_de(chave).messages.outgoing.where(private: false).pluck(:content)
  def historico(nome) = historico_de('id' => Autonomia::Automacao::Definicao.find_by!(account: account, nome: nome).id)

  # O extrair responde pelo que leu: "Quero o vestido azul no M, separa pra mim!" → peça, cor e tamanho, palavra a palavra
  # do texto que o pedido levou à IA; sem o dado, nulo.
  def peca_do_texto(mensagem)
    palavras = mensagem.to_s.split('] ', 2).last.delete(',!').split
    peca = palavras.index('o')
    tamanho = palavras.index('no')
    { 'peca' => peca && palavras[peca + 1], 'cor' => peca && palavras[peca + 2], 'tamanho' => tamanho && palavras[tamanho + 1] }
  end

  def parametro(chamada) = chamada.corpo.dig('template', 'components', 0, 'parameters', 0, 'text')

  # O Jev da IA de assunto (dublê): escolhe o que o roteiro da resposta diz, com certeza alta.
  def jev_responde
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do
      body = { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
               answers: { decisao: { type: 'choice', choice: roteiro.fetch('assunto'), confidence: 0.95 } } }
      { status: 200, body: body.to_json }
    end
  end

  # O modelo maior confirma o pedido novo e dá o nome do assunto pela peça que leu na conversa ("vestido", "calça").
  def revisao_do_assunto(corpo)
    conversa = JSON.parse(corpo.dig('input', 0, 'content', 0, 'text'))['conversation']
    peca = peca_do_texto(Array(conversa['messages']).last)['peca']
    { 'resposta' => roteiro.fetch('assunto'), 'titulo' => "Black: #{peca}", 'seguro' => true, 'motivo' => 'pedido de uma peça' }
  end

  def roteiro_da_ia(nome, corpo)
    case nome
    when 'automacao_extrair' then peca_do_texto(mensagens_lidas(corpo).last)
    when 'assunto_revisao' then revisao_do_assunto(corpo)
    else roteiro.fetch(nome)
    end
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'whatsapp_campaign')
    canal.update!(message_templates: ex.modelos)
    ex::ETIQUETAS.each { |nome, descricao| create(:label, account: account, title: nome, description: descricao) }
    # Os campos da peça existem só no card, onde a vendedora lê e o extrair grava (G70).
    ex::PECA.each do |chave|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                           attribute_model: 'card_attribute', attribute_display_type: 'text')
    end
    ligar_a_ia_de_assunto
  end

  # O funil de vendas na caixa da loja, com a IA de assunto em Automática: ela abre o card do pedido novo. O card não
  # nasce sozinho com a conversa (auto_create_card desligado): só a IA de assunto o abre.
  def ligar_a_ia_de_assunto
    account.crm_pipeline_inboxes.create!(pipeline: vendas.first, inbox: inbox, default_stage: vendas.last, auto_create_card: false,
                                         created_by: vanessa)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :auto)
  end

  def cadastrar_clientes
    clientes.each_value do |nome, telefone, etiquetas|
      create(:contact, account: account, name: nome, phone_number: "+#{telefone}").update!(label_list: etiquetas)
    end
    cliente(:gil).opt_out!(source: 'manual')
  end

  # A Bia, ligada na caixa da loja (Fase 2, como no CRM).
  def ligar_a_bia
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    Autonomia::Agents::Areas.vincular!(agent: bia, inbox: inbox).agent_bot
  end

  def ligar_as_automacoes
    { 'Pré-Black' => ex.pre_black(account, inbox), 'Resposta à Pré-Black' => ex.resposta(bia),
      'Últimas horas' => ex.ultimas_horas(account, inbox), 'Card ganho na Black' => ex.card_ganho(vendas.first) }.each do |nome, receita|
      ligar_automacao(vanessa, account, montar_automacao(vanessa, account, nome: nome, receita: receita))
    end
    clear_enqueued_jobs
  end

  before do
    receptor_whatsapp_cloud
    # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: ex.modelos.each_with_index.map { |modelo, i| modelo.merge('id' => "70#{i}") } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    ia_responde(account, method(:roteiro_da_ia))
    jev_responde
    as('2026-11-20 10:00') do
      preparar_conta
      cadastrar_clientes
      ligar_a_bia
      ligar_as_automacoes
    end
  end

  after { Current.reset }

  # Quinta às 9h; a Ana quer comprar e a Elisa pergunta.
  def quinta
    varrer_as('2026-11-26 09:05')
    responde_e_segue('2026-11-26 10:00', :ana, 'Quero o vestido azul no M, separa pra mim!', decide: 'quer_comprar', pedido: true)
    responde_e_segue('2026-11-26 10:30', :elisa, 'Até que horas a loja abre na sexta?', decide: 'so_duvida')
  end

  # Sexta às 8h; a Duda pede para sair, a Carla e o Hugo perguntam.
  def sexta
    varrer_as('2026-11-27 08:05')
    responde_e_segue('2026-11-27 09:00', :duda, 'Não quero receber essas promoções', decide: 'nao_quer_receber')
    responde_e_segue('2026-11-27 09:30', :carla, 'Tem a calça preta no G?', decide: 'so_duvida', pedido: true)
    responde_e_segue('2026-11-27 10:00', :hugo, 'Entregam em Campinas?', decide: 'so_duvida')
  end

  # Sábado: a Elisa, que perguntou na quinta, pede para sair; a Carla compra (card ganho).
  def sabado
    responde_e_segue('2026-11-28 11:00', :elisa, 'Pensei melhor, não me manda mais promoção', decide: 'nao_quer_receber')
    as('2026-11-28 15:00') do
      Crm::Cards::Closer.new(card: card_de(:carla), actor: vanessa, result: 'won').perform
      drenar
    end
  end

  it 'passo 1: na quinta às 9h a Pré-Black sai só para quem já comprou, e antes da hora nada sai', :aggregate_failures do
    varrer_as('2026-11-26 08:50')
    expect(account.campaigns).to be_empty

    varrer_as('2026-11-26 09:05')

    expect(campanha('Pré-Black').sole).to have_attributes(campaign_status: 'completed', sender: vanessa)
    expect(para('pre_black')).to contain_exactly('+5511900000701', '+5511900000702')
    expect(enviados('pre_black').first.corpo.dig('template', 'components', 0, 'parameters', 0, 'text')).to eq('amanhã')
  end

  it 'passo 2: na sexta às 8h a mesma campanha vai para todos os outros, menos quem pediu para não receber', :aggregate_failures do
    varrer_as('2026-11-26 09:05')
    varrer_as('2026-11-27 07:55')
    expect(campanha('Pré-Black').count).to eq(1)

    varrer_as('2026-11-27 08:05')

    sexta_feira = campanha('Pré-Black').last
    expect(campanha('Pré-Black').count).to eq(2)
    expect(sexta_feira.template_params['name']).to eq('pre_black')
    expect(para('pre_black')).to contain_exactly('+5511900000701', '+5511900000702', '+5511900000703', '+5511900000704',
                                                 '+5511900000705')
    expect(sexta_feira.campaign_recipients.find_by!(contact: cliente(:gil)).status).to eq('skipped')
    # A da sexta sai com o texto fixo da sexta: "A Black começa hoje".
    da_quinta = %w[+5511900000701 +5511900000702]
    sexta_enviados = enviados('pre_black').reject { |chamada| da_quinta.include?(chamada.corpo['to']) }
    expect(sexta_enviados.map { |chamada| parametro(chamada) }.uniq).to eq(['hoje'])
    expect(historico('Pré-Black')).to eq([['ja_compraram', 'ok', nil], ['ate_sexta_8h', 'ok', nil], ['todos_os_outros', 'ok', nil]])
  end

  it 'passos 3 e 4: a Ana quer comprar; o card nasce da IA de assunto depois da resposta e o extrair grava nele',
     :aggregate_failures do
    varrer_as('2026-11-26 09:05')
    responde_as('2026-11-26 10:00', :ana, 'Quero o vestido azul no M, separa pra mim!', decide: 'quer_comprar', pedido: true)

    # Na resposta, a Ana ainda não tem card: a automação decidiu e espera; a IA de assunto ainda não decidiu.
    expect(account.crm_cards.where(contact_id: cliente(:ana).id)).to be_empty
    expect(historico('Resposta à Pré-Black').map(&:first)).to eq(%w[o_que_quer espera_o_card])

    assunto_decide_as('2026-11-26 10:00:20')

    card = card_de(:ana)
    expect(card.created_at).to be > fuso.parse('2026-11-26 10:00')
    expect(card).to have_attributes(pipeline_id: vendas.first.id, title: 'Black: vestido')
    decisao = Crm::SubjectDecision.find_by!(conversation: conversa_de(:ana))
    expect(decisao).to have_attributes(action: 'create', state: 'applied', card_id: card.id)
    expect(card.custom_attributes.keys & ex::PECA).to be_empty

    varrer_as('2026-11-26 10:01:05')

    # O que o card guarda é o que o dublê tirou do texto que o pedido levou à IA, não um valor do teste.
    extrair = ia_recebeu.find { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_extrair' }
    expect(mensagens_lidas(extrair).last).to end_with('Quero o vestido azul no M, separa pra mim!')
    expect(card.reload.custom_attributes).to include('peca' => 'vestido', 'cor' => 'azul', 'tamanho' => 'M')
    # Direto no card (G70): a conversa não guarda a peça, e nenhuma ação copia para o card.
    expect(conversa_de(:ana).custom_attributes.keys & ex::PECA).to be_empty
    gravou = Autonomia::Automacao::Registro.where(passo: 'peca_cor_tamanho').sole
    expect(gravou.dados['campos']).to include('gravados' => ex::PECA, 'ausentes' => [])
    expect(historico('Resposta à Pré-Black')).to eq(
      [['o_que_quer', 'ok', nil], ['espera_o_card', 'ok', nil], ['peca_cor_tamanho', 'ok', nil]]
    )
    expect(textos(:ana)).to be_empty
  end

  it 'passo 4 só na Ana: a Elisa pergunta, nenhum card nasce para ela, e o card da Carla nasce sem a peça', :aggregate_failures do
    quinta
    sexta

    expect(account.crm_cards.where(contact_id: [cliente(:elisa).id, cliente(:hugo).id, cliente(:duda).id])).to be_empty
    expect(card_de(:carla).custom_attributes.keys & ex::PECA).to be_empty
    expect(historico('Resposta à Pré-Black').count { |passo, _| passo == 'peca_cor_tamanho' }).to eq(1)
    decidir = ia_recebeu.find { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_decidir' }
    expect(decidir.to_json).to include('Quero o vestido azul no M')
  end

  it 'passo 5: a Elisa só tem dúvida; ganha a etiqueta e a conversa passa para a Bia', :aggregate_failures do
    quinta

    expect(cliente(:elisa).label_list).to contain_exactly(ex::JA_COMPROU, ex::PERGUNTOU)
    expect(conversa_de(:elisa).reload.ai_assignee).to eq(Autonomia::Agents::Areas.vincular!(agent: bia, inbox: inbox).agent_bot)
    expect(cliente(:ana).label_list).not_to include(ex::PERGUNTOU)
  end

  it 'passo 6: a Duda pede para sair; recebe a confirmação, ganha a etiqueta e não recebe mais campanha', :aggregate_failures do
    quinta
    sexta

    expect(textos(:duda)).to eq(['Pronto, você não recebe mais promoções'])
    expect(cliente(:duda).label_list).to include(ex::NAO_ENVIAR)
    expect(cliente(:duda)).to be_opted_out

    # "Tira a pessoa de todas as campanhas": a campanha seguinte, para todos os contatos, pula a Duda.
    seguinte = campanha_para_todos('2026-11-27 12:00')
    expect(seguinte.campaign_recipients.find_by!(contact: cliente(:duda)).status).to eq('skipped')
    expect(para('ultimas_horas')).not_to include('+5511900000705')
    expect(para('ultimas_horas')).to include('+5511900000703')
  end

  # Uma campanha da tela para todos os contatos, disparada na hora.
  def campanha_para_todos(hora)
    as(hora) do
      campanha = account.campaigns.create!(
        title: 'Black: todos', inbox: inbox, sender: vanessa, scheduled_at: Time.current, message: 'Últimas horas da Black! Vem.',
        template_params: { 'name' => 'ultimas_horas', 'language' => 'pt_BR', 'category' => 'MARKETING',
                           'processed_params' => { 'body' => { '1' => 'Vem.' } } },
        audience: Autonomia::Automacao::CampanhaSemEtiquetas.todos
      )
      Campaigns::TriggerOneoffCampaignJob.perform_now(campanha)
      campanha
    end
  end

  it 'mensagem que não responde à Pré-Black não abre a automação da resposta', :aggregate_failures do
    quinta
    as('2026-11-26 11:00') { cliente_escreve_pela_cloud(canal, remetente: '5511900000799', nome: 'Ivo', texto: 'Oi, quero comprar') }

    da_conversa_de = ->(nome) { Autonomia::Automacao::Execucao.where(alvo: account.conversations.joins(:contact).where(contacts: { name: nome })) }
    expect(account.conversations.joins(:contact).where(contacts: { name: 'Ivo' })).to exist
    expect(da_conversa_de.call('Ivo')).to be_empty
    # Controle: a mesma consulta acha a execução da Elisa, que respondeu à Pré-Black.
    expect(da_conversa_de.call('Elisa')).to exist
  end

  it 'passo 8: o card da Carla ganho põe "comprou na Black 2026" e "já comprou"' do
    quinta
    sexta
    sabado

    expect(cliente(:carla).label_list).to contain_exactly(ex::PERGUNTOU, ex::COMPROU_NA_BLACK, ex::JA_COMPROU)
  end

  it 'passo 7: domingo às 18h "Últimas horas" vai só a quem perguntou, não comprou e não pediu para sair', :aggregate_failures do
    quinta
    sexta
    sabado
    varrer_as('2026-11-29 17:55')
    expect(campanha('Últimas horas')).to be_empty

    varrer_as('2026-11-29 18:05')

    ultimas = campanha('Últimas horas').sole
    expect(para('ultimas_horas')).to eq(['+5511900000704'])
    expect(enviados('ultimas_horas').map { |chamada| parametro(chamada) }).to eq(['Corre que acaba hoje.'])
    # A Elisa perguntou e depois pediu para sair (passo 6): fica de fora pela recusa, como em toda campanha.
    expect(ultimas.campaign_recipients.find_by!(contact: cliente(:elisa)).status).to eq('skipped')
    expect(ultimas.campaign_recipients.where(contact: cliente(:carla))).to be_empty
    expect(textos(:elisa)).to eq(['Pronto, você não recebe mais promoções'])
  end
end
