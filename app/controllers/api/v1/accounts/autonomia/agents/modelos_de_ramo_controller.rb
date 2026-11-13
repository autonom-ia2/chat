# #2881 — os modelos de agente prontos por ramo de seguro que a conta pode usar: a tela de escolha lê daqui quais
# cartões mostrar. Só as chaves; os textos dos cartões são da tela. Conta sem o pacote `seguros` ou sem a flag
# `agente_modelos_seguro` recebe a lista vazia (a tela fica como antes). Só leitura; a permissão é a da área de
# Agentes (`autonomia_view`), como a lista de agentes.
class Api::V1::Accounts::Autonomia::Agents::ModelosDeRamoController < Api::V1::Accounts::Autonomia::BaseController
  def index
    render json: { modelos: ::Autonomia::Agents::ModelosDeRamo.liberados(Current.account) }
  end
end
