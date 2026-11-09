# "ENDEREÇO E TELEFONE" DO AGENTE (#1479, #2723): `config['atendimento'] = { 'endereco' => texto, 'telefone' => E.164 ou '' }`,
# o bloco da página do agente.
#
# A REGRA MORA NO MODEL, para valer em todo caminho que grava com validação: a API (`AgentsController#create`/`update`,
# que mesclam o config), o Construtor (`apply_builder_config!`, que mescla e chama `update!`), a volta de versão e
# qualquer `update!`. Os caminhos que gravam sem validação (`update_columns` da base, `jsonb_set` do Revisor e do
# material) só tocam a chave deles e preservam esta. Só confere quando o atendimento MUDA: salvar outra coisa nunca
# trava por ele.
#
# - endereço: texto livre do dono, sem espaço sobrando, até MAX_ENDERECO; erro no atributo `endereco`;
# - telefone: vazio, ou "+" e só dígitos, espaço, parênteses, hífen e ponto, com 8 a 15 dígitos (a regra do cartão de
#   contato, `RichMessages::Types::Contact`) que o `TelephoneNumber` aceita (o mesmo do `contact_phone` da página).
#   "+55 (11) 94000-1234" vira "+5511940001234". Erro no atributo `telefone`: o 422 (`render_record_invalid`) devolve
#   `attributes`, e a tela põe o aviso no campo certo pelo atributo, nunca pelo texto;
# - campo que não é texto (nem nil): `invalido`, na base. Outras chaves dentro do atendimento saem.
#
# Quem usa: a instrução do agente (`Tools::Native::EnderecoETelefone`) e o cartão de contato (`CartaoDaPagina`), só com
# a flag `agentes_enviar_local_e_contato`. O endereço nunca vira mapa.
module Autonomia::Agents::DadosDoAtendimento
  extend ActiveSupport::Concern

  CHAVE = 'atendimento'.freeze
  MAX_ENDERECO = 300
  CAMPOS = %w[endereco telefone].freeze
  # Além do "+" do começo, o que o telefone aceita (o mesmo do cartão de contato, `RichMessages::Types::Contact`).
  CARACTERES_DO_TELEFONE = '0123456789 ().-'.freeze

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

  # Os valores dos atributos `telefone` e `endereco` do erro (o `errors.add` lê o valor do atributo pelo nome). Só
  # leitura, como gravado (ou como veio, antes de salvar).
  def telefone
    valor_do_atendimento('telefone')
  end

  def endereco
    valor_do_atendimento('endereco')
  end

  private

  def valor_do_atendimento(campo)
    bruto = atendimento_bruto
    bruto.is_a?(Hash) ? bruto.stringify_keys[campo] : nil
  end

  def atendimento_bruto
    config.to_h.stringify_keys[CHAVE]
  end

  def atendimento_mudou?
    atendimento_bruto != config_in_database.to_h[CHAVE]
  end

  def normalizar_atendimento
    bruto = atendimento_bruto
    return unless campos_em_texto?(bruto)

    dados = bruto.stringify_keys
    self.config = config.to_h.stringify_keys.merge(
      CHAVE => { 'endereco' => dados['endereco'].to_s.squish, 'telefone' => telefone_normalizado(dados['telefone']) }
    )
  end

  # Um par de campos, cada um texto ou nil (nil vira vazio). Número, lista ou outro objeto: `invalido`.
  def campos_em_texto?(bruto)
    bruto.is_a?(Hash) && bruto.stringify_keys.values_at(*CAMPOS).all? { |valor| valor.nil? || valor.is_a?(String) }
  end

  # "+55 (11) 94000-1234" -> "+5511940001234". Fica como veio (e a validação recusa) quando não começa com "+" ou traz
  # caractere fora de dígito, espaço, parênteses, hífen e ponto.
  def telefone_normalizado(valor)
    texto = valor.to_s.strip
    return texto unless caracteres_de_telefone?(texto)

    ::Autonomia::Agents::Tools::Native::CartaoDaPagina.telefone(texto)
  end

  def caracteres_de_telefone?(texto)
    texto.start_with?('+') && texto.delete_prefix('+').each_char.all? { |caractere| CARACTERES_DO_TELEFONE.include?(caractere) }
  end

  def atendimento_valido
    bruto = atendimento_bruto
    return if bruto.nil?
    return errors.add(:base, I18n.t('autonomia.agents.atendimento.invalido')) unless campos_em_texto?(bruto)

    errors.add(:endereco, :invalid, message: mensagem_do_endereco_longo) if endereco_longo?(bruto)
    return if telefone_valido?(bruto['telefone'].to_s)

    errors.add(:telefone, :invalid, message: I18n.t('autonomia.agents.atendimento.telefone_invalido'))
  end

  def mensagem_do_endereco_longo
    I18n.t('autonomia.agents.atendimento.endereco_longo', maximo: MAX_ENDERECO)
  end

  def endereco_longo?(bruto)
    bruto['endereco'].to_s.length > MAX_ENDERECO
  end

  # Vazio, ou o "+" e os dígitos que servem para o cartão de contato (`RichMessages::Types::Contact`: 8 a 15 dígitos) e
  # que o `TelephoneNumber` aceita.
  def telefone_valido?(telefone)
    return true if telefone.empty?
    return false unless caracteres_de_telefone?(telefone)

    cartao = { 'type' => 'contact', 'name' => CHAVE, 'phone' => telefone }
    ::RichMessages::Types::Contact.new(cartao).error_for('').nil? && TelephoneNumber.valid?(telefone)
  end
end
