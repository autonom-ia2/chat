# Trazer do Agger (E7, #2900): o que os specs da busca no conector repetem. Tudo fictício, com o conector de mentira
# (Autonomia::Insurance::Connector::Mock::CarteiraDaCorretora) e sem chamada paga: o tipo de cada ramo vem de uma
# pergunta falsa.
module CarteiraConectorHelpers
  TIPOS_DOS_RAMOS = { 'automóvel' => 'auto', 'residencial' => 'residencial', 'vida' => 'vida', 'empresarial' => 'empresarial' }.freeze

  def sem_pergunta_paga_do_ramo
    pergunta = instance_double(Carteira::Trazer::PerguntaDoRamo)
    allow(pergunta).to receive(:call) { |ramos| ramos.index_with { |ramo| TIPOS_DOS_RAMOS.fetch(ramo, 'outro') } }
    allow(Carteira::Trazer::PerguntaDoRamo).to receive(:new).and_return(pergunta)
  end

  # A conexão do Agger da conta, pronta e com a sessão viva.
  def conectar_agger!(conta)
    Autonomia::Insurance::Connection.create!(account: conta, provider: 'agger', username: 'corretora@exemplo.test',
                                             password: 'segredo', status: 'ready')
                                    .tap { |conexao| conexao.store_session!({ 'token' => 'viva' }, expires_at: 3.hours.from_now) }
  end

  # Anda a busca até ela terminar ou parar, como o job faria, passando o tempo da espera do conector de mentira.
  def andar_a_busca(leitura, portal: nil)
    20.times do
      espera = Carteira::Conector::Sincronizar.new(leitura.reload, portal: portal).passo
      break if espera.nil?

      travel(espera + Autonomia::Insurance::Connector::Mock::CarteiraDaCorretora::BUSCANDO_POR)
    end
    leitura.reload
  end

  # A gravação inteira, bloco a bloco, como o job faria.
  def gravar_a_busca(leitura)
    5.times { break if Carteira::Conector::Gravar.new(leitura.reload).call == :terminou }
    leitura.reload
  end
end

RSpec.configure do |config|
  config.include CarteiraConectorHelpers
end
