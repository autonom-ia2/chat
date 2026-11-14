# E4 (#2897): o que os specs de "Trazer minha lista" com seguros têm em comum. A conta com a carteira, uma planilha em
# que cada linha é um seguro (dados inventados) e o caminho da tela até a lista gravada: enviar, responder que a planilha
# tem seguros, escolher as colunas e trazer. O tipo de cada ramo é do modelo, que aqui é um dublê: nenhum spec chama IA.
RSpec.shared_context 'with planilha de seguros' do
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

  def apolice(numero)
    apolices.find_by!(numero: numero)
  end
end
