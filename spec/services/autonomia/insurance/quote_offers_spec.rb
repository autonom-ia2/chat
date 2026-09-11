require 'rails_helper'

# O TEXTO DO PREÇO É ESCRITO POR CÓDIGO, e não pelo modelo — preço redigido por modelo é preço que
# ele pode arredondar ou trocar de seguradora. O custo dessa escolha é que a instrução ("negrito no
# nome e no valor") não alcança aqui, e ninguém testava o formato: em 08/09/2026 o cliente leu
# `Usebens: R$ 2837,70` numa lista corrida, sem negrito, sem milhar, com a mesma ressalva repetida
# por extenso em toda mensagem.
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
  def motivo_mensal
    "packageType=1 (assinatura mensal: o relatorio do portal imprime 'por mes'); parcelamentos=[]"
  end

  # ENTREGA 13, termo 5 — preço de período desconhecido nunca é ordenado pelo número cru. A Bp
  # Assinatura (351,59, então sem período) aparecia na frente da Porto (1.321,25 no total) como se
  # fosse a mais barata; sendo mensalidade (`packageType=1`), é a mais cara da lista.
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
    it 'poe a mensal DEPOIS dos totais, mesmo com o numero menor' do
      ofertas = described_class.new(
        'offers' => [offer('Bp Assinatura', 298.43, 'monthly', code: '55', motivo: motivo_mensal),
                     offer('Suhai', 1818.48, code: '20'), offer('Porto', 1321.25, code: '8')]
      ).quoted

      expect(ofertas.map { |o| o['insurer']['name'] }).to eq(['Porto', 'Suhai', 'Bp Assinatura'])
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

  describe '.describe' do
    it 'poe o nome em negrito do WhatsApp, que e asterisco simples' do
      # Não há conversão de markdown na saída: `**nome**` chegaria com os asteriscos à mostra.
      texto = described_class.describe([offer('Suhai', 4147.70)], first: true)

      expect(texto).to include('*Suhai*')
      expect(texto).not_to include('**')
    end

    it 'separa o milhar' do
      texto = described_class.describe([offer('Usebens', 2837.70)], first: true)

      expect(texto).to include('R$ 2.837,70')
      expect(texto).not_to include('R$ 2837,70')
    end

    it 'abre item com marcador, um por linha' do
      texto = described_class.describe([offer('Darwin', 2058.27), offer('Justos', 198.33)], first: true)

      expect(texto.lines.grep(/\A• /).size).to eq(2)
    end

    # A ressalva vale para UMA oferta, e vinha como parágrafo no fim valendo para o bloco inteiro —
    # maior que os próprios preços, e sem dizer de quem era.
    it 'cola a ressalva na oferta a que ela pertence' do
      texto = described_class.describe(
        [offer('Bp Assinatura', 402.26, nil, nil), offer('Darwin', 2058.27, 'total')], first: false
      )
      linhas = texto.lines.map(&:chomp)
      indice = linhas.index { |linha| linha.include?('Bp Assinatura') }

      expect(linhas[indice + 1]).to include('não informou')
      # E aparece UMA vez: como parágrafo do bloco ela valia para ofertas que tinham base.
      expect(texto.scan('não informou').size).to eq(1)
    end

    it 'nao repete a ressalva quando todas as ofertas tem base' do
      texto = described_class.describe([offer('Suhai', 4147.70, 'total')], first: true)

      expect(texto).not_to include('não informou')
    end

    # "Primeiros preços que chegaram" / "Chegaram mais opções" descreviam a NOSSA fila de entrega.
    it 'nao telegrafa o mecanismo de entrega' do
      texto = described_class.describe([offer('Darwin', 2058.27)], first: false)

      expect(texto).not_to include('chegaram')
      expect(texto).not_to include('Chegaram')
    end

    it 'abre o primeiro lote sem prometer que virao outros' do
      texto = described_class.describe([offer('Suhai', 4147.70)], first: true)

      expect(texto).to start_with('Primeiros preços:')
    end

    # Nome vindo do portal, interpolado dentro do negrito: um `*` fecharia o negrito cedo.
    it 'nao deixa o nome da seguradora quebrar o negrito' do
      texto = described_class.describe([offer("Se*gu\nradora", 100.0)], first: true)

      expect(texto).to start_with("Primeiros preços:\n\n• *Se gu radora* —")
    end

    it 'concorda em numero com as ofertas do lote' do
      uma = described_class.describe([offer('Darwin', 2058.27)], first: false)
      duas = described_class.describe([offer('Darwin', 2058.27), offer('Justos', 198.33)], first: false)

      expect(uma).to start_with('Mais uma opção:')
      expect(duas).to start_with('Mais 2 opções:')
    end

    # ENTREGA 13, termo 4 — período genuinamente desconhecido: o preço sai SEM afirmar período
    # nenhum. "no total" só quando o adapter disse `total`; parcelamento sozinho não prova nada aqui,
    # porque quem deriva é o adapter, e este texto só traduz o que veio.
    it 'nao afirma periodo quando o adapter nao soube, nem com parcelamento no payload' do
      texto = described_class.describe(
        [offer('Bp Assinatura', 351.59, 'unknown', { 'count' => 2, 'amount' => 175.8 })], first: true
      )

      expect(texto).to include('*Bp Assinatura* — R$ 351,59')
      expect(texto).not_to include('no total')
      expect(texto.downcase).not_to include('por mês')
      expect(texto.downcase).not_to include('ao ano')
      # A ressalva sai mesmo com parcelamento no payload: sem período, o parcelamento não prova o
      # total, e um "ou 2x de R$ 175,80" sozinho afirmaria por omissão o que o adapter negou.
      expect(texto).to include(Autonomia::Insurance::PremiumText::SEM_BASE)
      expect(texto).not_to include('2x de')
    end

    it 'diz "por mês" para a assinatura mensal, sem ressalva e sem parcelamento' do
      texto = described_class.describe(
        [offer('Bp Assinatura', 298.43, 'monthly', code: '55', motivo: motivo_mensal)], first: true
      )

      expect(texto).to include('*Bp Assinatura* — R$ 298,43 por mês')
      expect(texto).not_to include(Autonomia::Insurance::PremiumText::SEM_BASE)
      expect(texto).not_to include('x de')
    end

    it 'diz "no total" e o parcelamento quando o adapter derivou os dois' do
      texto = described_class.describe(
        [offer('Tokio', 1901.97, 'total', { 'count' => 12, 'amount' => 158.39 })], first: true
      )

      expect(texto).to include('R$ 1.901,97 no total')
      expect(texto).to include('ou 12x de R$ 158,39')
    end

    it 'mantem o aviso de bonus quando ele vem' do
      texto = described_class.describe([offer('Suhai', 4147.70)], first: true, aviso: 'Cotei sem o bônus.')

      expect(texto).to end_with('Cotei sem o bônus.')
    end
  end
end
