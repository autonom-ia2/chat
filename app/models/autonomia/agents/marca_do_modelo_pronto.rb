# A MARCA DO MODELO PRONTO DE RAMO CONTRA O SAVE COMUM (#2881).
#
# O agente que nasceu de um modelo pronto guarda no `config` a marca do modelo (`modelo_pronto`: as listas de perguntas
# e de documentos como o dono as deixou) e as ferramentas que saem dela (`ferramentas_sugeridas`, `ferramentas_tambem`).
# Quem escreve essas chaves é a edição do dono (`ModelosDeRamo::Edicao`), com o agente travado.
#
# A CORRIDA com o save comum (painel, API): ele grava o `config` inteiro que leu no começo. Se uma edição do dono entrou
# no meio, a lista velha voltaria em silêncio. Todo save que muda o `config` sem mexer na marca relê as três chaves, sob
# a trava da linha (a mesma de TrocaDaBase e de ConfigDoMaterial), e mantém o que está salvo. Quem muda a marca de
# propósito por save (o nascimento do rascunho, o fechamento do Construtor) segue mudando.
#
# Só para o agente que tem a marca: os demais salvam como antes, sem a leitura sob trava.
module Autonomia::Agents::MarcaDoModeloPronto
  extend ActiveSupport::Concern

  MARCA = 'modelo_pronto'.freeze
  CHAVES = [MARCA, 'ferramentas_sugeridas', 'ferramentas_tambem'].freeze

  included do
    before_update :manter_modelo_pronto_salvo, if: :manter_modelo_pronto_salvo?
  end

  private

  def manter_modelo_pronto_salvo?
    return false unless will_save_change_to_config? && config.to_h.key?(MARCA)

    attribute_in_database(:config).to_h[MARCA] == config.to_h[MARCA]
  end

  def manter_modelo_pronto_salvo
    salvo = self.class.where(id: id).lock.pick(:config).to_h.slice(*CHAVES)
    self.config = config.to_h.except(*CHAVES).merge(salvo)
  end
end
