require 'rails_helper'

# Fechamento do épico #2414, G31: "a cada resposta da Ana, a IA decide" (exemplo 2, passo 6). A dona monta e liga pela
# API da tela; o card do lead nasce pelo mesmo Creator do formulário, a mensagem abre a conversa pela caixa escolhida
# (G33), e o resto chega pelo despacho da plataforma, um job por vez. A IA é o dublê no endereço da OpenAI.
#
# Os passos 3 e 6 rodam como o termo diz: espera a resposta por até 2 horas; a cada resposta, a IA decide, e "ainda
# conversando" volta a esperar a próxima. O prazo do "decidir de novo" (2 horas, o número do passo 3) é um exemplo: o
# termo não diz quanto esperar nem o que fazer quando vence (pergunta ao Rodrigo no PR); vencido, segue para o passo
# depois do decidir, que no exemplo 2 não há: a execução acaba.
# Fora daqui: o passo 5 (passar a conversa à Sofia) é a G15, provada em passo_de_ia_assumir_spec.rb; aqui a Sofia é uma
# mensagem de saída de um robô. O link da agenda (passo 7) é a G12; no lugar dele, um aviso marca que o caminho rodou.
# O exemplo 2 inteiro nasce quando G29, G30 e G32 fecharem. As bordas (rajada, prazo, caixa que quem ligou não vê, nova
# tentativa) estão em spec/services/autonomia/automacao/decidir_de_novo_spec.rb.
RSpec.describe 'Fechamento #2414 · G31: decidir a cada resposta', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:whatsapp) { create_crm_whatsapp_api_inbox(account: account, members: [dona]) }
  let(:funil) { create_crm_pipeline(account: account, user: dona).first }
  let(:ana) { account.contacts.create!(name: 'Ana', phone_number: '+5511900000031') }
  # O que o dublê da IA escolhe, uma escolha por ida, na ordem.
  let(:escolhas) { [] }

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    roteiro = Object.new
    fila = escolhas
    roteiro.define_singleton_method(:fetch) { |_schema| { 'caminho' => fila.shift, 'motivo' => 'Pela conversa.' } }
    ia_responde(account, roteiro)
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job por vez, como no Sidekiq, com o job do evento do card no meio.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def chega_mensagem(conversa, **atributos)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, **atributos)
    drenar
  end

  def lead_chega
    Crm::Cards::Creator.new(account: account, user: nil,
                            params: { pipeline_id: funil.id, stage_id: funil.stages.first.id, contact_id: ana.id,
                                      source: Crm::MetaAds::LeadForms::Importer::SOURCE, title: 'Ana' }).perform
    drenar
  end

  def caminho(nome, chave, descricao, passos = [])
    { nome: nome, chave: chave, descricao: descricao, passos: passos }
  end

  def receita(de_novo: { caminhos: ['ainda_conversando'], prazo: { valor: 2, unidade: 'horas' } })
    oi = { id: 'oi', tipo: 'mensagem',
           texto: ['Oi, ', { '$valor' => 'contato.nome' }, '! Vi que você se interessou pelo apartamento do Jardim. Posso te ajudar?'] }
    espera = { id: 'espera', tipo: 'esperar_ate', prazo: { valor: 2, unidade: 'horas' },
               condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true } }
    visita = { id: 'visita', tipo: 'avisar', para: { pessoas: [dona.id] }, texto: ['A Ana quer visitar'] }
    decide = { id: 'decide', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que a Ana quer?', de_novo: de_novo,
               caminhos: [caminho('Quer visitar', 'quer_visitar', 'ela quer marcar uma visita', [visita]),
                          caminho('Quer outro imóvel', 'quer_outro_imovel', 'ela quer ver outro apartamento'),
                          caminho('Só curiosidade', 'so_curiosidade', 'ela só está curiosa'),
                          caminho('Ainda conversando', 'ainda_conversando', 'ela ainda está tirando dúvidas')] }
    { gatilho: { tipo: 'card.criado', funil_id: funil.id, conversa_nova: { caixa_id: whatsapp.id } }, passos: [oi, espera, decide] }
  end

  def execucao = Autonomia::Automacao::Execucao.sole

  def decisoes = Autonomia::Automacao::Registro.where(passo: 'decide').order(:id).map { |item| [item.dados['ramo'], item.dados.key?('nota_id')] }

  it 'a cada resposta da Ana a IA decide; "ainda conversando" espera a próxima, e "quer visitar" segue', :aggregate_failures do
    automacao = montar_automacao(dona, account, nome: 'Lead do anúncio', receita: receita)
    ligar_automacao(dona, account, automacao)

    # Passos 2 e 3: a mensagem sai e a espera de 2 horas começa.
    lead_chega
    conversa = account.crm_cards.find_by!(contact: ana).primary_conversation
    expect(historico_de(automacao)).to eq([['oi', 'ok', nil], ['espera', 'ok', nil]])

    # Passo 6, 1ª resposta: a IA decide "ainda conversando", e a execução espera a próxima, sem nota e sem caminho.
    escolhas << 'ainda_conversando'
    travel(20.minutes) { chega_mensagem(conversa, message_type: :incoming, sender: ana, content: 'Qual o valor do condomínio?') }
    prazo = execucao.due_at
    expect([execucao.estado, execucao.cursor]).to eq(%w[esperando decide])
    expect(prazo).to be_within(1.minute).of(20.minutes.from_now + 2.hours)
    expect(historico_de(automacao).last).to eq(['decide', 'ok', nil])
    expect(conversa.messages.where(private: true)).to be_empty

    # A Sofia responde: acorda, mas volta a esperar com o mesmo prazo, sem outra ida à IA.
    robo = create(:agent_bot, account: account, name: 'Sofia')
    travel(25.minutes) { chega_mensagem(conversa, message_type: :outgoing, sender: robo, content: 'O condomínio é R$ 600,00.') }
    expect([execucao.reload.estado, execucao.due_at, ia_recebeu.size]).to eq(['esperando', prazo, 1])

    # 2ª resposta: a IA decide de novo, "quer visitar", e o caminho roda; a nota do motivo fica só nesta volta.
    escolhas << 'quer_visitar'
    travel(40.minutes) { chega_mensagem(conversa, message_type: :incoming, sender: ana, content: 'Quero visitar sábado') }
    expect(execucao.reload.estado).to eq('concluida')
    expect(decisoes).to eq([['ainda_conversando', false], ['quer_visitar', true]])
    expect(historico_de(automacao).last(2)).to eq([['decide', 'ok', nil], ['visita', 'ok', nil]])
    expect(ia_recebeu.size).to eq(2)
    expect(ia_recebeu.last.to_json).to include('Quero visitar sábado')
  end

  it 'o salvar recusa o caminho que decide de novo e tem passos', :aggregate_failures do
    errada = receita(de_novo: { caminhos: ['quer_visitar'], prazo: { valor: 2, unidade: 'horas' } })
    post api_automacoes(account), params: { nome: 'Lead', receita: errada }, headers: dona.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Quer visitar')
  end
end
