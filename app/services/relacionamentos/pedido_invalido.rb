# A tela pediu à Lista de Relacionamentos (#2894) um grupo, uma ordem, uma página ou um filtro que não existe. O controller
# responde 422 com a mensagem, em vez de cair num padrão em silêncio.
class Relacionamentos::PedidoInvalido < StandardError; end
