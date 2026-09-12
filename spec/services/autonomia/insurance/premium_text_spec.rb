require 'rails_helper'

# O VALOR VIRA FRASE, e só o adapter decide o que o valor é (critério 5.5; entrega 13). Aqui não se
# infere período de nada: `basis == 'total'` diz "no total", `basis == 'monthly'` diz "por mês",
# qualquer outra coisa não diz período.
RSpec.describe Autonomia::Insurance::PremiumText do
  it 'diz "no total" so quando o adapter disse total' do
    expect(described_class.new('amount' => 980.0, 'basis' => 'total').resumo).to eq('R$ 980,00 no total')
    expect(described_class.new('amount' => 980.0, 'basis' => 'unknown').resumo).to eq('R$ 980,00')
    expect(described_class.new('amount' => 980.0).resumo).to eq('R$ 980,00')
  end

  # ASSINATURA MENSAL (11/09/2026, noite): o PDF do comparativo do portal imprimia "R$ 298,43 por mês"
  # para a Bp Assinatura enquanto o cliente lia aqui a ressalva de valor sem período. O marcador é o
  # `packageType=1` do portal, lido pelo adapter e nomeado em `basis_evidence`; aqui só se traduz o
  # `monthly` que ele manda — e "por mês" tem período, então não dispara a ressalva.
  it 'diz "por mês" quando o adapter disse monthly, e isso e periodo' do
    texto = described_class.new('amount' => 298.43, 'basis' => 'monthly',
                                'basis_evidence' => "packageType=1 (assinatura mensal: o relatorio do portal imprime 'por mes')")

    expect(texto.resumo).to eq('R$ 298,43 por mês')
    expect(texto.indefinido?).to be(false)
    expect(texto.mensal?).to be(true)
  end

  # A assinatura não tem parcelamento (`parcelamentos=[]`) e tem período: sem ressalva e sem linha de
  # parcelas, o item sai só com a primeira linha.
  it 'mensal sem parcelamento nao tem linha de baixo: nem ressalva, nem parcelas' do
    expect(described_class.new('amount' => 298.43, 'basis' => 'monthly').detalhe).to be_nil
  end

  it 'nao deduz total do parcelamento: quem deriva e o adapter' do
    texto = described_class.new('amount' => 980.0, 'basis' => 'unknown',
                                'installments' => { 'count' => 2, 'amount' => 490.0 })

    expect(texto.resumo).to eq('R$ 980,00')
    expect(texto.indefinido?).to be(true)
  end

  # Sem período, o detalhe e a RESSALVA, nao o parcelamento: "ou 2x de R$ 490,00" sozinho diria por
  # omissao que 980 e o total, e o registro no handle ficaria dizendo "sem periodo" para uma frase
  # que o cliente nunca ouviu.
  it 'sem periodo, a ressalva vem antes do parcelamento' do
    texto = described_class.new('amount' => 980.0, 'basis' => 'unknown',
                                'installments' => { 'count' => 2, 'amount' => 490.0 })

    expect(texto.detalhe).to eq(described_class::SEM_BASE)
  end

  it 'poe o parcelamento na linha de baixo quando o adapter o derivou' do
    texto = described_class.new('amount' => 1901.97, 'basis' => 'total',
                                'installments' => { 'count' => 12, 'amount' => 158.39 })

    expect(texto.detalhe).to eq('ou 12x de R$ 158,39')
    expect(texto.indefinido?).to be(false)
  end

  it 'sem periodo, a ressalva e a linha de baixo, e o motivo e o do adapter' do
    texto = described_class.new('amount' => 351.59, 'basis' => 'unknown',
                                'basis_evidence' => 'parcelamentos=[] (vazio)')

    expect(texto.detalhe).to eq(described_class::SEM_BASE)
    expect(texto.motivo).to eq('parcelamentos=[] (vazio)')
  end

  it 'sem motivo do adapter, o motivo descreve o que veio em vez de inventar' do
    expect(described_class.new('amount' => 1.0).motivo).to eq('basis=nil sem basis_evidence')
    expect(described_class.new('amount' => 1.0, 'basis' => 'unknown').motivo).to eq('basis="unknown" sem basis_evidence')
  end

  it 'nao parcela uma mensalidade, mesmo que venha installments junto de monthly' do
    # O adapter não manda parcelamento com `monthly` (assinatura vem com `parcelamentos=[]`); se
    # mandar, "por mês" e "ou 10x de" na mesma oferta seriam contradição. Só o total parcela.
    texto = described_class.new('amount' => 298.43, 'basis' => 'monthly',
                                'installments' => { 'count' => 10, 'amount' => 29.84 })
    expect(texto.resumo).to eq('R$ 298,43 por mês')
    expect(texto.detalhe).to be_nil
  end

end
