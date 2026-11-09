# Os valores fechados da receita. Saiu de `Valores`, que segue sendo a porta (`Valores::FECHADOS`, `Valores.fechado`),
# quando ela passou do tamanho no merge da main com a G49 (#2414).
module Autonomia::Automacao::Valores::Fechados
  # Valores fechados (#2496): fora destas opções e destes operadores a condição nunca casa, e a automação falharia em
  # silêncio. O salvar recusa o resto; o editor mostra só isto.
  LISTA = {
    'mensagem.tipo' => { 'opcoes' => %w[recebida enviada nota], 'operadores' => %w[igual diferente] },
    'mensagem.privada' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'mensagem.primeira' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'mensagem.tem_anexo' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'conversa.iniciada_por' => { 'opcoes' => %w[cliente equipe], 'operadores' => %w[igual diferente] },
    'conversa.cliente_respondeu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'conversa.equipe_respondeu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'conversa.responsavel_respondeu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'gatilho.repetiu' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'card.origem' => { 'opcoes' => ::Autonomia::Automacao::OrigemDoCard::GRUPOS, 'operadores' => %w[igual diferente] },
    'card.tem_reuniao_marcada' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'contato.tem_reuniao_marcada' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'envio.situacao' => { 'opcoes' => ::Autonomia::Automacao::Envio::SITUACOES.values, 'operadores' => %w[igual diferente] }
  }.merge(::Autonomia::Automacao::Ausencia::FECHADOS).freeze
end
