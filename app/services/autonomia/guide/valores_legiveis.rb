# O que vai ser gravado, em linguagem de gente, para o cartão de confirmação do
# Guia: "Automação: Novo lead · Descrição: Leads do formulário". Sem isso a
# confirmação seria só a frase do modelo, que pode suavizar ou errar um valor —
# e a pessoa confirmaria sem ver o que de fato vai ser gravado.
#
# O identificador da rota entra junto, e isso importa mais do que parece: num
# DELETE o corpo é sempre vazio, então a tela mostrava a frase e o aviso de que
# não tem volta — e NADA sobre qual registro ia sumir. Se o modelo errasse o
# id, a pessoa não tinha como perceber antes de clicar.
#
# Valor composto (as condições de uma automação, uma lista de passos) não vira
# texto aqui: impresso cru, saía `{"values" => [3], ...}` na tela (conta 16,
# 05/10/2026). Ele é contado em `ajustes`, e a tela mostra a prévia da
# automação ou "e mais N ajustes".
class Autonomia::Guide::ValoresLegiveis
  def initialize(account:, acao:, dados:, conferencia:)
    @account = account
    @acao = acao.to_s
    @dados = dados
    @conferencia = conferencia
  end

  def para_tela
    { detalhe: texto, ajustes: ajustes }
  end

  def texto
    alvo = (@dados[:caminho] || {}).to_h.transform_keys(&:to_s)
    textos = alvo.filter_map { |campo, valor| registro_legivel(campo, valor) } +
             @conferencia.valores.filter_map { |campo, valor| campo_legivel(campo, valor) }
    textos.join(' · ').presence
  end

  def ajustes
    @conferencia.valores.values.count { |valor| composto?(valor) }
  end

  private

  def campo_legivel(campo, valor)
    return if composto?(valor)

    texto = valor.is_a?(Array) ? valor.join(', ') : valor.to_s
    "#{rotulo(campo)}: #{texto}" if texto.present?
  end

  def composto?(valor)
    valor.is_a?(Hash) || (valor.is_a?(Array) && valor.any? { |item| item.is_a?(Hash) || item.is_a?(Array) })
  end

  # O registro da rota pelo nome — "Registro: 8" não diz a quem confirma qual
  # automação vai mudar. Só registro desta conta: de outra, fica o número.
  def registro_legivel(campo, valor)
    modelo = modelo_do_registro(campo)
    nome = modelo && nome_do_registro(modelo, valor)
    return "#{rotulo(campo)}: #{valor}" if nome.blank?

    "#{I18n.t("autonomia.guide.records.#{modelo.model_name.i18n_key}", default: rotulo(campo))}: #{nome}"
  end

  # `id` é o registro da própria ação (o modelo vem do formato dela); `inbox_id`
  # e afins, o registro que o nome do campo diz.
  def modelo_do_registro(campo)
    nome = campo == 'id' ? ::Autonomia::Guide::Formatos.para(@acao)&.dig('modelo') : campo.delete_suffix('_id').classify
    modelo = nome.to_s.safe_constantize
    modelo if modelo.is_a?(Class) && modelo < ApplicationRecord && modelo.column_names.include?('account_id')
  end

  def nome_do_registro(modelo, id)
    registro = modelo.find_by(id: id, account_id: @account.id)
    %i[name title].filter_map { |atributo| registro.try(atributo).presence }.first if registro
  end

  # Nome de campo da API vira etiqueta legível, no idioma de quem está olhando.
  # Campo sem tradução aparece com o próprio nome, sem underline: melhor mostrar
  # um nome feio do que esconder o valor que vai ser gravado.
  def rotulo(campo)
    chave = "autonomia.guide.fields.#{campo}"
    return I18n.t(chave) if I18n.exists?(chave)

    campo.to_s.tr('_', ' ').capitalize
  end
end
