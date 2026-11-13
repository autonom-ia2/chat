require 'rails_helper'

# E4 (#2897) — "Trazer minha lista" com seguros: na conta com a carteira, a planilha em que cada linha é um seguro. Da
# pergunta "esta planilha tem seguros?" ao que fica na carteira, passando pelos destinos das colunas e pelas linhas que
# precisam de conserto. O tipo de cada ramo é do modelo, que aqui é um dublê. Todos os dados são inventados.
RSpec.describe 'Trazer minha lista: a planilha traz seguros (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  let(:account) { conta_com_carteira }
  # Colunas: 0 Nome, 1 Celular, 2 E-mail, 3 Apólice, 4 Seguradora, 5 Ramo, 6 Início, 7 Fim, 8 Prêmio, 9 Bem.
  let(:cabecalho) { 'Nome;Celular;E-mail;Apólice;Seguradora;Ramo;Início;Fim;Prêmio;Bem' }
  let(:ana) { 'Ana Albuquerino;11987650001;ana.albuquerino@exemplo.com.br' }
  # Linhas 2 a 5: a Ana em três linhas (três seguros) e o Bruno em uma.
  let(:seguros_bons) do
    ["#{ana};EX-001234;Seguradora Exemplo;Automóvel;10/03/2026;10/03/2027;R$ 3.410;Carro Exemplo ABC1D23",
     "#{ana};EX-005678;Seguradora Exemplo;Residencial;01/06/2025;01/06/2026;890.50;Casa Exemplo",
     "#{ana};VD-000042;Outra Seguradora Exemplo;Vida;;15/09/2026;;",
     'Bruno Brandolim;11987650002;;EX-009999;Seguradora Exemplo;Automóvel;05/01/2026;05/01/2027;2.100;Moto Exemplo XYZ9A87']
  end
  # Linhas 6 a 8: sem o fim da vigência, a mesma apólice da linha 2 com outro valor, e o número em notação científica.
  let(:com_problema) do
    ['Carla Carvalhedo;11987650003;;EX-007777;Seguradora Exemplo;Automóvel;01/02/2026;;1.000;Carro Exemplo',
     'Davi Dornelino;11987650004;;EX-001234;Seguradora Exemplo;Automóvel;10/03/2026;10/03/2027;R$ 9.999;Carro Exemplo ABC1D23',
     'Elisa Esteveira;11987650005;;1.23457E+15;Seguradora Exemplo;Automóvel;;10/03/2027;;']
  end
  # Primeiro as colunas que podem faltar; a última obrigatória é a que faz a planilha ser lida de novo.
  let(:destinos) do
    { 6 => 'seguro_comeca', 8 => 'seguro_valor', 9 => 'seguro_bem', 3 => 'seguro_numero', 4 => 'seguro_seguradora', 5 => 'seguro_tipo',
      7 => 'seguro_termina' }
  end
  let(:obrigatorios) { %w[seguro_numero seguro_seguradora seguro_tipo seguro_termina] }
  let(:do_modelo) { { 'automóvel' => 'auto', 'residencial' => 'residencial', 'vida' => 'vida' } }
  let(:pergunta) { instance_double(Carteira::Trazer::PerguntaDoRamo) }

  before do
    allow(pergunta).to receive(:call) { |ramos| do_modelo.slice(*ramos) }
    allow(Carteira::Trazer::PerguntaDoRamo).to receive(:new).and_return(pergunta)
  end

  def planilha_de(*linhas)
    "#{([cabecalho] + linhas.flatten).join("\n")}\n"
  end

  def escolher_as_colunas(importacao)
    destinos.each do |indice, destino|
      trocar(importacao, indice, destino: destino)
      ler_de_novo
    end
  end

  # Envia, diz que a planilha tem seguros e escolhe as colunas: a conferência como a pessoa a deixa antes de trazer.
  def conferir_com_seguros(texto)
    importacao = ler_planilha(texto)
    responder(importacao, seguros: 'sim')
    ler_de_novo
    escolher_as_colunas(importacao)
    importacao
  end

  def trazer_tudo(texto)
    importacao = conferir_com_seguros(texto)
    trazer(importacao)
    gravar_a_lista
    importacao.reload
  end

  def apolices
    Carteira::Apolice.where(account_id: account.id)
  end

  # O que o bloco escreve no log do nível de produção (info): sem as consultas ao banco, que só saem em debug.
  def log_de
    saida = StringIO.new
    escuta = ActiveSupport::Logger.new(saida, level: Logger::INFO)
    Rails.logger.broadcast_to(escuta)
    yield
    saida.string
  ensure
    Rails.logger.stop_broadcasting_to(escuta)
  end

  def apolice(numero)
    apolices.find_by!(numero: numero)
  end

  describe 'a conferência' do
    it 'pergunta se a planilha tem seguros; só com "sim" as colunas aceitam os destinos do seguro, e sem as obrigatórias não traz' do
      importacao = ler_planilha(planilha_de(seguros_bons, com_problema))
      corpo = ler(importacao)
      expect(corpo['perguntas']).to include('id' => 'seguros')
      expect(corpo).not_to have_key('seguros')

      trocar(importacao, 3, destino: 'seguro_numero')
      expect([response.status, response.parsed_body['error']]).to eq([422, 'destino_desconhecido'])
      responder(importacao, seguros: 'talvez')
      expect([response.status, response.parsed_body['error']]).to eq([422, 'resposta_desconhecida'])

      responder(importacao, seguros: 'sim')
      expect(response.parsed_body).to eq('id' => importacao.id, 'situacao' => 'lendo')
      ler_de_novo
      corpo = ler(importacao)
      expect(corpo['respostas']).to include('seguros' => 'sim')
      expect(corpo['seguros']).to eq('destinos' => Carteira::Trazer::ColunasDeSeguro::DESTINOS, 'faltam' => obrigatorios)

      trazer(importacao)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'falta_coluna_do_seguro', 'faltam' => obrigatorios)
      expect(pergunta).not_to have_received(:call)
    end

    it 'com as colunas escolhidas, conta seguros e pessoas, mostra os seguros de cada pessoa e aponta as linhas que precisam de conserto' do
      importacao = conferir_com_seguros(planilha_de(seguros_bons, com_problema))
      corpo = ler(importacao)

      expect(corpo['seguros']['faltam']).to eq([])
      expect(corpo['colunas'].to_h { |coluna| [coluna['indice'], coluna['destino']] }).to include(destinos)
      expect(corpo['resumo']).to include(
        'total' => 7, 'comProblema' => 3, 'juntadas' => 0, 'entram' => 4, 'seguros' => 4, 'pessoas' => 2, 'clientes' => 2,
        'pessoasQueJaEstavam' => 0, 'repetidos' => 0, 'porTipo' => { 'auto' => 2, 'residencial' => 1, 'vida' => 1, 'empresarial' => 0, 'outro' => 0 }
      )
      expect(corpo['problemas'].map { |problema| problema.slice('linha', 'tipo', 'motivo', 'estado') }).to eq(
        [{ 'linha' => 6, 'tipo' => 'falta_termina', 'motivo' => 'falta', 'estado' => 'aberto' },
         { 'linha' => 7, 'tipo' => 'duplicado', 'estado' => 'aberto' },
         { 'linha' => 8, 'tipo' => 'numero', 'motivo' => 'notacao_cientifica', 'estado' => 'aberto' }]
      )
      expect(corpo['problemas'][1]).to include('numero' => 'EX-001234', 'outraLinha' => 2)
      expect(corpo['problemas'][1]['duplicadas'].pluck('linha', 'valor')).to eq([[2, 3410.0], [7, 9999.0]])
      # O texto que veio errado na célula não volta para a tela.
      expect(corpo['problemas'].to_json).not_to include('1.23457E+15')

      da_ana = corpo['exemplos'].first
      expect(da_ana).to include('nome' => 'Ana Albuquerino', 'cliente' => true)
      expect(da_ana['seguros'].pluck('tipo', 'ramoOriginal', 'numero', 'termina', 'valor')).to eq(
        [['auto', 'Automóvel', 'EX-001234', '2027-03-10', 3410.0], ['residencial', 'Residencial', 'EX-005678', '2026-06-01', 890.5],
         ['vida', 'Vida', 'VD-000042', '2026-09-15', nil]]
      )
      # O modelo recebeu só os ramos distintos das linhas boas, uma vez.
      expect(pergunta).to have_received(:call).with(match_array(%w[automóvel residencial vida])).once
    end

    it 'a linha com problema no seguro não tem conserto na tela, só na planilha; na apólice repetida a pessoa escolhe a linha' do
      importacao = conferir_com_seguros(planilha_de(seguros_bons, com_problema))

      consertar(importacao, 6, valor: '10/03/2027')
      expect([response.status, response.parsed_body]).to eq([422, { 'error' => 'valor_invalido', 'motivo' => 'conserto_na_planilha' }])

      consertar(importacao, 7, ficar_com: 7)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['problema']).to include('linha' => 7, 'tipo' => 'duplicado', 'estado' => 'guardado')
    end
  end

  describe 'trazer' do
    let(:fuso) { ActiveSupport::TimeZone[Crm::Timezone::Resolver.new(account: account).name_or_default] }

    it 'a pessoa em três linhas vira um contato com três seguros, cliente desde o começo de vigência mais antigo' do
      importacao = trazer_tudo(planilha_de(seguros_bons, com_problema))
      da_ana = account.contacts.find_by!(phone_number: '+5511987650001')

      expect(importacao).to be_completed
      expect([account.contacts.count, apolices.count]).to eq([2, 4])
      expect(da_ana.apolices.order(:numero).pluck(:numero, :tipo, :ramo_original, :valor_centavos, :origem)).to eq(
        [['EX-001234', 'auto', 'Automóvel', 341_000, 'planilha'], ['EX-005678', 'residencial', 'Residencial', 89_050, 'planilha'],
         ['VD-000042', 'vida', 'Vida', nil, 'planilha']]
      )
      expect(apolice('EX-001234')).to have_attributes(
        seguradora: 'Seguradora Exemplo', seguradora_chave: 'seguradoraexemplo', numero_chave: 'EX001234', inicio_vigencia: Date.new(2026, 3, 10),
        fim_vigencia: Date.new(2027, 3, 10), bem: 'Carro Exemplo ABC1D23', campaign_import_id: importacao.id, company_id: nil
      )
      chegada = apolice('EX-001234').eventos.sole
      expect([chegada.tipo, chegada.valores, chegada.user_id, chegada.campaign_import_id])
        .to eq(['chegou_planilha', { 'arquivo' => 'Clientes 2025.csv' }, admin.id, importacao.id])

      # As colunas do seguro não viram informação da pessoa, e quem entra com seguro é cliente.
      expect([da_ana.custom_attributes, account.custom_attribute_definitions.count]).to eq([{}, 0])
      expect(account.contacts.pluck(:contact_type).uniq).to eq(['customer'])
      expect(da_ana.customer_since).to eq(fuso.local(2025, 6, 1))
      expect(Relacionamentos::Trazer::Andamento.new(importacao).call)
        .to include(situacao: 'pronto', seguros: 4, pessoas: 2, pessoasNovas: 2, pessoasQueJaEstavam: 0)
    end

    it 'a mesma planilha de novo não duplica nada; o que mudou atualiza e entra na história; o corrigido à mão fica' do
      trazer_tudo(planilha_de(seguros_bons))
      apolice('EX-009999').update!(bem: 'Moto Corrigida', corrigido_a_mao: ['bem'])
      contagem = -> { [apolices.count, Carteira::ApoliceEvento.count, account.contacts.count] }

      expect { trazer_tudo(planilha_de(seguros_bons)) }.not_to(change { contagem.call })
      expect(contagem.call).to eq([4, 4, 2])

      # O valor do carro mudou, o fim da vigência da casa foi corrigido na origem e a moto veio com outro bem.
      mudada = ["#{ana};EX-001234;Seguradora Exemplo;Automóvel;10/03/2026;10/03/2027;R$ 3.900;Carro Exemplo ABC1D23",
                "#{ana};EX-005678;Seguradora Exemplo;Residencial;01/06/2025;01/07/2026;890.50;Casa Exemplo", seguros_bons[2],
                'Bruno Brandolim;11987650002;;EX-009999;Seguradora Exemplo;Automóvel;05/01/2026;05/01/2027;2.100;Moto Outra']
      terceira = trazer_tudo(planilha_de(mudada))

      expect(contagem.call).to eq([4, 6, 2])
      expect([apolice('EX-001234').valor_centavos, apolice('EX-005678').fim_vigencia, apolice('EX-009999').bem])
        .to eq([390_000, Date.new(2026, 7, 1), 'Moto Corrigida'])
      de_novo = apolice('EX-001234').eventos.order(:id).last
      expect([de_novo.tipo, de_novo.campaign_import_id]).to eq(['chegou_de_novo', terceira.id])
      expect(de_novo.mudancas).to eq([{ 'campo' => 'valor', 'antes' => 341_000, 'depois' => 390_000 }])
      expect(apolice('EX-005678').eventos.order(:id).last.mudancas)
        .to eq([{ 'campo' => 'termina', 'antes' => '2026-06-01', 'depois' => '2026-07-01' }])
      expect(apolice('EX-009999').eventos.pluck(:tipo)).to eq(%w[chegou_planilha])
    end

    it 'nenhuma linha de log leva número de apólice, placa nem o texto das células do seguro' do
      log = log_de { trazer_tudo(planilha_de(seguros_bons, com_problema)) }

      expect(apolices.count).to eq(4)
      expect(log).not_to be_empty
      expect(log).not_to include('EX-001234', 'EX001234', 'VD-000042', 'EX-007777', 'ABC1D23', 'XYZ9A87', '1.23457E+15', 'Seguradora Exemplo')
    end
  end

  context 'when a conta não tem a carteira' do
    let(:account) { create(:account) }

    it 'não recebe a pergunta, e mandar coisa de seguro responde 422' do
      importacao = ler_planilha(planilha_de(seguros_bons))
      corpo = ler(importacao)

      expect(corpo['perguntas'].pluck('id')).not_to include('seguros')
      expect(corpo).not_to have_key('seguros')
      responder(importacao, seguros: 'sim')
      expect([response.status, response.parsed_body['error']]).to eq([422, 'resposta_desconhecida'])
      trocar(importacao, 3, destino: 'seguro_numero')
      expect([response.status, response.parsed_body['error']]).to eq([422, 'destino_desconhecido'])
      expect(importacao.reload.options['trazer'].to_h.slice('respostas', 'destinos')).to eq({})
    end

    it 'a planilha sem seguros continua juntando as linhas da mesma pessoa, e nada vai para a carteira' do
      importacao = ler_planilha(planilha_de(seguros_bons))

      expect(ler(importacao)['resumo']).to include('total' => 4, 'juntadas' => 2, 'entram' => 2)
      trazer(importacao)
      gravar_a_lista
      expect([importacao.reload.completed?, account.contacts.count, apolices.count]).to eq([true, 2, 0])
      expect(pergunta).not_to have_received(:call)
    end
  end
end
