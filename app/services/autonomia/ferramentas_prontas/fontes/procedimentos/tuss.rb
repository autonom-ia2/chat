# A tabela 22 da TUSS (procedimentos e eventos em saúde), da ANS, num arquivo do repositório: só os termos ativos,
# com o código de 8 dígitos e o nome (`lib/ferramentas_prontas/procedimentos.csv`, a origem e os termos ao lado).
class Autonomia::FerramentasProntas::Fontes::Procedimentos::Tuss < Autonomia::FerramentasProntas::Fontes::Procedimentos::TabelaLocal
  NOME = 'tuss'.freeze
  ARQUIVO = Rails.root.join('lib/ferramentas_prontas/procedimentos.csv')

  def self.chave(codigo)
    codigo.to_s.delete("^#{Autonomia::FerramentasProntas::Parametro::DIGITOS}")
  end
end
