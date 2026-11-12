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

  # Lote 5 (#2681): o modelo de propaganda sai fora da janela, e a tela avisa que custa mais.
  it 'diz o modelo que sai com a janela fechada e marca o de propaganda' do
    canal = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    modelo = { 'name' => 'pre_black', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
               'components' => [{ 'type' => 'BODY', 'text' => 'Oi! A Black começa na quinta.' }] }
    canal.update!(message_templates: [modelo])
    conversa.update!(inbox: canal.inbox)
    passo = mensagem_passo('p1', 'Oi.').merge('modelo' => { 'nome' => 'pre_black', 'idioma' => 'pt_BR', 'variaveis' => [] })

    expect(passos_de(receita(passo)).first[:dados]).to eq(texto: 'Oi.', modelo: 'pre_black', propaganda: true)
    canal.update!(message_templates: [modelo.merge('category' => 'UTILITY')])
    expect(passos_de(receita(passo)).first[:dados]).to eq(texto: 'Oi.', modelo: 'pre_black')
  end

  # #2609: com a janela fechada e sem modelo que saia no lugar, a execução para (#2573): o ensaio diz "pararia", com o
  # motivo do motor, e não lista os passos seguintes.
  describe 'janela fechada' do
    let(:canal) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:aprovado) do
      { 'name' => 'retorno', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi! Podemos falar?' }] }
    end
    let(:com_modelo) { mensagem_passo('p1', 'Oi.').merge('modelo' => { 'nome' => 'retorno', 'idioma' => 'pt_BR', 'variaveis' => [] }) }

    before { conversa.update!(inbox: canal.inbox) }

    def pararia(motivo) = [{ id: 'p1', tipo: 'mensagem', faria: 'pararia', dados: { motivo: motivo } }]

    it 'sem modelo, pararia fora da janela e o caminho acaba' do
      expect(passos_de(receita(mensagem_passo('p1', 'Oi.'), esperar_passo('e1')))).to eq(pararia('fora_da_janela'))
    end

    it 'com modelo que não sai, pararia com o motivo do modelo', :aggregate_failures do
      expect(passos_de(receita(com_modelo, esperar_passo('e1')))).to eq(pararia('modelo_fora_da_caixa'))

      canal.update!(message_templates: [aprovado.merge('status' => 'PENDING')])
      expect(passos_de(receita(com_modelo, esperar_passo('e1')))).to eq(pararia('modelo_nao_aprovado'))
    end

    it 'com o modelo que sai, mostra o texto e o modelo e segue' do
      canal.update!(message_templates: [aprovado])

      expect(passos_de(receita(com_modelo, esperar_passo('e1'))).map { |no| [no[:faria], no[:dados]] })
        .to eq([['mensagem', { texto: 'Oi.', modelo: 'retorno' }], ['esperar', {}]])
    end

    it 'com a janela aberta, a mensagem sairia e segue' do
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, content: 'Oi')

      expect(passos_de(receita(mensagem_passo('p1', 'Oi.'), esperar_passo('e1'))).pluck(:faria)).to eq(%w[mensagem esperar])
    end

    it 'o limite de horas da caixa API vencido pararia' do
      api = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '2' })
      conversa.update!(inbox: api.inbox)

      expect(passos_de(receita(mensagem_passo('p1', 'Oi.'), esperar_passo('e1')))).to eq(pararia('limite_da_caixa'))
    end

    it 'o "escrever" ao cliente pararia antes da IA; a sugestão segue', :aggregate_failures do
      escrever = { 'id' => 'i1', 'tipo' => 'escrever', 'le' => ['mensagens'], 'instrucao' => 'Agradeça', 'destino' => 'mensagem' }

      expect(passos_de(receita(escrever, esperar_passo('e1'))))
        .to eq([{ id: 'i1', tipo: 'escrever', faria: 'pararia', dados: { motivo: 'fora_da_janela' } }])
      expect(passos_de(receita(escrever.merge('destino' => 'sugestao'), esperar_passo('e1'))).pluck(:faria)).to eq(%w[ia_escrever esperar])
    end
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

  it 'o "esperar até" sem prazo que ainda não vale só abre o caminho de quando chegar (#2750)' do
    espera = { 'id' => 'a1', 'tipo' => 'esperar_ate', 'condicao' => aberta, 'prazo' => 'sem_prazo' }

    no = passos_de(receita(espera, esperar_passo('r1'))).first

    expect(no[:ramos].map { |ramo| [ramo[:chave], ramo[:passos].pluck(:id)] }).to eq([['chegou', %w[r1]]])
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

  # #2552: com a reserva da caixa, o ensaio faz a mesma conta do motor (só lê): diz por que iria para a caixa, ou que
  # ninguém da caixa seria avisado.
  describe 'o aviso com a reserva da caixa' do
    let(:aviso) { avisar_passo('a1', { 'responsavel' => true, 'se_nao_houver' => 'caixa' }, 'Chegou reclamação') }

    def no_do_aviso = passos_de(receita(aviso)).first

    before { create(:inbox_member, user: admin, inbox: inbox) }

    it 'sem responsável, mostra o texto e diz que iria para a caixa' do
      expect(no_do_aviso).to eq(id: 'a1', tipo: 'avisar', faria: 'avisar', dados: { texto: 'Chegou reclamação', reserva: 'sem_responsavel' })
    end

    it 'com responsável que não poderia ser avisado, diz que iria para a caixa por isso' do
      conversa.update!(assignee: create(:user, account: account, role: :agent))

      expect(no_do_aviso).to include(faria: 'avisar', dados: { texto: 'Chegou reclamação', reserva: 'responsavel_fora' })
    end

    it 'com responsável que poderia ser avisado, só o texto' do
      conversa.update!(assignee: admin)

      expect(no_do_aviso).to include(faria: 'avisar', dados: { texto: 'Chegou reclamação' })
    end

    it 'sem ninguém da caixa que pudesse ser avisado, diz que ninguém seria avisado' do
      InboxMember.where(inbox: inbox).delete_all

      expect(no_do_aviso).to eq(id: 'a1', tipo: 'avisar', faria: 'caixa_sem_ninguem', dados: {})
    end

    # O ensaio não tem execução: quem atende a reunião fica fora da conta, sem quebrar o ensaio.
    it 'com quem atende a reunião na lista, faz a conta da caixa do mesmo jeito' do
      com_reuniao = avisar_passo('a1', { 'responsavel' => true, 'se_nao_houver' => 'caixa', 'da_reuniao' => true }, 'Oi')

      expect(passos_de(receita(com_reuniao)).first).to include(faria: 'avisar', dados: { texto: 'Oi', reserva: 'sem_responsavel' })
    end
  end

  it 'o "decidir" mostra todos os caminhos e o "nenhum", sem chamar IA' do
    decidir = { 'id' => 'd1', 'tipo' => 'decidir', 'pergunta' => 'Sobre o quê?', 'nenhum' => [],
                'caminhos' => [{ 'chave' => 'cotacao', 'nome' => 'Cotação', 'passos' => [esperar_passo('c1')] }] }

    no = passos_de(receita(decidir, esperar_passo('r1'))).first

    expect(no[:ramos].map { |ramo| [ramo[:chave], ramo[:passos].pluck(:id)] }).to eq([['cotacao', %w[c1 r1]], ['nenhum', %w[r1]]])
  end

  describe 'extrair, escrever e resumir (#2500 F7)' do
    let(:extrair) do
      { 'id' => 'i1', 'tipo' => 'extrair', 'le' => ['mensagens'],
        'campos' => [{ 'chave' => 'placa', 'descricao' => 'A placa', 'destino' => 'conversa.placa' }] }
    end
    let(:escrever) { { 'id' => 'i2', 'tipo' => 'escrever', 'le' => ['mensagens'], 'instrucao' => 'Agradeça', 'destino' => 'mensagem' } }
    let(:resumir) { { 'id' => 'i3', 'tipo' => 'resumir', 'le' => ['mensagens'], 'destino' => { 'avisar' => { 'responsavel' => true } } } }

    before do
      allow(Crm::Ai::CredentialResolver).to receive(:new)
      allow(Crm::Ai::ResponsesClient).to receive(:new)
    end

    it 'dizem o que a IA faria e para onde iria, seguem para o próximo passo e não chamam IA', :aggregate_failures do
      conversa.update!(assignee: admin)
      passos = passos_de(receita(extrair, escrever, resumir, esperar_passo('r1')))

      expect(passos).to eq([
                             { id: 'i1', tipo: 'extrair', faria: 'ia_extrair',
                               dados: { campos: [{ chave: 'placa', destino: 'conversa.placa' }] } },
                             { id: 'i2', tipo: 'escrever', faria: 'ia_escrever', dados: { destino: 'mensagem' } },
                             { id: 'i3', tipo: 'resumir', faria: 'ia_resumir', dados: { destino: 'avisar' } },
                             { id: 'r1', tipo: 'esperar', faria: 'esperar', dados: {} }
                           ])
      expect(Crm::Ai::CredentialResolver).not_to have_received(:new)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'sem a mensagem automática, o que falaria com gente não sairia; a sugestão e a nota sim' do
      account.disable_features!('automacao_mensagens')
      sugestao = escrever.merge('id' => 'i4', 'destino' => 'sugestao')
      nota = resumir.merge('id' => 'i5', 'destino' => 'nota')

      passos = passos_de(receita(escrever, resumir, sugestao, nota))

      expect(passos.map { |no| [no[:id], no[:faria]] })
        .to eq([%w[i2 mensagens_desligadas], %w[i3 mensagens_desligadas], %w[i4 ia_escrever], %w[i5 ia_resumir]])
    end

    # #2552: o resumo que sai pelo "avisar" mostra o mesmo que o avisar, sem e com a reserva da caixa.
    it 'o resumo para o responsável, na conversa sem responsável, diz o mesmo que o avisar', :aggregate_failures do
      com_reserva = resumir.merge('id' => 'i6', 'destino' => { 'avisar' => { 'responsavel' => true, 'se_nao_houver' => 'caixa' } })
      create(:inbox_member, user: admin, inbox: inbox)

      expect(passos_de(receita(resumir)).first).to eq(id: 'i3', tipo: 'resumir', faria: 'sem_responsavel', dados: {})
      expect(passos_de(receita(com_reserva)).first)
        .to eq(id: 'i6', tipo: 'resumir', faria: 'ia_resumir', dados: { destino: 'avisar', reserva: 'sem_responsavel' })
      InboxMember.where(inbox: inbox).delete_all
      expect(passos_de(receita(com_reserva)).first).to eq(id: 'i6', tipo: 'resumir', faria: 'caixa_sem_ninguem', dados: {})
    end
  end

  # G3 (#2629): o retorno mostra o título montado ou por que pularia, e não cria nada.
  describe 'criar retorno' do
    let(:retorno) do
      { 'id' => 'r1', 'tipo' => 'retorno', 'titulo' => ['Ligar para ', { '$valor' => 'contato.nome' }],
        'daqui' => { 'valor' => 2, 'unidade' => 'dias' } }
    end

    it 'com responsável, o título montado; sem, diz que não criaria; nada é criado', :aggregate_failures do
      expect(passos_de(receita(retorno)).first).to include(faria: 'retorno_sem_responsavel')

      conversa.update!(assignee: admin)

      expect(passos_de(receita(retorno)).first).to eq(id: 'r1', tipo: 'retorno', faria: 'retorno', dados: { texto: 'Ligar para Maria' })
      expect(passos_de(receita(retorno.merge('para' => { 'quem' => 'pessoas', 'pessoas' => [admin.id] }))).first[:faria]).to eq('retorno')
      expect(Crm::FollowUp.count).to eq(0)
    end

    it 'com a mensagem e sem a mensagem automática, diz que não sairia' do
      account.disable_features!('automacao_mensagens')

      expect(passos_de(receita(retorno.merge('envio' => { 'mensagem' => ['Oi'] }))).first[:faria]).to eq('mensagens_desligadas')
    end

    it 'a mensagem com valor vazio ou só de espaços pula como o motor', :aggregate_failures do
      conversa.update!(assignee: admin)
      vazia = retorno.merge('envio' => { 'mensagem' => [{ '$valor' => 'contato.email' }] })

      conversa.contact.update!(email: nil)
      expect(passos_de(receita(vazia)).first[:faria]).to eq('faltou_valor')
      expect(passos_de(receita(retorno.merge('envio' => { 'mensagem' => ['   '] }))).first[:faria]).to eq('texto_vazio')
    end
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

  # G53: no gatilho "mensagem que falhou" o ensaio usa a última mensagem recusada da conversa, e o passo mostra o texto
  # real dela (o ex. 19, passo 2: "manda por e-mail o mesmo conteúdo").
  describe 'no gatilho "mensagem que falhou"' do
    let(:caixa_de_email) { create(:channel_email, account: account).inbox }
    let(:pergunta) { ' Você trocou de WhatsApp? Me responde com o número novo.' }
    let(:email) do
      { 'id' => 'email', 'tipo' => 'email', 'caixa_id' => caixa_de_email.id, 'assunto' => ['Você trocou de WhatsApp?'],
        'texto' => [{ '$valor' => 'falhou.texto' }, pergunta] }
    end
    let(:falhou) { receita(email, gatilho: { 'tipo' => 'mensagem.falhou' }) }

    def mensagem(**atributos)
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, **atributos)
    end

    before { contato.update!(email: 'maria@exemplo.com.br') }

    it 'o e-mail mostra o texto da última mensagem recusada, não da última da conversa', :aggregate_failures do
      mensagem(content: 'Primeira recusa.', status: :failed)
      mensagem(content: 'Seu boleto vence amanhã.', status: :failed)
      mensagem(content: 'Esta chegou.', status: :delivered)
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'Oi')

      no = passos_de(falhou).first

      expect(no[:faria]).to eq('email')
      expect(no[:dados]).to include(texto: "Seu boleto vence amanhã.#{pergunta}", assunto: 'Você trocou de WhatsApp?')
    end

    it 'sem mensagem recusada que saiu para o cliente, não entraria; a nota recusada não conta' do
      mensagem(content: 'Chegou.', status: :delivered)
      mensagem(content: 'Nota.', status: :failed, private: true)

      expect(ensaio(falhou)[:conversas].first).to include(entraria: false, motivo: 'sem_mensagem_que_falhou', passos: [])
    end

    it 'a recusada só com anexo pularia, como no motor' do
      mensagem(content: nil, status: :failed)

      expect(passos_de(falhou).first[:faria]).to eq('faltou_valor')
    end
  end

  # #2604: quem agiria (quem ligou, ou quem vai ligar) precisa poder agir na conversa, a pergunta do Executor no começo
  # de cada rodada (Acesso#motivo_no): sem isso, a automação pausaria no primeiro passo, e o caminho acaba ali. O e-mail
  # confere também a caixa dele.
  describe 'quem age' do
    let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
    let(:caixa_de_email) { create(:channel_email, account: account).inbox }
    let(:email) { { 'id' => 'em', 'tipo' => 'email', 'caixa_id' => caixa_de_email.id, 'assunto' => ['Oi'], 'texto' => ['Tudo bem?'] } }
    let(:pausaria) { { motivo: 'quem_ligou_sem_acesso', quem: 'Bia' } }
    let(:etiqueta) do
      { 'id' => 'x1', 'tipo' => 'acao', 'acao' => 'POST conversations/:conversation_id/labels', 'descricao' => 'Etiqueta',
        'corpo' => { 'labels' => ['vip'] } }
    end

    # Como a versão salva de uma automação que `quem` ligou: o controller passa o Acesso dela.
    def passos_como(quem, *passos)
      automacao = create(:autonomia_automacao, account: account, ligada_por: quem)
      acesso = Autonomia::Automacao::Acesso.new(automacao, chave_gatilho: 'conversa.resolvida')
      described_class.new(receita: receita(*passos), conta: account, usuario: admin, acesso: acesso).resultado[:conversas].first[:passos]
    end

    def gerencia_automacoes(quem)
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage])
      account.account_users.find_by(user: quem).update!(custom_role: funcao)
    end

    before { contato.update!(email: 'maria@exemplo.com.br') }

    it 'a mensagem e o aviso pausariam quando quem age não enxerga a conversa, e o caminho acaba', :aggregate_failures do
      gerencia_automacoes(bia)
      aviso = avisar_passo('a1', { 'pessoas' => [admin.id] }, 'Olha')

      expect(passos_como(bia, mensagem_passo('m1', 'Oi'), esperar_passo('e1')))
        .to eq([{ id: 'm1', tipo: 'mensagem', faria: 'pausaria', dados: pausaria }])
      expect(passos_como(bia, aviso, esperar_passo('e1'))).to eq([{ id: 'a1', tipo: 'avisar', faria: 'pausaria', dados: pausaria }])
      expect(passos_como(admin, mensagem_passo('m1', 'Oi'), esperar_passo('e1')).pluck(:faria)).to eq(%w[mensagem esperar])
    end

    # O motor pausa no começo da rodada, antes de qualquer passo (Executor#rodar): a ação, a IA e até a espera de antes
    # da mensagem não aparecem como feitas.
    it 'pausaria já no primeiro passo, seja ele qual for, e não lista os seguintes', :aggregate_failures do
      gerencia_automacoes(bia)
      resumir = { 'id' => 'r1', 'tipo' => 'resumir', 'le' => ['mensagens'], 'destino' => { 'avisar' => { 'responsavel' => true } } }

      expect(passos_como(bia, etiqueta, mensagem_passo('m1', 'Oi')))
        .to eq([{ id: 'x1', tipo: 'acao', faria: 'pausaria', dados: pausaria }])
      expect(passos_como(bia, resumir, mensagem_passo('m1', 'Oi'))).to eq([{ id: 'r1', tipo: 'resumir', faria: 'pausaria', dados: pausaria }])
      expect(passos_como(bia, esperar_passo('e1'), etiqueta)).to eq([{ id: 'e1', tipo: 'esperar', faria: 'pausaria', dados: pausaria }])
      expect(passos_como(admin, etiqueta, mensagem_passo('m1', 'Oi')).pluck(:faria)).to eq(%w[acao mensagem])
    end

    # A mesma pergunta inteira do motor: quem ligou e perdeu a permissão de gerenciar automações (ou saiu da conta)
    # pausaria a automação, mesmo vendo a conversa.
    it 'pausaria com o motivo do motor quando quem ligou não pode mais gerenciar automações' do
      create(:inbox_member, user: bia, inbox: inbox)

      expect(passos_como(bia, etiqueta, mensagem_passo('m1', 'Oi')))
        .to eq([{ id: 'x1', tipo: 'acao', faria: 'pausaria', dados: { motivo: 'quem_ligou_sem_permissao', quem: 'Bia' } }])
    end

    # O rascunho age como quem pede, que só ensaia as conversas que vê: o alcance não pausa.
    it 'sem o Acesso de quem ligou, age como quem pede' do
      passos = described_class.new(receita: receita(etiqueta, mensagem_passo('m1', 'Oi')), conta: account, usuario: admin)
                              .resultado[:conversas].first[:passos]

      expect(passos.pluck(:faria)).to eq(%w[acao mensagem])
    end

    it 'o e-mail pausaria quando quem age vê a conversa mas não começa conversa na caixa de e-mail', :aggregate_failures do
      gerencia_automacoes(bia)
      create(:inbox_member, user: bia, inbox: inbox)

      expect(passos_como(bia, email, esperar_passo('e1'))).to eq([{ id: 'em', tipo: 'email', faria: 'pausaria', dados: pausaria }])

      create(:inbox_member, user: bia, inbox: caixa_de_email)
      expect(passos_como(bia, email, esperar_passo('e1')).pluck(:faria)).to eq(%w[email esperar])
    end

    it 'o e-mail pausaria quando quem age não enxerga a conversa, mesmo na caixa de e-mail' do
      gerencia_automacoes(bia)
      create(:inbox_member, user: bia, inbox: caixa_de_email)

      expect(passos_como(bia, email).first).to include(faria: 'pausaria', dados: pausaria)
    end

    # Na ordem do PassoDeEmail: a caixa e quem age vêm antes do texto. Texto vazio sem acesso à caixa pausaria, não pularia.
    it 'o e-mail confere a caixa antes do texto, como o motor', :aggregate_failures do
      gerencia_automacoes(bia)
      create(:inbox_member, user: bia, inbox: inbox)
      vazio = email.merge('texto' => [' '])

      expect(passos_como(bia, vazio).first).to include(faria: 'pausaria', dados: pausaria)
      contato.update!(email: nil)
      expect(passos_como(admin, vazio).first[:faria]).to eq('contato_sem_email')
      contato.update!(email: 'maria@exemplo.com.br')
      expect(passos_como(admin, vazio).first[:faria]).to eq('texto_vazio')
    end
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
