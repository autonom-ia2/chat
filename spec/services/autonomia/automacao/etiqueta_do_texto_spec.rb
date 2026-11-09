require 'rails_helper'

# G29 (#2702): o nome do anúncio vira etiqueta pela regra da tela de etiquetas (Label: letras, inclusive acentuadas,
# números, "-" e "_", e duas letras no mínimo). O que a regra não aceita vira "_".
RSpec.describe Autonomia::Automacao::EtiquetaDoTexto do
  it 'transforma nome de anúncio real em etiqueta que o Label aceita', :aggregate_failures do
    casos = {
      'Apartamento Jardim' => 'apartamento_jardim',
      'Black Friday, 50% off' => 'black_friday_50_off',
      'Promoção "Verão" 2026' => 'promoção_verão_2026',
      "Casa d'Água – Lançamento" => 'casa_d_água_lançamento',
      '  -- Lote_7 --  ' => 'lote_7',
      'já-válida' => 'já-válida'
    }

    casos.each do |nome, etiqueta|
      expect(described_class.de(nome)).to eq(etiqueta)
      expect(Label.new(account: build(:account), title: described_class.de(nome))).to be_valid
    end
  end

  it 'não inventa etiqueta quando não sobra nome que o Label aceite', :aggregate_failures do
    expect(described_class.de('%%')).to be_nil
    expect(described_class.de('A')).to be_nil
    expect(described_class.de(nil)).to be_nil
  end
end
