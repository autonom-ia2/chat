require 'rails_helper'

# A LEITURA DAS OFERTAS DE UMA COTAÇÃO: a ordem por período, o que conta como desfecho e o nome limpo. Desde a
# fatia 3 do #420 o texto do preço ao cliente é da Lia, e a conferência dele mora em `ConferenciaDePrecos`.
RSpec.describe Autonomia::Insurance::QuoteOffers do
  # `extra`: `code:` (a seguradora) e `motivo:` (o `basis_evidence` do adapter).
  def offer(name, amount, basis = 'total', installments = nil, **extra)
    { 'insurer' => { 'name' => name, 'code' => extra[:code] }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'basis' => basis, 'installments' => installments,
                     'basis_evidence' => extra[:motivo] } }
  end

  # O motivo que o adapter ESCREVIA para a Bp Assinatura na renovação real de 11/09/2026, quando ainda
  # a dava como `unknown` — antes de ler o `packageType=1` do portal. Fica como o exemplo de motivo de
  # oferta sem período, com os campos do portal pelo nome; a Bp real hoje sai `monthly` (abaixo).
  def motivo_bp
    'parcelamentos=[] (vazio): o portal nao ofereceu plano de pagamento; ' \
      'premioMensal=29.30 e premio/12 (derivado pelo portal, nao distingue periodo)'
  end

  # O motivo da assinatura mensal desde a noite de 11/09/2026: o marcador é do portal, e o PDF do
  # comparativo da mesma conversa imprime "por mês".
  def motivo_mensal(mensal = '24.87')
    # A string é a do adapter (autonomia-adapters#57), verbatim; `mensal` é premio/12 daquele valor.
    'packageType=1 (assinatura mensal: o relatorio do portal imprime "por mes"); ' \
      "parcelamentos=[] (assinatura nao parcela); premioMensal=#{mensal} e premio/12 (derivado pelo portal, nao distingue periodo)"
  end

  # ENTREGA 13, termo 5 — preço de período desconhecido nunca é ordenado pelo número cru. A Bp
  # Assinatura (351,59, então sem período) aparecia na frente da Porto (1.321,25 no total) como se
  # fosse a mais barata; sendo mensalidade (`packageType=1`), não é comparável ao total sem um
  # período comum.
  describe '#quoted' do
    it 'poe o preco sem periodo DEPOIS dos totais, mesmo com o numero menor' do
      ofertas = described_class.new(
        'offers' => [offer('Bp Assinatura', 351.59, 'unknown', code: '55', motivo: motivo_bp),
                     offer('Suhai', 1818.48, code: '20'), offer('Porto', 1321.25, code: '8')]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(['Porto', 'Suhai', 'Bp Assinatura'])
    end

    # ASSINATURA MENSAL: 298,43 por mês não é "mais barato" que 1.321,25 no total — são períodos
    # diferentes, e ×12 seria um número nosso (decisão de produto pendente). O bloco dos mensais vem
    # DEPOIS dos totais e ANTES dos sem período, e só se ordena pelo número entre si.
    it 'poe a mensal DEPOIS dos totais, mesmo com o numero menor — e ANTES de uma sem periodo mais barata' do
      # A sem período (10,00) entra no arranjo de propósito: sem ela, uma mensal tratada como "sem
      # período" iria para o fim do mesmo jeito, e o exemplo não distinguiria os dois blocos.
      ofertas = described_class.new(
        'offers' => [offer('X', 10.0, 'unknown', code: '1'),
                     offer('Bp Assinatura', 298.43, 'monthly', code: '55', motivo: motivo_mensal),
                     offer('Suhai', 1818.48, code: '20'), offer('Porto', 1321.25, code: '8')]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(['Porto', 'Suhai', 'Bp Assinatura', 'X'])
      expect(Autonomia::Insurance::PremiumText.new(ofertas[2]['premium']).resumo).to eq('R$ 298,43 por mês')
    end

    it 'poe a mensal ANTES das sem periodo' do
      ofertas = described_class.new(
        'offers' => [offer('X', 10.0, 'unknown', code: '1'),
                     offer('Bp Assinatura', 298.43, 'monthly', code: '55', motivo: motivo_mensal),
                     offer('Porto', 1321.25, code: '8')]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(['Porto', 'Bp Assinatura', 'X'])
    end

    it 'ordena as mensais entre si, da mais barata para a mais cara' do
      ofertas = described_class.new(
        'offers' => [offer('Bp Assinatura', 298.43, 'monthly', code: '55', motivo: motivo_mensal),
                     offer('Justos', 177.43, 'monthly', code: '47', motivo: motivo_mensal)]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(['Justos', 'Bp Assinatura'])
    end

    it 'entre os sem periodo, mantem a ordem em que o portal os devolveu, sem comparar numeros' do
      ofertas = described_class.new(
        'offers' => [offer('B', 400.0, 'unknown', code: '2'), offer('A', 300.0, 'unknown', code: '1')]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(%w[B A])
    end

    # O critério de "tem período" é UM só, o de `PremiumText#indefinido?`. Com `basis` nil (payload
    # sem `basis`), a partição por `basis == 'total'` a mandava para o fim, mas uma por
    # `basis != 'unknown'` a poria ENTRE OS TOTAIS pelo número cru — abrindo a lista como a mais
    # barata enquanto o texto da mesma oferta sai com a ressalva e o handle a registra sem período.
    it 'oferta sem `basis` vai para o fim, junto das sem periodo, mesmo com o numero menor' do
      ofertas = described_class.new(
        'offers' => [offer('X', 10.0, nil, code: '1'), offer('Porto', 1321.25, code: '8')]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(%w[Porto X])
    end

    it 'continua excluindo quem nao cotou e quem veio sem valor' do
      ofertas = described_class.new(
        'offers' => [offer('Porto', 900.0, code: '8').merge('status' => 'declined'),
                     { 'insurer' => { 'name' => 'Azul', 'code' => '9' }, 'status' => 'quoted', 'premium' => {} },
                     offer('Mapfre', 700.0, code: '3')]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(['Mapfre'])
    end
  end

  # ENTREGA 13, termo 1 — quando não sabemos o período, o MOTIVO fica registrado por oferta e diz
  # qual campo do portal faltou ou veio ambíguo. É o `basis_evidence` do adapter, sem tradução.
  describe '#sem_periodo' do
    it 'devolve, por codigo de seguradora, o motivo que o adapter escreveu' do
      ofertas = described_class.new(
        'offers' => [offer('Bp Assinatura', 351.59, 'unknown', code: '55', motivo: motivo_bp),
                     offer('Porto', 1321.25, code: '8', motivo: 'parcelas=10 x premioDemaisParc=132.12')]
      )

      expect(ofertas.sem_periodo).to eq('55' => motivo_bp)
    end

    it 'sem motivo do adapter, registra o que veio — nunca um texto nosso no lugar' do
      ofertas = described_class.new('offers' => [offer('X', 10.0, nil, code: '1')])

      expect(ofertas.sem_periodo).to eq('1' => 'basis=nil sem basis_evidence')
    end

    it 'e vazio quando toda oferta tem periodo' do
      expect(described_class.new('offers' => [offer('Porto', 1321.25, code: '8')]).sem_periodo).to eq({})
    end

    # A mensal TEM período, marcado pelo portal: registrá-la diria ao handle que o portal não
    # informou o que ele informou em `packageType=1`.
    it 'nao registra a mensal, so quem saiu sem periodo' do
      ofertas = described_class.new(
        'offers' => [offer('Bp Assinatura', 298.43, 'monthly', code: '55', motivo: motivo_mensal),
                     offer('X', 980.0, 'unknown', code: '1', motivo: 'nenhum dos 3 parcelamento(s) fecha com premio=980.0')]
      )

      expect(ofertas.sem_periodo).to eq('1' => 'nenhum dos 3 parcelamento(s) fecha com premio=980.0')
    end

    # O filtro é o de `#quoted` (só quem cotou com valor). Partindo de `offers` cru, o registro no
    # handle ganharia 'basis=nil sem basis_evidence' para quem nem cotou ou veio sem valor — motivo
    # de uma seguradora que o cliente nunca ouviu. Hoje o único chamador já passa `fresh` filtrado;
    # a unidade não pode depender de quem a chama.
    it 'ignora quem nao cotou e quem veio sem valor' do
      ofertas = described_class.new(
        'offers' => [offer('Porto', 900.0, 'unknown', code: '8', motivo: 'motivo da Porto').merge('status' => 'declined'),
                     { 'insurer' => { 'name' => 'Azul', 'code' => '9' }, 'status' => 'quoted', 'premium' => {} },
                     offer('Bp Assinatura', 351.59, 'unknown', code: '55', motivo: motivo_bp)]
      )

      expect(ofertas.sem_periodo).to eq('55' => motivo_bp)
    end
  end

  # FATIA 1 DO PDF RÁPIDO (13/09/2026): a cotação encerra quando TODA seguradora já tem desfecho, sem
  # esperar o portal declarar o negócio pronto. Medido no portal real: as dezessete responderam em
  # 41 s, 98 s e 64 s, e o portal só se declarou pronto em 188 s, 380 s e 316 s.
  #
  # RODADA 2: a lista precisa se repetir, com desfecho, em DUAS leituras seguidas (sonda C da revisão: a
  # lista que cresce entre leituras). Cada exemplo abaixo é uma das exigências da regra; tirar qualquer uma
  # delas do código reprova pelo menos um.
  describe '#assentada e #todas_com_desfecho?' do
    def oferta(code, status)
      { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => status }
    end

    def leitura(*ofertas)
      described_class.new('offers' => ofertas)
    end

    it 'assentada devolve os codigos em ordem quando toda oferta tem desfecho, e nil quando nao' do
      expect(leitura(oferta('8', 'quoted'), oferta('3', 'declined')).assentada).to eq(%w[3 8])
      expect(leitura(oferta('8', 'quoted'), oferta('3', 'running')).assentada).to be_nil
      expect(leitura.assentada).to be_nil
    end

    it 'e verdade quando a leitura anterior estava assentada com o mesmo conjunto e nenhuma acionada sumiu' do
      atual = leitura(oferta('8', 'quoted'), oferta('3', 'declined'), oferta('7', 'auth_required'))

      expect(atual.todas_com_desfecho?(%w[3 7 8], %w[3 7 8])).to be(true)
    end

    # `error` só sai do adapter DEPOIS de o portal declarar o negócio pronto, para a oferta sem preço
    # escolhível. Sem ele na lista, a cotação pronta com uma oferta assim esperaria o prazo inteiro.
    it 'conta error como desfecho' do
      expect(leitura(oferta('8', 'quoted'), oferta('4', 'error')).todas_com_desfecho?(%w[4 8], %w[4 8])).to be(true)
    end

    # A OFERTA SEM PREÇO E SEM ERRO, COM O NEGÓCIO ABERTO, É `running` NO ADAPTER — inclusive a do
    # cálculo cujos resultados vieram todos com erro. Ela segura o encerramento até o portal ficar
    # pronto, quando passa a `error`.
    it 'e falso com uma seguradora ainda running' do
      atual = leitura(oferta('8', 'quoted'), oferta('3', 'declined'), oferta('19', 'running'))

      expect(atual.todas_com_desfecho?(%w[3 8 19], %w[3 8 19])).to be(false)
    end

    # O CONTRATO DO ADAPTER TEM STATUS QUE O AGGER NÃO PRODUZ (`queued`, `timeout`, `not_configured`).
    # Um status fora da lista de desfechos segura o encerramento.
    it 'e falso com um status que nao esta na lista de desfechos' do
      expect(leitura(oferta('8', 'quoted'), oferta('3', 'queued')).todas_com_desfecho?(%w[3 8], %w[3 8])).to be(false)
      expect(leitura(oferta('8', 'quoted'), oferta('3', nil)).todas_com_desfecho?(%w[3 8], %w[3 8])).to be(false)
    end

    # A PRIMEIRA LEITURA ASSENTADA NÃO ENCERRA — nem a primeira de todas, nem a que vem depois de uma leitura
    # com seguradora em andamento (sonda C: [8, 20] em andamento, depois [8 cotou, 20 recusou]).
    it 'e falso quando a leitura anterior nao estava assentada' do
      atual = leitura(oferta('8', 'quoted'), oferta('20', 'declined'))

      expect(atual.todas_com_desfecho?(nil, nil)).to be(false)
      expect(atual.todas_com_desfecho?(%w[20 8], nil)).to be(false)
    end

    # A LISTA QUE CRESCEU: a leitura anterior assentada tinha outro conjunto.
    it 'e falso quando o conjunto mudou desde a leitura anterior' do
      atual = leitura(oferta('8', 'quoted'), oferta('20', 'declined'), oferta('47', 'quoted'))

      expect(atual.todas_com_desfecho?(%w[20 47 8], %w[20 8])).to be(false)
    end

    # A LEITURA QUE PERDEU UMA SEGURADORA JÁ ACIONADA não encerra, mesmo repetida: a que sumiu pode ainda
    # cotar.
    it 'e falso quando esta leitura nao traz uma seguradora que uma leitura anterior listou' do
      atual = leitura(oferta('8', 'quoted'), oferta('3', 'declined'))

      expect(atual.todas_com_desfecho?(%w[3 8 19], %w[3 8])).to be(false)
    end

    it 'e falso com a lista de ofertas vazia' do
      expect(leitura.todas_com_desfecho?(%w[3 8], [])).to be(false)
      expect(leitura.todas_com_desfecho?([], [])).to be(false)
    end
  end

  # A LISTA DE PREÇOS ESCRITA PELO CÓDIGO SAIU (fatia 3 do #420): quem escreve é a Lia, com os dados de
  # `ResultadoDaCotacao#preco`. O que fica daqui é o nome limpo que vai a ela.
  describe '.nome' do
    it 'tira do nome da seguradora o asterisco e a quebra de linha' do
      expect(described_class.nome(offer("Se*gu\nradora", 100.0))).to eq('Se gu radora')
    end
  end
end
