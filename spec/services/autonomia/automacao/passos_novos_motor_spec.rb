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

    it 'sem resposta, segue pelo galho "se não conseguir buscar"' do
      stub_request(:get, url).to_return(status: 500)
      definicao = automacao_ligada(account, admin, [consulta, se_tem])

      expect(historico(rodar(definicao))).to eq([%w[busca ok consulta_recusada], ['nao', 'ok', nil]])
    end
  end
end
