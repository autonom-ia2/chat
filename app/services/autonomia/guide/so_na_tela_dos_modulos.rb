# O que cada módulo do fork declara que o Guia não faz por ninguém, só a tela (`Guide::Acoes::SO_NA_TELA`). Cada módulo
# guarda a própria lista ao lado do código que ela protege, com o motivo; aqui elas se juntam. Módulo novo entra nesta
# lista, e não em mais uma linha da classe das ações (#2897: ela chegou ao teto de tamanho).
module Autonomia::Guide::SoNaTelaDosModulos
  ACOES = {}.merge(
    # #2894: apagar as pessoas marcadas na Lista de Relacionamentos é excluir contato, em lote.
    ::Relacionamentos::Apagar::SO_NA_TELA_DO_GUIA,
    # #2858 F7: o Experimente da vitrine de ferramentas prontas e a leitura do pedido dele.
    ::Autonomia::FerramentasProntas::SO_NA_TELA_DO_GUIA,
    # #2897: guardar e tirar o PDF de um seguro é envio de arquivo, e o link do PDF é assinado.
    ::Carteira::Pdf::SO_NA_TELA_DO_GUIA
  ).freeze
end
