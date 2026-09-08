require 'rails_helper'

# O TEXTO DO PREÇO É ESCRITO POR CÓDIGO, e não pelo modelo — preço redigido por modelo é preço que
# ele pode arredondar ou trocar de seguradora. O custo dessa escolha é que a instrução ("negrito no
# nome e no valor") não alcança aqui, e ninguém testava o formato: em 08/09/2026 o cliente leu
# `Usebens: R$ 2837,70` numa lista corrida, sem negrito, sem milhar, com a mesma ressalva repetida
# por extenso em toda mensagem.
RSpec.describe Autonomia::Insurance::QuoteOffers do
  def offer(name, amount, basis = 'total', installments = nil)
    { 'insurer' => { 'name' => name },
      'premium' => { 'amount' => amount, 'basis' => basis, 'installments' => installments } }
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
      expect(texto).not_to include(Autonomia::Insurance::PremiumText::SEM_SIGNIFICADO)
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

    it 'concorda em numero com as ofertas do lote' do
      uma = described_class.describe([offer('Darwin', 2058.27)], first: false)
      duas = described_class.describe([offer('Darwin', 2058.27), offer('Justos', 198.33)], first: false)

      expect(uma).to start_with('Mais uma opção:')
      expect(duas).to start_with('Mais 2 opções:')
    end

    it 'mantem o aviso de bonus quando ele vem' do
      texto = described_class.describe([offer('Suhai', 4147.70)], first: true, aviso: 'Cotei sem o bônus.')

      expect(texto).to end_with('Cotei sem o bônus.')
    end
  end
end
