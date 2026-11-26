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
    ::Carteira::Pdf::SO_NA_TELA_DO_GUIA,
    ::Autonomia::Agents::SourceFile::SO_NA_TELA_DO_GUIA,
    # #2899 (E6.5 e E6.6): ler e guardar o seguro de outra corretora, apagá-lo, escrever o seguro em palavras simples
    # (chamada paga) e mandá-lo ao cliente.
    ::Carteira::DeFora::SO_NA_TELA_DO_GUIA,
    ::Carteira::Palavras::SO_NA_TELA_DO_GUIA,
    # #2900 (E7): buscar os seguros no Agger, buscar de novo e ligar a busca de todo dia (que passa a gravar sozinha).
    ::Carteira::Conector::SO_NA_TELA_DO_GUIA,
    # #2901 (E8): mandar a proposta de renovação ao cliente é o clique de "Enviar" no card.
    ::Carteira::Cotacao::SO_NA_TELA_DO_GUIA,
    # #3211: o login do corretor na seguradora do agente contratado (a senha não passa pela conversa do Guia).
    ::Autonomia::Agents::AcessoDaSeguradora::SO_NA_TELA_DO_GUIA
  ).freeze
end
