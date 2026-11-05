require 'rails_helper'

# Ensaiar (#2498): o que a automação faria em cada conversa, sem fazer nada. Só as conversas que quem pede enxerga; o
# "se" segue o que vale agora; o "esperar até" que ainda não vale e o "decidir" mostram todos os caminhos; tipo fora do
# mapa só ganha a frase.
RSpec.describe Autonomia::Automacao::Ensaio, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let!(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contato, status: :resolved) }
  let(:resolvida) { { 'campo' => { '$valor' => 'conversa.status' }, 'op' => 'igual', 'valor' => 'resolved' } }
  let(:aberta) { resolvida.merge('valor' => 'open') }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  def receita(*passos, gatilho: { 'tipo' => 'conversa.resolvida' })
    { 'gatilho' => gatilho, 'passos' => passos }
  end

  def ensaio(receita, usuario: admin, conversa_id: nil)
    described_class.new(receita: receita, conta: account, usuario: usuario, conversa_id: conversa_id).resultado
  end

  def passos_de(receita) = ensaio(receita)[:conversas].first[:passos]

  it 'monta o texto com os valores da conversa, para o balão' do
    passos = passos_de(receita(mensagem_passo('p1', 'Oi ', { '$valor' => 'contato.nome' }, ', obrigado.')))

    expect(passos).to eq([{ id: 'p1', tipo: 'mensagem', faria: 'mensagem', dados: { texto: 'Oi Maria, obrigado.' } }])
  end

  it 'sem a mensagem automática, diz que não sairia' do
    account.disable_features!('automacao_mensagens')

    expect(passos_de(receita(mensagem_passo('p1', 'Oi')))).to eq([{ id: 'p1', tipo: 'mensagem', faria: 'mensagens_desligadas', dados: {} }])
  end

  it 'valor vazio na conversa: o passo pularia, como no motor' do
    contato.update!(name: '')

    expect(passos_de(receita(mensagem_passo('p1', 'Oi ', { '$valor' => 'contato.nome' }))).first[:faria]).to eq('faltou_valor')
  end

  it 'o "se" segue o ramo que vale agora e depois o resto' do
    se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => resolvida, 'entao' => [esperar_passo('e1')], 'senao' => [esperar_passo('e2')] }

    passos = passos_de(receita(se, esperar_passo('e3')))

    expect(passos.pluck(:id)).to eq(%w[s1 e1 e3])
    expect(passos.first[:dados]).to eq(ramo: 'entao')
  end

  it 'o "esperar até" que ainda não vale abre os dois caminhos', :aggregate_failures do
    espera = { 'id' => 'a1', 'tipo' => 'esperar_ate', 'condicao' => aberta, 'prazo' => { 'valor' => 2, 'unidade' => 'horas' },
               'se_vencer' => [esperar_passo('v1')] }

    no = passos_de(receita(espera, esperar_passo('r1'))).first

    expect(no[:faria]).to eq('esperar_ate')
    expect(no[:ramos].map { |ramo| [ramo[:chave], ramo[:passos].pluck(:id)] }).to eq([['chegou', %w[r1]], ['se_vencer', %w[v1 r1]]])
  end

  it 'o "esperar até" que já vale segue na hora' do
    espera = { 'id' => 'a1', 'tipo' => 'esperar_ate', 'condicao' => resolvida, 'prazo' => { 'valor' => 2, 'unidade' => 'horas' } }

    expect(passos_de(receita(espera, esperar_passo('r1'))).map { |no| [no[:id], no[:faria]] }).to eq([%w[a1 esperar_ate_ja_vale], %w[r1 esperar]])
  end

  # #2523: o aviso só para o responsável, na conversa sem responsável, não sairia para ninguém.
  it 'o aviso só para o responsável diz que ninguém seria avisado na conversa sem responsável', :aggregate_failures do
    aviso = avisar_passo('a1', { 'responsavel' => true }, 'Chegou reclamação')

    expect(passos_de(receita(aviso)).first).to eq(id: 'a1', tipo: 'avisar', faria: 'sem_responsavel', dados: {})

    conversa.update!(assignee: admin)
    expect(passos_de(receita(aviso)).first).to include(faria: 'avisar', dados: { texto: 'Chegou reclamação' })
  end

  # #2552: com a reserva da caixa, o aviso sem responsável iria para quem atende a caixa.
  it 'o aviso com a reserva, sem responsável, mostra o texto e diz que iria para a caixa' do
    aviso = avisar_passo('a1', { 'responsavel' => true, 'se_nao_houver' => 'caixa' }, 'Chegou reclamação')

    expect(passos_de(receita(aviso)).first).to eq(id: 'a1', tipo: 'avisar', faria: 'avisar',
                                                  dados: { texto: 'Chegou reclamação', reserva: 'caixa' })
  end

  it 'o "decidir" mostra todos os caminhos e o "nenhum", sem chamar IA' do
    decidir = { 'id' => 'd1', 'tipo' => 'decidir', 'pergunta' => 'Sobre o quê?', 'nenhum' => [],
                'caminhos' => [{ 'chave' => 'cotacao', 'nome' => 'Cotação', 'passos' => [esperar_passo('c1')] }] }

    no = passos_de(receita(decidir, esperar_passo('r1'))).first

    expect(no[:ramos].map { |ramo| [ramo[:chave], ramo[:passos].pluck(:id)] }).to eq([['cotacao', %w[c1 r1]], ['nenhum', %w[r1]]])
  end

  it 'um tipo que o ensaio não conhece só ganha a frase do catálogo' do
    expect(passos_de(receita({ 'id' => 'x1', 'tipo' => 'inventado' })).first).to eq(id: 'x1', tipo: 'inventado', faria: 'catalogo', dados: {})
  end

  it '"parar" acaba o caminho' do
    expect(passos_de(receita({ 'id' => 'f1', 'tipo' => 'parar' }, esperar_passo('r1'))).pluck(:id)).to eq(%w[f1])
  end

  it 'fora do "Só se" do gatilho, não entraria' do
    resultado = ensaio(receita(esperar_passo('e1'), gatilho: { 'tipo' => 'conversa.resolvida', 'filtros' => [aberta] }))

    expect(resultado[:conversas].first).to include(entraria: false, motivo: 'fora_do_filtro', passos: [])
  end

  it 'no Spam, não entraria' do
    allow(ConversaCanal::PastaDoEmail).to receive(:no_spam?).with(conversa).and_return(true)

    expect(ensaio(receita(esperar_passo('e1')))[:conversas].first).to include(entraria: false, motivo: 'spam')
  end

  it 'no gatilho de mensagem, conversa sem mensagem não entraria; atividade não conta' do
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :activity, content: 'resolvida')

    resultado = ensaio(receita(esperar_passo('e1'), gatilho: { 'tipo' => 'mensagem.criada' }))

    expect(resultado[:conversas].first).to include(entraria: false, motivo: 'sem_mensagem')
  end

  describe 'quais conversas' do
    let(:agente) { create(:user, account: account, role: :agent) }
    let(:outra_caixa) { create(:inbox, account: account) }
    let!(:escondida) { create(:conversation, account: account, inbox: outra_caixa) }

    before { create(:inbox_member, user: agente, inbox: inbox) }

    it 'só as que quem pede enxerga, a mais recente primeiro' do
      recente = create(:conversation, account: account, inbox: inbox, last_activity_at: 1.minute.from_now)

      ids = ensaio(receita(esperar_passo('e1')), usuario: agente)[:conversas].pluck(:conversa_id)

      expect(ids).to eq([recente.display_id, conversa.display_id])
    end

    it 'a conversa escolhida fora do alcance é como se não existisse' do
      expect { ensaio(receita(esperar_passo('e1')), usuario: agente, conversa_id: escondida.display_id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'as 10 recentes ensaiadas e as seguintes só com o nome, para escolher outra', :aggregate_failures do
      create_list(:conversation, 11, account: account, inbox: inbox)

      resultado = ensaio(receita(esperar_passo('e1')), usuario: agente)

      expect(resultado[:conversas].size).to eq(10)
      expect(resultado[:outras].size).to eq(2)
      expect(resultado[:outras].first.keys).to eq(%i[conversa_id nome])
    end
  end

  it 'só lê: nada grava, manda, enfileira nem transmite', :aggregate_failures do
    se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => resolvida, 'entao' => [mensagem_passo('m1', 'Oi')] }
    acao = { 'id' => 'x1', 'tipo' => 'acao', 'acao' => 'POST conversations/:conversation_id/labels', 'descricao' => 'Etiqueta',
             'corpo' => { 'labels' => ['vip'] } }
    contar = -> { [Autonomia::Automacao::Execucao.count, Autonomia::Automacao::Registro.count, Message.count, conversa.reload.label_list] }
    chaves = -> { Redis::Alfred.with { |conexao| conexao.keys('*') }.sort }
    redis = chaves.call
    allow(ActionCable.server).to receive(:broadcast)
    admin

    antes = contar.call
    expect { ensaio(receita(se, acao, esperar_passo('e1'))) }.not_to have_enqueued_job
    expect(contar.call).to eq(antes)
    expect(chaves.call).to eq(redis)
    expect(ActionCable.server).not_to have_received(:broadcast)
  end
end
