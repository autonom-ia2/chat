# O CATÁLOGO DAS FERRAMENTAS PRONTAS (#2858). Fica no código: quem decide que uma fonte existe, com que prazo, reserva,
# cache e limite, somos nós; a conta só escolhe incluir.
#
# COMO ADICIONAR UMA FONTE (F1 em diante), sem mexer no resto:
#   1. um arquivo em `fontes/<nome>.rb` com o módulo `Fontes::<Nome>`: os provedores (subclasses de `Provedor`, com
#      `NOME`, `HOST` e `consultar`), os parâmetros (`Parametro`, sempre normalizados) e a `FONTE` com as consultas;
#   2. a fonte nesta lista;
#   3. o spec do adaptador: resposta boa, prazo, reserva e erro (ver `spec/services/autonomia/ferramentas_prontas`);
#   4. o host novo no teto global (`TetoDoProvedor::TETOS`, se o termo da fonte der número) e os termos em
#      `docs/ferramentas-prontas/termos-das-fontes.md`. Fonte de fase nova: `flag:` com a flag da fase.
# Parâmetro de texto livre que vai na URL: `codificar` (o resto é dígito ou opção da lista). Provedor sem rede: `HOST = nil`.
# A execução, o cache, o contador, o limite, o corte, o log e o caminho em segundo plano já valem para ela.
module Autonomia::FerramentasProntas::Catalogo
  module_function

  def todas
    [*fundacao_e_lote1, *lote2, *premium]
  end

  def fundacao_e_lote1
    [
      Autonomia::FerramentasProntas::Fontes::Cep::FONTE,
      Autonomia::FerramentasProntas::Fontes::Cnpj::FONTE,
      Autonomia::FerramentasProntas::Fontes::Fipe::FONTE,
      # F1 (flag `agente_ferramentas_prontas_consultas`)
      Autonomia::FerramentasProntas::Fontes::Cpf::FONTE,
      Autonomia::FerramentasProntas::Fontes::Feriados::FONTE,
      Autonomia::FerramentasProntas::Fontes::BancoCentral::FONTE,
      Autonomia::FerramentasProntas::Fontes::Cidades::FONTE,
      Autonomia::FerramentasProntas::Fontes::Ddd::FONTE,
      Autonomia::FerramentasProntas::Fontes::Localizacao::FONTE,
      Autonomia::FerramentasProntas::Fontes::Bancos::FONTE
    ]
  end

  # F4 (flag `agente_ferramentas_prontas_lote2`)
  def lote2
    [
      Autonomia::FerramentasProntas::Fontes::Hospitais::FONTE,
      Autonomia::FerramentasProntas::Fontes::Procedimentos::FONTE,
      Autonomia::FerramentasProntas::Fontes::Doencas::FONTE,
      Autonomia::FerramentasProntas::Fontes::Ncm::FONTE,
      Autonomia::FerramentasProntas::Fontes::ComprasGoverno::FONTE,
      Autonomia::FerramentasProntas::Fontes::Estacoes::FONTE,
      Autonomia::FerramentasProntas::Fontes::Chuva::FONTE,
      Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::FONTE,
      Autonomia::FerramentasProntas::Fontes::CorretorSusep::FONTE
    ]
  end

  # F7 (flag `agente_ferramentas_prontas_premium`): as consultas pagas à BigDataCorp, um card por tema.
  def premium
    [
      Autonomia::FerramentasProntas::Fontes::Premium::Certidoes::FONTE,
      Autonomia::FerramentasProntas::Fontes::Premium::RaioX::FONTE,
      Autonomia::FerramentasProntas::Fontes::Premium::Pessoa::FONTE,
      Autonomia::FerramentasProntas::Fontes::Premium::Placa::FONTE,
      Autonomia::FerramentasProntas::Fontes::Premium::RiscoEndereco::FONTE,
      Autonomia::FerramentasProntas::Fontes::Premium::ImovelRural::FONTE,
      Autonomia::FerramentasProntas::Fontes::Premium::ContatoEmpresa::FONTE
    ]
  end

  def chaves
    todas.map(&:chave)
  end

  # As chaves que a vitrine e o Construtor podem oferecer (fora as de uso interno).
  def chaves_da_vitrine
    todas.select(&:na_vitrine?).map(&:chave)
  end

  def buscar(chave)
    todas.find { |fonte| fonte.chave == chave.to_s }
  end
end
