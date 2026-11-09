# "ENDEREÇO E TELEFONE" DO AGENTE (#1479, #2723): `config['atendimento'] = { 'endereco' => texto, 'telefone' => E.164 ou '' }`,
# o bloco da página do agente.
#
# A REGRA MORA NO MODEL, para valer em todo caminho que grava com validação: a API (`AgentsController#create`/`update`,
# que mesclam o config), o Construtor (`apply_builder_config!`, que mescla e chama `update!`), a volta de versão e
# qualquer `update!`. Os caminhos que gravam sem validação (`update_columns` da base, `jsonb_set` do Revisor e do
# material) só tocam a chave deles e preservam esta. Só confere quando o atendimento MUDA: salvar outra coisa nunca
# trava por ele.
#
# - endereço: texto livre do dono, sem espaço sobrando, até MAX_ENDERECO;
# - telefone: vazio, ou "+" e dígitos que o `TelephoneNumber` aceita (o mesmo E.164 do `contact_phone` da página e do
#   convidado da reunião). "+55 (11) 94000-1234" vira "+5511940001234"; sem "+", não passa.
# - outras chaves dentro do atendimento saem.
#
# Quem usa: a instrução do agente (`Tools::Native::EnderecoETelefone`) e o cartão de contato (`CartaoDaPagina`), só com
# a flag `agentes_enviar_local_e_contato`. O endereço nunca vira mapa.
module Autonomia::Agents::DadosDoAtendimento
  extend ActiveSupport::Concern

  CHAVE = 'atendimento'.freeze
  MAX_ENDERECO = 300

  included do
    before_validation :normalizar_atendimento, if: :atendimento_mudou?
    validate :atendimento_valido, if: :atendimento_mudou?
  end

  # O par gravado, sempre com as duas chaves em texto ('' quando falta).
  def dados_do_atendimento
    valor = config.to_h[CHAVE]
    valor = {} unless valor.is_a?(Hash)
    { 'endereco' => valor['endereco'].to_s, 'telefone' => valor['telefone'].to_s }
  end

  private

  def atendimento_bruto
    config.to_h.stringify_keys[CHAVE]
  end

  def atendimento_mudou?
    atendimento_bruto != config_in_database.to_h[CHAVE]
  end

  def normalizar_atendimento
    bruto = atendimento_bruto
    return unless bruto.is_a?(Hash)

    dados = bruto.stringify_keys
    self.config = config.to_h.stringify_keys.merge(
      CHAVE => { 'endereco' => dados['endereco'].to_s.squish, 'telefone' => telefone_normalizado(dados['telefone']) }
    )
  end

  # "+55 (11) 94000-1234" -> "+5511940001234". Sem "+", fica como veio (e a validação recusa).
  def telefone_normalizado(valor)
    texto = valor.to_s.strip
    return texto unless texto.start_with?('+')

    ::Autonomia::Agents::Tools::Native::CartaoDaPagina.telefone(texto)
  end

  def atendimento_valido
    bruto = atendimento_bruto
    return if bruto.nil?
    return errors.add(:base, I18n.t('autonomia.agents.atendimento.invalido')) unless bruto.is_a?(Hash)

    errors.add(:base, I18n.t('autonomia.agents.atendimento.endereco_longo', maximo: MAX_ENDERECO)) if endereco_longo?(bruto)
    errors.add(:base, I18n.t('autonomia.agents.atendimento.telefone_invalido')) unless telefone_valido?(bruto['telefone'].to_s)
  end

  def endereco_longo?(bruto)
    bruto['endereco'].to_s.length > MAX_ENDERECO
  end

  def telefone_valido?(telefone)
    telefone.empty? || (telefone.start_with?('+') && TelephoneNumber.valid?(telefone))
  end
end
