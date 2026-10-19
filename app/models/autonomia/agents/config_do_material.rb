# #1426 (tema 4b) — as chaves do `config` do agente que o SISTEMA escreve para o material: as conferências entre
# materiais (`conferencia_da_base`: contradições, duplicados mantidos) e o autoteste (`autoteste`). Ninguém as escreve
# pela API (o controller as tira do que chega, RESERVED_CONFIG_KEYS).
#
# A CORRIDA: um save do agente (painel, API, Construtor, voltar versão) grava o jsonb `config` inteiro com o que leu no
# começo. Um resultado do autoteste gravado no meio seria apagado pela versão velha. Por isso:
# - toda escrita destas chaves é atômica, no próprio UPDATE (jsonb_set), e a que depende do valor atual lê sob a trava
#   da linha (`alterar_chave_do_material!`);
# - todo save que muda o `config` relê, sob a mesma trava (SELECT … FOR UPDATE, dentro da transação do save), o valor
#   salvo destas chaves e o mantém. Uma escrita do sistema que chega durante o save espera a trava e entra depois.
module Autonomia::Agents::ConfigDoMaterial
  extend ActiveSupport::Concern

  CHAVES = %w[conferencia_da_base autoteste].freeze

  included do
    before_update :manter_chaves_do_material, if: :manter_chaves_do_material?
  end

  class_methods do
    # Grava `valor` em `chave`, só nela, num UPDATE só. `onde` (opcional) é uma guarda a mais no mesmo UPDATE (ex.: a
    # rodada do autoteste ainda é a vigente). true se gravou.
    def gravar_chave_do_material!(agent_id, chave, valor, onde: nil)
      raise ArgumentError, "chave fora do material: #{chave}" unless CHAVES.include?(chave)

      escopo = where(id: agent_id)
      escopo = escopo.where(onde) if onde
      escopo.update_all(["config = jsonb_set(COALESCE(config, '{}'::jsonb), ?::text[], ?::jsonb, true), updated_at = ?", # rubocop:disable Rails/SkipsModelValidations
                         "{#{chave}}", valor.to_json, Time.current]) == 1
    end
  end

  # O valor SALVO (lido do banco): o objeto em memória pode ser de antes de uma escrita atômica.
  def chave_do_material(chave)
    raise ArgumentError, "chave fora do material: #{chave}" unless CHAVES.include?(chave)

    self.class.where(id: id).pick(Arel.sql("config -> #{self.class.connection.quote(chave)}"))
  end

  # Lê o valor atual de `chave` sob a trava da linha, passa uma cópia ao bloco e grava o que ele devolver (nil: não
  # grava). Devolve o valor que ficou.
  def alterar_chave_do_material!(chave)
    self.class.transaction do
      atual = self.class.where(id: id).lock.pick(:config).to_h[chave]
      novo = yield(atual.deep_dup)
      if novo.nil?
        atual
      else
        self.class.gravar_chave_do_material!(id, chave, novo)
        novo
      end
    end
  end

  private

  # Só na Fase 2 (onde as chaves existem): fora dela, o save fica byte a byte o da main, sem a leitura sob trava.
  def manter_chaves_do_material?
    will_save_change_to_config? && Autonomia::Agents::Fase2.ligada?(account)
  end

  def manter_chaves_do_material
    salvo = self.class.where(id: id).lock.pick(:config).to_h.slice(*CHAVES)
    self.config = config.to_h.except(*CHAVES).merge(salvo)
  end
end
