# O CATÁLOGO DAS FERRAMENTAS PRONTAS (#2858). Fica no código: quem decide que uma fonte existe, com que prazo, reserva,
# cache e limite, somos nós; a conta só escolhe incluir.
#
# COMO ADICIONAR UMA FONTE (F1 em diante), sem mexer no resto:
#   1. um arquivo em `fontes/<nome>.rb` com o módulo `Fontes::<Nome>`: os provedores (subclasses de `Provedor`, com
#      `NOME`, `HOST` e `consultar`), os parâmetros (`Parametro`, sempre normalizados) e a `FONTE` com as consultas;
#   2. a fonte nesta lista;
#   3. o spec do adaptador: resposta boa, prazo, reserva e erro (ver `spec/services/autonomia/ferramentas_prontas`).
# A execução, o cache, o contador, o limite, o corte, o log e o caminho em segundo plano já valem para ela.
module Autonomia::FerramentasProntas::Catalogo
  module_function

  def todas
    [
      Autonomia::FerramentasProntas::Fontes::Cep::FONTE,
      Autonomia::FerramentasProntas::Fontes::Cnpj::FONTE,
      Autonomia::FerramentasProntas::Fontes::Fipe::FONTE
    ]
  end

  def chaves
    todas.map(&:chave)
  end

  def buscar(chave)
    todas.find { |fonte| fonte.chave == chave.to_s }
  end
end
