# O AGENTE CONTRATADO DO CATÁLOGO (#3211), no model.
#
# O contratado é um agente comum (`sdr`) com a marca `config['contratado']`: o modelo do catálogo
# (`Autonomia::Agents::Contratados::MODELOS`), o nome do agente e o nome e a apresentação da corretora. A instrução e
# as ferramentas vêm do catálogo a cada turno (`Agent#instrucao_do_sistema`, `Agent#ferramentas_nativas`), e a
# instrução é mantida pela Autonom.ia como a da Lia (`Agent#instrucao_mantida?`).
#
# O que mora aqui:
# - o tipo não muda depois de contratado (o catálogo diz o tipo; trocá-lo desmontaria as guardas);
# - só passa a atender com o acesso à seguradora conferido (`acesso_da_seguradora` em `ok`);
# - a marca e a versão da base semeada não voltam atrás num save comum com cópia velha (o desenho de
#   MarcaDoModeloPronto): quem muda a marca de propósito por save segue mudando.
module Autonomia::Agents::Contratado
  extend ActiveSupport::Concern

  # A versão da base é gravada por `update_all` + `jsonb_set`, fora do save: um save com o `config` lido antes a
  # devolveria à versão velha, e o cron re-semearia a base sem precisar.
  CHAVES_SALVAS = [::Autonomia::Agents::Contratados::MARCA, ::Autonomia::Agents::Contratados::BASE_VERSAO].freeze

  included do
    has_one :acesso_da_seguradora, class_name: 'Autonomia::Agents::AcessoDaSeguradora', foreign_key: :autonomia_agent_id,
                                   inverse_of: :agent, dependent: :destroy

    validate :contratado_fica_no_tipo
    validate :atender_exige_acesso_conferido, on: %i[update ativacao], if: :passa_a_atender?
    before_update :manter_marca_salva, if: :manter_marca_salva?
  end

  def contratado?
    marca_do_catalogo?(config)
  end

  # -> a marca (`modelo`, `nome_agente`, `nome_corretora`, `sobre_corretora`), ou nil para quem não é contratado.
  def marca_do_contratado
    contratado? ? ::Autonomia::Agents::Contratados.marca(self) : nil
  end

  private

  def marca_do_catalogo?(valor)
    marca = valor.to_h[::Autonomia::Agents::Contratados::MARCA]
    marca.is_a?(Hash) && ::Autonomia::Agents::Contratados::MODELOS.key?(marca['modelo'])
  end

  # Vale para quem já é contratado no banco e para quem o save deixaria contratado.
  def contratado_fica_no_tipo
    return unless persisted? && will_save_change_to_agent_type?
    return unless contratado? || marca_do_catalogo?(attribute_in_database(:config))

    errors.add(:agent_type, :invalid)
  end

  # Lê do banco: o acesso pode ter sido conferido depois de o agente ser carregado.
  def atender_exige_acesso_conferido
    return unless contratado?
    return if reload_acesso_da_seguradora&.ok?

    errors.add(:base, I18n.t('autonomia.contratados.acesso_pendente'))
  end

  def manter_marca_salva?
    marca = ::Autonomia::Agents::Contratados::MARCA
    return false unless will_save_change_to_config? && config.to_h.key?(marca)

    attribute_in_database(:config).to_h[marca] == config.to_h[marca]
  end

  def manter_marca_salva
    salvo = self.class.where(id: id).lock.pick(:config).to_h.slice(*CHAVES_SALVAS)
    self.config = config.to_h.except(*CHAVES_SALVAS).merge(salvo)
  end
end
