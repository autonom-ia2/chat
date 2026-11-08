require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 7 dos termos de aceite: "Black Friday para os clientes antigos primeiro".
#
# Montado como a dona da loja montaria, pela API da tela, em quatro automações:
# - Pré-Black (passo 1): na quinta antes da Black Friday, às 9h, uma vez só (data única, #2681), a campanha "Pré-Black"
#   para quem tem a etiqueta "ja-comprou" (G14, gatilho da conta da G7).
# - Pré-Black para os outros (passo 2): na sexta, às 8h, a mesma campanha para a lista de clientes da loja menos quem
#   já comprou (público com exclusão, #2681). "Todos os outros" é a etiqueta "clientes" que a loja põe em toda a lista;
#   a campanha da plataforma sempre sai para etiquetas.
# - Respostas (passos 3 a 6): cada mensagem do cliente que responde à "Pré-Black" (filtro "respondeu à campanha",
#   #2681) vai à IA, que decide entre comprar, só dúvida e não quer receber.
#   - Quer comprar: o card nasce no funil Black Friday (G4), a IA extrai peça, cor e tamanho e eles vão para o card da
#     Black Friday do contato (G18, filtrado pelo funil, aberto e mais recente: não o card aberto de outro funil).
#   - Só dúvida: etiqueta "perguntou-na-black" e a conversa passa para a Bia, a agente de IA (G15).
#   - Não quer receber: confirma, põe a etiqueta e tira de todas as campanhas (G14 nao_receber).
# - Últimas horas (passo 7): no domingo, às 18h, uma vez só, a campanha "Últimas horas" para quem perguntou na Black e
#   não comprou (público com exclusão: "perguntou-na-black" menos "comprou-na-black-2026").
# - Compra (passo 8): card ganho no funil Black Friday põe no contato "comprou-na-black-2026" e "ja-comprou".
#
# A campanha sai pela Campanha da tela até o pedido na Graph (receptor de teste, F9.7); a IA é o dublê. Black Friday de
# 2026: sexta, 27/11. Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
RSpec.describe 'Fechamento #2414 · exemplo 7: Black Friday para os clientes antigos primeiro', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') do
      exemplo.run
    end
  end

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Lu Dona') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: dona, name: 'Black Friday') }
  let(:funil) { funil_e_etapa.first }
  let(:interessados) { funil_e_etapa.last }
  let(:bia) { Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true) }
  let(:roteiro) { {} }
  let(:etiquetas) do
    %w[clientes ja-comprou perguntou-na-black comprou-na-black-2026 nao-quer-promocao]
      .index_with { |nome| create(:label, account: account, title: nome, description: "Loja: #{nome}") }
  end

  # Quem a loja tem: Ana e Bruno já compraram; Carla, Duda e Edu são da lista. Cada um com a conversa do WhatsApp.
  let(:clientes) do
    { 'Ana' => ['+5511900000071', %w[clientes ja-comprou]], 'Bruno' => ['+5511900000072', %w[clientes ja-comprou]],
      'Carla' => ['+5511900000073', %w[clientes]], 'Duda' => ['+5511900000074', %w[clientes]], 'Edu' => ['+5511900000075', %w[clientes]] }
      .to_h { |nome, (telefone, marcas)| [nome, cliente(nome, telefone, marcas)] }
  end

  def cliente(nome, telefone, marcas)
    contato = create(:contact, account: account, name: nome, phone_number: telefone)
    contato.update!(label_list: marcas)
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contato, source_id: telefone.delete('+'))
    create(:conversation, account: account, inbox: inbox, contact: contato, contact_inbox: contact_inbox, status: :open)
    contato
  end

  def conversa_de(nome) = Conversation.find_by!(account: account, contact: clientes.fetch(nome))

  def modelo(nome) = { nome: nome, idioma: 'pt_BR', variaveis: [['na sexta']] }

  def campanha(id, titulo, modelo_aprovado, etiquetas_do_publico, sem: [])
    { id: id, tipo: 'campanha', faz: 'disparar', titulo: titulo, caixa_id: inbox.id, modelo: modelo(modelo_aprovado),
      etiquetas: etiquetas_do_publico.map { |nome| etiquetas.fetch(nome).id },
      sem_etiquetas: sem.map { |nome| etiquetas.fetch(nome).id } }
  end

  def uma_vez(data, hora) = { tipo: 'conta.recorrente', frequencia: 'uma_vez', data: data, hora: hora }

  def etiqueta_no_contato(id, *nomes)
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: "Pôr #{nomes.join(' e ')}",
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: nomes } }
  end

  def receitas
    { pre_black: { gatilho: uma_vez('2026-11-26', 9), passos: [campanha('pre_black', 'Pré-Black', 'pre_black', %w[ja-comprou])] },
      pre_black_outros: { gatilho: uma_vez('2026-11-27', 8),
                          passos: [campanha('pre_black', 'Pré-Black', 'pre_black', %w[clientes], sem: %w[ja-comprou])] },
      respostas: receita_das_respostas,
      ultimas_horas: { gatilho: uma_vez('2026-11-29', 18),
                       passos: [campanha('ultimas_horas', 'Últimas horas', 'ultimas_horas', %w[perguntou-na-black],
                                         sem: %w[comprou-na-black-2026])] },
      compra: { gatilho: { tipo: 'card.ganho', funil_id: funil.id },
                passos: [etiqueta_no_contato('comprou', 'comprou-na-black-2026', 'ja-comprou')] } }
  end

  def receita_das_respostas
    { gatilho: { tipo: 'mensagem.criada', filtros: [{ campo: { '$valor' => 'mensagem.campanha' }, op: 'igual', valor: 'Pré-Black' }] },
      passos: [{ id: 'intencao', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que o cliente quer com a Pré-Black?',
                 caminhos: [{ nome: 'Quer comprar', chave: 'comprar', descricao: 'quer comprar uma peça', passos: quer_comprar },
                            { nome: 'Só dúvida', chave: 'duvida', descricao: 'só tem dúvida', passos: so_duvida },
                            { nome: 'Não quer receber', chave: 'nao_quer', descricao: 'não quer mais receber', passos: nao_quer }],
                 nenhum: [] }] }
  end

  def quer_comprar
    pedido = %w[peca cor tamanho].index_with { |chave| { '$valor' => "conversa.atributos.#{chave}" } }
    [{ id: 'card', tipo: 'card', etapa_id: interessados.id },
     { id: 'pedido', tipo: 'extrair', campos: [
       { chave: 'peca', descricao: 'a peça que quer', destino: 'conversa.atributos.peca' },
       { chave: 'cor', descricao: 'a cor', destino: 'conversa.atributos.cor' },
       { chave: 'tamanho', descricao: 'o tamanho', destino: 'conversa.atributos.tamanho' }
     ] },
     { id: 'no_card_da_black', tipo: 'em_outro_registro',
       registro: { de: 'cards_do_contato', funil_id: funil.id, situacao: %w[open], mais_recente: true },
       passos: [{ id: 'grava', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Gravar o pedido no card',
                  caminho: { id: { '$valor' => 'card.id' } }, corpo: { card: { custom_attributes: pedido } } }] }]
  end

  def so_duvida = [etiqueta_no_contato('perguntou', 'perguntou-na-black'), { id: 'bia', tipo: 'ia_assumir', agente_id: bia.id }]

  def nao_quer
    [{ id: 'confirma', tipo: 'mensagem', texto: ['Pronto, você não recebe mais as nossas promoções.'] },
     etiqueta_no_contato('marca', 'nao-quer-promocao'),
     { id: 'sai', tipo: 'campanha', faz: 'nao_receber' }]
  end

  def modelos_aprovados
    %w[pre_black ultimas_horas].map do |nome|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
        'components' => [{ 'type' => 'BODY', 'text' => "Oi! #{nome}: a Black começa {{1}}." }] }
    end
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'whatsapp_campaign')
    create(:inbox_member, user: dona, inbox: inbox)
    canal.update!(message_templates: modelos_aprovados)
    %w[peca cor tamanho].each do |chave|
      %w[conversation_attribute card_attribute].each do |modelo|
        create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                             attribute_model: modelo, attribute_display_type: 'text')
      end
    end
    preparar_bia
  end

  # A Bia atende a caixa do WhatsApp como área de IA (Fase 2 dos Agentes), para receber quem passa.
  def preparar_bia
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    Autonomia::Agents::Areas.vincular!(agent: bia, inbox: inbox)
  end

  # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
  def meta_aprova_os_modelos
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: modelos_aprovados.each_with_index.map { |item, i| item.merge('id' => "900#{i}") } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  # Ligadas uma semana antes: a data única que já passou não salva.
  def ligar_tudo
    travel_to(fuso.parse('2026-11-20 10:00')) do
      receitas.each do |nome, receita|
        ligar_automacao(dona, account, montar_automacao(dona, account, nome: "Black: #{nome}", receita: receita))
      end
      clear_enqueued_jobs
    end
  end

  # A varredura do recorrente no momento, no fuso da conta, e o disparo da campanha que ela monta.
  def chega(momento)
    travel_to(fuso.parse(momento)) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob)
      perform_enqueued_jobs(only: Campaigns::TriggerOneoffCampaignJob)
    end
  end

  def responde(nome, texto, momento)
    travel_to(fuso.parse(momento)) do
      cliente_escreve(conversa_de(nome), texto)
      perform_enqueued_jobs(only: Autonomia::Automacao::EventoDoCardJob)
      rodar_jobs
    end
  end

  # Para quem cada campanha saiu, pelo pedido na Graph.
  def receberam(modelo_aprovado)
    para = chamadas_para('graph.facebook.com').select { |chamada| chamada.corpo.dig('template', 'name') == modelo_aprovado }
    para.map { |chamada| clientes.key(Contact.find_by!(account: account, phone_number: "+#{chamada.corpo['to']}")) }
  end

  def historico(nome) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome)).order(:id).pluck(:passo, :resultado, :motivo)

  def automacao_id(nome) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: "Black: #{nome}").id

  def card_da_black(nome) = account.crm_cards.where(pipeline: funil, contact: clientes.fetch(nome)).sole

  before do
    preparar_conta
    clientes
    receptor_whatsapp_cloud
    meta_aprova_os_modelos
    ia_responde(account, roteiro)
    ligar_tudo
  end

  after { Current.reset }

  it 'passo 1: na quinta, às 9h, a Pré-Black sai só para quem já comprou, uma vez', :aggregate_failures do
    chega('2026-11-26 08:50')
    expect(receberam('pre_black')).to be_empty

    chega('2026-11-26 09:10')
    chega('2026-11-26 15:00')

    expect(receberam('pre_black')).to contain_exactly('Ana', 'Bruno')
    expect(account.campaigns.where(title: 'Pré-Black').count).to eq(1)
  end

  it 'passo 2: na sexta, às 8h, a mesma campanha vai para os outros clientes, sem repetir para quem já comprou', :aggregate_failures do
    chega('2026-11-26 09:10')
    chega('2026-11-27 08:10')

    expect(receberam('pre_black')).to contain_exactly('Ana', 'Bruno', 'Carla', 'Duda', 'Edu')
    expect(account.campaigns.where(title: 'Pré-Black').count).to eq(2)
  end

  context 'with a Pré-Black recebida (passos 3 a 6)' do
    before do
      chega('2026-11-26 09:10')
      chega('2026-11-27 08:10')
    end

    it 'passo 3: só a resposta à Pré-Black vai à IA; a mensagem sem campanha não', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'duvida', 'motivo' => 'perguntou o horário' }

      responde('Carla', 'Até que horas vai a promoção?', '2026-11-27 10:00')

      decisoes = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_decidir' }
      expect(decisoes.size).to eq(1)
      expect(decisoes.sole['input'].to_json).to include('Até que horas vai a promoção?')
      expect(historico(:respostas).first).to eq(['intencao', 'ok', nil])
    end

    it 'passo 4: quer comprar: o card nasce na Black Friday e guarda peça, cor e tamanho; o card de outro funil fica igual',
       :aggregate_failures do
      outro_funil = create_crm_pipeline(account: account, user: dona, name: 'Trocas').first
      troca = account.crm_cards.create!(pipeline: outro_funil, stage: outro_funil.stages.first, title: 'Troca da Duda', currency: 'BRL',
                                        contact: clientes['Duda'], primary_conversation: conversa_de('Duda'))
      roteiro['automacao_decidir'] = { 'caminho' => 'comprar', 'motivo' => 'quer o vestido' }
      roteiro['automacao_extrair'] = { 'peca' => 'vestido', 'cor' => 'preto', 'tamanho' => 'M' }

      responde('Duda', 'Quero o vestido preto, tamanho M!', '2026-11-27 10:00')

      card = card_da_black('Duda')
      expect(card).to have_attributes(stage_id: interessados.id, status: 'open')
      expect(card.custom_attributes).to include('peca' => 'vestido', 'cor' => 'preto', 'tamanho' => 'M')
      expect(troca.reload.custom_attributes).not_to include('peca')
    end

    it 'passo 5: só dúvida: etiqueta "perguntou-na-black" e a conversa passa para a Bia', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'duvida', 'motivo' => 'perguntou do frete' }

      responde('Carla', 'O frete é grátis?', '2026-11-27 10:00')

      expect(clientes['Carla'].reload.label_list).to include('perguntou-na-black')
      expect(conversa_de('Carla').reload.ai_assignee&.name).to eq('Bia')
      expect(historico(:respostas).map(&:first)).to include('perguntou', 'bia')
    end

    it 'passo 6: não quer receber: confirma, põe a etiqueta e sai de todas as campanhas', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'nao_quer', 'motivo' => 'pediu para parar' }

      responde('Edu', 'Não quero mais receber isso', '2026-11-27 10:00')

      edu = clientes['Edu'].reload
      expect(edu.label_list).to include('nao-quer-promocao')
      expect(edu.opted_out?).to be(true)
      confirmacao = chamadas_para('graph.facebook.com').find { |chamada| chamada.corpo.dig('text', 'body') }
      expect(confirmacao.corpo).to include('to' => '5511900000075')
      expect(confirmacao.corpo.dig('text', 'body')).to eq('Pronto, você não recebe mais as nossas promoções.')
    end

    # 🟡 da qualidade (#2686): a próxima campanha recebida fecha a janela da anterior.
    it 'depois das "Últimas horas", a mensagem não conta mais como resposta à Pré-Black' do
      roteiro['automacao_decidir'] = { 'caminho' => 'duvida', 'motivo' => 'perguntou do frete' }
      responde('Carla', 'O frete é grátis?', '2026-11-27 10:00')
      chega('2026-11-29 18:10')
      decisoes_antes = ia_recebeu.size

      responde('Carla', 'Ainda dá tempo?', '2026-11-29 19:00')

      expect(ia_recebeu.size).to eq(decisoes_antes)
    end
  end

  it 'passo 7: no domingo, às 18h, "Últimas horas" vai para quem perguntou na Black e não comprou', :aggregate_failures do
    chega('2026-11-26 09:10')
    chega('2026-11-27 08:10')
    roteiro['automacao_decidir'] = { 'caminho' => 'duvida', 'motivo' => 'perguntou do frete' }
    responde('Carla', 'O frete é grátis?', '2026-11-27 10:00')
    responde('Duda', 'Tem desconto no vestido?', '2026-11-27 10:05')
    Crm::Cards::Closer.new(card: account.crm_cards.create!(pipeline: funil, stage: interessados, title: 'Vestido da Duda',
                                                           currency: 'BRL', contact: clientes['Duda'],
                                                           primary_conversation: conversa_de('Duda')),
                           actor: dona, result: 'won').perform
    travel_to(fuso.parse('2026-11-28 12:00')) do
      perform_enqueued_jobs(only: Autonomia::Automacao::EventoDoCardJob)
      rodar_jobs
    end

    chega('2026-11-29 18:10')

    expect(receberam('ultimas_horas')).to eq(['Carla'])
  end

  it 'passo 8: card ganho na Black Friday põe "comprou-na-black-2026" e "ja-comprou" no contato', :aggregate_failures do
    card = account.crm_cards.create!(pipeline: funil, stage: interessados, title: 'Vestido do Edu', currency: 'BRL',
                                     contact: clientes['Edu'], primary_conversation: conversa_de('Edu'))

    travel_to(fuso.parse('2026-11-27 16:00')) do
      Crm::Cards::Closer.new(card: card, actor: dona, result: 'won').perform
      perform_enqueued_jobs(only: Autonomia::Automacao::EventoDoCardJob)
      rodar_jobs
    end

    expect(clientes['Edu'].reload.label_list).to include('comprou-na-black-2026', 'ja-comprou', 'clientes')
    expect(historico(:compra)).to eq([['comprou', 'ok', nil]])
  end
end
