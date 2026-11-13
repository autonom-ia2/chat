# Para os objetos do leitor de apólice que guardam dado de cliente (texto de página, CPF/CNPJ, caminho do arquivo) ou
# o cliente de IA, que leva a credencial da conta (E6, #2899).
#
# O `inspect` padrão do Ruby e o `as_json` do ActiveSupport mostram as variáveis de instância: um `pp`, um objeto
# dentro de uma mensagem de erro ou um `to_json` levariam a chave e o texto da apólice para o log. Quem inclui este
# módulo mostra só o nome da classe. A classe que tem algo seguro a mostrar (uma contagem, o número da página) define
# o seu próprio `inspect` ou `as_json` depois de incluir.
module Carteira::Leitor::Reservado
  def inspect
    "#<#{self.class.name}>"
  end

  def as_json(*)
    { 'classe' => self.class.name }
  end
end
