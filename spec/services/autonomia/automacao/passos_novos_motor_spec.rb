require 'rails_helper'

# #2932–#2934 pelo motor de verdade: Partida, AvancarJob, o job da lista e a varredura.
RSpec.describe 'Passos novos da Automação livre no motor', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
  let(:contato) { account.contacts.create!(name: 'Mercado Bom Preço', phone_number: '+5511987654321') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:url) { 'https://loja.exemplo.com/pedidos/10482?token=abc' }

  around { |exemplo| with_modified_env(FRONTEND_URL: 'https://app.plataforma.com') { exemplo.run } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_passos_novos')
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('loja.exemplo.com').and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses).with('app.plataforma.com').and_return(['151.101.1.69'])
  end

  after { Current.reset }

  def parar(id) = { 'id' => id, 'tipo' => 'parar' }

  def rodar(definicao)
    perform_enqueued_jobs(only: [Autonomia::Automacao::AvancarJob, Autonomia::Automacao::RepetirListaJob]) { comecar(definicao, conversa) }
    Autonomia::Automacao::Execucao.find_by!(automacao: definicao, alvo: conversa)
  end

  def historico(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  describe 'fazer para cada um de uma lista (#2932)' do
    let!(:vips) do
      account.labels.create!(title: 'vip')
      %w[Ana Bruno Carla Diego].map do |nome|
        account.contacts.create!(name: nome, email: "#{nome.downcase}@exemplo.com").tap do |pessoa|
          pessoa.update!(label_list: ['vip'])
        end
      end
    end

    def lista(teto:, ritmo: 'rapido')
      { 'id' => 'lista', 'tipo' => 'repetir_lista', 'lista' => { 'de' => 'etiqueta', 'etiqueta' => 'vip' }, 'teto' => teto,
        'ritmo' => ritmo, 'cada' => [parar('c1')] }
    end

    it 'cada item ganha a execução dele, sem o bloqueado, até o teto, e a mãe conta tudo', :aggregate_failures do
      vips.last.update!(blocked: true)
      definicao = automacao_ligada(account, admin, [lista(teto: 2), parar('fim')])

      mae = rodar(definicao)

      filhas = Autonomia::Automacao::Execucao.where(automacao: definicao, alvo_type: 'Contact')
      expect(filhas.map(&:alvo)).to match_array(vips.first(2))
      expect(filhas.pluck(:estado).uniq).to eq(['concluida'])
      expect(mae.reload.estado).to eq('concluida')
      rodou = Autonomia::Automacao::Registro.find_by!(execucao: mae, motivo: 'lista_rodou')
      expect(rodou.dados).to include('abertas' => 2, 'passou_do_teto' => 1, 'teto' => 2)
      expect(Autonomia::Automacao::Historico.new(automacao: definicao, usuario: admin).resultado[:execucoes]).to be_present
    end

    it 'um por minuto: a primeira anda já e as outras esperam, um minuto cada', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [lista(teto: 3, ritmo: 'aos_poucos')])

      rodar(definicao)

      filhas = Autonomia::Automacao::Execucao.where(automacao: definicao, alvo_type: 'Contact').order(:id)
      expect(filhas.map(&:estado)).to eq(%w[concluida esperando esperando])
      expect(filhas.second.due_at).to be < filhas.third.due_at
    end

    it 'rodar de novo a mesma lista não abre o item que já está no meio da automação (sem laço)' do
      definicao = automacao_ligada(account, admin, [lista(teto: 3, ritmo: 'aos_poucos')])
      mae = rodar(definicao)

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::RepetirListaJob.perform_now(account.id, mae.id, 'lista')
      end

      expect(Autonomia::Automacao::Execucao.where(automacao: definicao, alvo_type: 'Contact').count).to eq(3)
    end

    it 'com a flag desligada, a execução que chega no passo para' do
      definicao = automacao_ligada(account, admin, [lista(teto: 2)])
      account.disable_features!('automacao_passos_novos')

      expect(historico(rodar(definicao))).to eq([%w[lista pulado passos_novos_desligados]])
    end

    def contas(mae) = Autonomia::Automacao::Registro.where(execucao: mae, motivo: 'lista_rodou').order(:id).map(&:dados)

    it 'quem quem ligou não alcança fica de fora; a nova tentativa do job retoma sem abrir de novo', :aggregate_failures do
      fora = vips.first
      allow_any_instance_of(Autonomia::Automacao::Acesso).to receive(:alcanca?).and_wrap_original do |original, alvo, *resto| # rubocop:disable RSpec/AnyInstance
        alvo == fora ? false : original.call(alvo, *resto)
      end
      definicao = automacao_ligada(account, admin, [lista(teto: 2, ritmo: 'aos_poucos')])
      mae = rodar(definicao)

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::RepetirListaJob.perform_now(account.id, mae.id, 'lista')
      end

      primeira, segunda = contas(mae)
      expect(primeira).to include('abertas' => 2, 'abertas_antes' => 0, 'fora_do_alcance' => 1, 'passou_do_teto' => 1)
      expect(segunda).to include('abertas' => 0, 'abertas_antes' => 2, 'fora_do_alcance' => 1, 'passou_do_teto' => 1)
      expect(Autonomia::Automacao::Execucao.where(automacao: definicao, alvo_type: 'Contact').map(&:alvo)).to match_array(vips[1, 2])
    end

    it 'outra rodada da automação não abre de novo o item que ainda está no meio dela', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [lista(teto: 2, ritmo: 'aos_poucos')])
      rodar(definicao)
      outra = create_crm_conversation(account: account, inbox: inbox, contact: account.contacts.create!(name: 'Outra'))

      perform_enqueued_jobs(only: [Autonomia::Automacao::AvancarJob, Autonomia::Automacao::RepetirListaJob]) { comecar(definicao, outra) }

      segunda_mae = Autonomia::Automacao::Execucao.find_by!(automacao: definicao, alvo: outra)
      # Ana terminou e entra de novo; Bruno ainda espera a vez dele (um por minuto) e fica de fora.
      expect(contas(segunda_mae).first).to include('abertas' => 2, 'ja_aberta' => 1)
    end

    it 'flag desligada com o job já na fila: não abre nada, e a filha que esperava a vez para', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [lista(teto: 2, ritmo: 'aos_poucos')])
      mae = rodar(definicao)
      esperando = Autonomia::Automacao::Execucao.find_by!(automacao: definicao, alvo_type: 'Contact', estado: 'esperando')
      account.disable_features!('automacao_passos_novos')

      Autonomia::Automacao::RepetirListaJob.perform_now(account.id, mae.id, 'lista')
      esperando.update!(due_at: 1.minute.ago)
      varrer

      expect(historico(mae).last).to eq(%w[lista pulado passos_novos_desligados])
      expect(Autonomia::Automacao::Execucao.where(automacao: definicao, alvo_type: 'Contact').count).to eq(2)
      expect(esperando.reload.estado).to eq('parada')
      expect(historico(esperando).last).to eq(%w[inicio pulado passos_novos_desligados])
    end
  end

  describe 'usar outra automação (#2933)' do
    let(:bloco) do
      create(:autonomia_automacao, account: account, bloco: true).tap do |definicao|
        definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [parar('b1')] }, autor: admin)
      end
    end

    it 'roda o bloco no mesmo alvo, como quem ligou a de cima, e segue quando ele termina', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [{ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => bloco.id }, parar('fim')])

      mae = rodar(definicao)
      filha = Autonomia::Automacao::Execucao.find_by!(automacao: bloco, alvo: conversa)
      expect(filha.estado).to eq('concluida')
      expect(filha.dona).to eq(definicao)

      varrer

      expect(mae.reload.estado).to eq('concluida')
      expect(historico(mae)).to eq([%w[usar ok bloco_chamado], %w[usar ok bloco_terminou], ['fim', 'ok', nil]])
      dentro = Autonomia::Automacao::Historico.new(automacao: definicao, usuario: admin).dentro(filha.id)
      expect(dentro[:execucoes].first[:passos].pluck(:passo)).to include('b1')
      expect(Autonomia::Automacao::Historico.new(automacao: create(:autonomia_automacao, account: account), usuario: admin)
                                            .dentro(filha.id)).to be_nil
    end

    def usar(definicao, id = 'usar') = { 'id' => id, 'tipo' => 'usar_bloco', 'bloco_id' => definicao.id }

    def novo_bloco(passos)
      create(:autonomia_automacao, account: account, bloco: true).tap do |definicao|
        definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }, autor: admin)
      end
    end

    def execucao_de(definicao) = Autonomia::Automacao::Execucao.find_by!(automacao: definicao, alvo: conversa)

    # O bloco muda depois de a de cima salvar: a rodada confere de novo a profundidade pelas execuções de cima.
    it 'bloco dentro de bloco além do limite, por uma mudança depois de salvar, para na execução', :aggregate_failures do
      primeiro = novo_bloco([parar('b1')])
      segundo = novo_bloco([usar(primeiro, 'usa_1')])
      terceiro = novo_bloco([usar(segundo, 'usa_2')])
      definicao = automacao_ligada(account, admin, [usar(terceiro), parar('fim')])
      primeiro.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [usar(novo_bloco([parar('b0')]), 'usa_0')] },
                              autor: admin)

      rodar(definicao)

      expect(execucao_de(primeiro).estado).to eq('falhou')
      expect(historico(execucao_de(primeiro)).last).to eq(%w[usa_0 falhou bloco_fundo_demais])
    end

    # O salvar recusa o laço (Bloco.laco_ao_salvar); a versão gravada por fora (defeito, corrida) para na rodada.
    it 'o bloco que chega nele mesmo para na execução, sem laço', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [usar(bloco), parar('fim')])
      laco = bloco.versoes.new(account: account, numero: 2, autor: admin, digest: SecureRandom.hex(32),
                               receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [usar(bloco, 'de_novo')] })
      laco.save!(validate: false)
      bloco.update!(versao_ativa: laco)

      rodar(definicao)

      expect(Autonomia::Automacao::Execucao.where(automacao: bloco).count).to eq(1)
      expect(historico(execucao_de(bloco)).last).to eq(%w[de_novo falhou bloco_em_laco])
    end

    # #2933, revisão: quem muda o bloco não age com as permissões de quem ligou a automação que o usa.
    it 'a versão nova do bloco pausa a automação ligada por outra pessoa, e não a de quem salvou', :aggregate_failures do
      outra_pessoa = create(:user, account: account, role: :agent)
      outra_pessoa.account_users.find_by(account: account)
                  .update!(custom_role: create(:custom_role, account: account, permissions: %w[automation_manage]))
      de_quem_salva = automacao_ligada(account, admin, [usar(bloco)])
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [parar('b2')] }

      bloco.salvar_versao!(receita: receita, autor: admin)
      expect(de_quem_salva.reload.ativa).to be(true)

      bloco.salvar_versao!(receita: receita, autor: outra_pessoa)
      expect(de_quem_salva.reload.ativa).to be(false)
    end

    it 'o bloco que falha faz a de cima parar com o motivo', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [{ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => bloco.id }, parar('fim')])
      mae = rodar(definicao)
      Autonomia::Automacao::Execucao.find_by!(automacao: bloco).update!(estado: 'falhou')
      mae.update!(due_at: Time.current)

      varrer

      expect(mae.reload.estado).to eq('falhou')
      expect(historico(mae).last).to eq(%w[usar falhou bloco_falhou])
    end
  end

  # Revisão: um "para cada" que usa um bloco com outro "para cada" dentro multiplicaria as execuções sem teto. O salvar
  # recusa; o bloco que ganha o "para cada" depois para na rodada, sem abrir netas.
  describe 'para cada que usa um bloco (#2932 com #2933)' do
    let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
    let(:etapa) { funil_e_etapa.last }
    let(:cards) do
      ['Proposta A', 'Proposta B'].map do |titulo|
        account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: etapa, title: titulo, currency: 'BRL', value_cents: 1_000)
      end
    end
    let(:da_etapa) { { 'de' => 'etapa', 'etapa_id' => etapa.id } }
    let(:bloco_do_card) do
      create(:autonomia_automacao, account: account, bloco: true).tap do |definicao|
        definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [parar('b1')] }, autor: admin)
      end
    end

    around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

    before { account.enable_features!('automacao_gatilhos') }

    def para_cada(cada) = { 'id' => 'lista', 'tipo' => 'repetir_lista', 'lista' => da_etapa, 'teto' => 10, 'ritmo' => 'rapido', 'cada' => cada }

    it 'o bloco que ganhou um "para cada" depois de a de cima salvar não abre netas', :aggregate_failures do
      cards
      definicao = automacao_ligada(account, admin, [para_cada([{ 'id' => 'usar', 'tipo' => 'usar_bloco', 'bloco_id' => bloco_do_card.id }])])
      dentro = { 'id' => 'de_dentro', 'tipo' => 'repetir_lista', 'lista' => da_etapa, 'teto' => 10, 'ritmo' => 'rapido', 'cada' => [parar('n1')] }
      bloco_do_card.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [dentro] }, autor: admin)

      rodar(definicao)

      do_bloco = Autonomia::Automacao::Execucao.where(automacao: bloco_do_card)
      expect(do_bloco.count).to eq(2)
      do_bloco.each { |execucao| expect(historico(execucao)).to include(%w[de_dentro pulado receita_com_problema]) }
      expect(Autonomia::Automacao::Execucao.where(automacao: bloco_do_card).where('evento LIKE ?', 'lista:%')).to be_empty
    end
  end

  describe 'buscar informação em outro sistema (#2934)' do
    let(:consulta) do
      { 'id' => 'busca', 'tipo' => 'consultar', 'fonte' => { 'de' => 'endereco', 'url' => url },
        'guardar' => [{ 'nome' => 'Status do pedido', 'caminho' => 'pedido.status' }], 'nao_consultou' => [parar('nao')] }
    end
    let(:se_tem) do
      { 'id' => 'tem', 'tipo' => 'se', 'condicao' => { 'campo' => { '$valor' => 'consulta.busca.status_do_pedido' }, 'op' => 'igual',
                                                       'valor' => 'enviado' }, 'entao' => [parar('sim')] }
    end

    it 'guarda o dado com o nome que a pessoa deu, e o passo seguinte lê; o histórico nunca leva o endereço', :aggregate_failures do
      stub_request(:get, url).to_return(status: 200, body: { pedido: { status: 'enviado' } }.to_json)
      definicao = automacao_ligada(account, admin, [consulta, se_tem])

      mae = rodar(definicao)

      expect(historico(mae)).to eq([['busca', 'ok', nil], ['tem', 'ok', nil], ['sim', 'ok', nil]])
      # O "sim" prova que o passo seguinte leu o dado; terminada, a execução perde o que buscou (Execucao::AO_TERMINAR).
      expect(mae.reload.textos).to eq({})
      expect(Autonomia::Automacao::Registro.where(execucao: mae).pluck(:dados).to_json).not_to include('loja.exemplo.com')
    end

    it 'quem ligou perdeu a chave de integrações: não busca e a automação pausa', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [consulta, se_tem])
      allow(Autonomia::Automacao::PassoDeWebhook).to receive(:pode_mandar?).and_return(false)

      mae = rodar(definicao)

      expect(historico(mae)).to eq([%w[busca falhou consulta_sem_permissao]])
      expect(mae.reload.estado).to eq('parada')
      expect(definicao.reload.ativa).to be(false)
      expect(WebMock).not_to have_requested(:get, url)
    end

    it 'sem resposta, segue pelo galho "se não conseguir buscar"' do
      stub_request(:get, url).to_return(status: 500)
      definicao = automacao_ligada(account, admin, [consulta, se_tem])

      expect(historico(rodar(definicao))).to eq([%w[busca ok consulta_recusada], ['nao', 'ok', nil]])
    end
  end
end
