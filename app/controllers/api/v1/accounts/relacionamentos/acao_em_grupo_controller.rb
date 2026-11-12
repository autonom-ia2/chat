# Base das ações em grupo da Lista nova de Relacionamentos (#2894): criar cards, etiquetar e apagar as pessoas marcadas.
# Cada ação confere a permissão que a tela de hoje já pede para ela, além da de ver os contatos (BaseController).
class Api::V1::Accounts::Relacionamentos::AcaoEmGrupoController < Api::V1::Accounts::Relacionamentos::BaseController
  # O corpo chega como a tela manda, sem o envelope do Rails: a chave a mais seria um parâmetro que a ação não conhece.
  wrap_parameters false

  private

  # O permit descarta em silêncio a chave que não conhece e a que chega no formato errado (pessoa_ids=7, funil_id[]=1):
  # a ação seguiria pela metade. Aqui as duas respondem 422. `permitido` é o params.permit da ação; os CAMPOS, as chaves
  # que ela aceita. Devolve os campos da ação (nil no que não veio), para o serviço dela.
  def corpo(permitido)
    recebidas = request.parameters.keys - request.path_parameters.keys.map(&:to_s)
    desconhecida = (recebidas - self.class::CAMPOS).first
    recusar("parâmetro desconhecido: #{desconhecida}") if desconhecida
    torta = (recebidas - permitido.to_h.keys).first
    recusar("#{torta} em formato inválido") if torta
    self.class::CAMPOS.to_h { |campo| [campo.to_sym, permitido[campo]] }
  end

  def de_quem_pede
    { account: Current.account, user: Current.user }
  end
end
