# As telas para onde o Guia pode levar a pessoa (issue #590).
#
# Sai do mesmo mapa que o modelo lê (`guia-produto.md`, gerado do roteador do
# painel): cada fluxo diz a rota e o endereço dela. Do endereço sai o que a tela
# exige — `/settings/inboxes/:inboxId/:tab?` pede o id da caixa e aceita a aba.
#
# Era isso que faltava: o botão só levava a tela que abre com o id da conta, e
# 39 dos 163 fluxos apontam para UMA caixa, UMA conversa, UM agente. Agora quem
# escolhe a tela é o modelo, que leu a conta e sabe os ids; aqui só se confere
# que a tela existe e que o endereço fecha.
#
# A permissão não mora aqui. Quem clica passa pela guarda da rota no painel, e a
# tela busca os dados com a permissão dela — como se tivesse clicado no menu.
class Autonomia::Guide::Telas
  class Recusada < StandardError; end

  # O id da conta é da sessão, nunca do modelo: o painel sempre põe o da conta
  # aberta, e aceitar outro seria abrir a porta para outra conta pelo botão.
  DA_SESSAO = 'accountId'.freeze
  MAX_VALOR = 100

  def self.padrao
    @padrao ||= new(::Autonomia::Guide::Seed::KB_PATH.read)
  end

  def initialize(mapa)
    @telas = ler(mapa)
  end

  def nomes
    @telas.keys
  end

  # Devolve o destino que a tela recebe, ou levanta `Recusada` com a frase que
  # o modelo lê para corrigir o pedido — ou perguntar à pessoa o que falta.
  #
  # `permissoes` é `AccountUser#permissions` de quem pergunta. A regra é a do
  # painel (`hasPermissions`): a tela abre se ela tem um dos papéis da tela.
  # Medido na bateria real de 22/09/2026: sem isso, o agente comum recebia o
  # botão das configurações da caixa, e o clique dava na guarda da rota.
  def destino(nome, parametros, destaque = nil, permissoes: nil)
    tela = @telas[nome.to_s]
    raise Recusada, "A tela \"#{nome}\" não está no mapa. Use a rota de um dos fluxos que você recebeu." if tela.nil?

    conferir_perfil(tela, permissoes)
    valores = limpos(parametros)
    conferir_obrigatorios(tela, valores)

    { route_name: nome.to_s, params: valores.slice(*(tela[:obrigatorios] + tela[:opcionais])),
      highlight: tela[:destaques].include?(destaque.to_s) ? destaque.to_s : nil }
  end

  # As telas de UM registro que moram logo abaixo desta no endereço: a lista de
  # agentes (`/agents`) tem o painel de um agente (`/agents/:agentId`). Medido na
  # bateria real de 22/09/2026: pedindo "o robô de renovação", o modelo parava na
  # lista, sem saber que o painel dele existia. Sai do mapa, não de uma lista minha.
  def de_um_registro(nome)
    tela = @telas[nome.to_s]
    return [] if tela.nil?

    abaixo = "#{tela[:endereco]}/:"
    @telas.filter_map do |outro, dados|
      "#{outro} (#{dados[:obrigatorios].join(', ')})" if dados[:endereco].start_with?(abaixo)
    end
  end

  private

  def conferir_perfil(tela, permissoes)
    return if permissoes.nil? || tela[:papeis].empty? || tela[:papeis].intersect?(permissoes)

    raise Recusada, 'Essa tela não abre para o perfil de quem está perguntando. Não mostre o botão: ' \
                    'explique que quem administra a conta faz isso.'
  end

  def conferir_obrigatorios(tela, valores)
    faltam = tela[:obrigatorios] - valores.keys
    return if faltam.empty?

    raise Recusada, "Para abrir essa tela falta: #{faltam.join(', ')}. Leia a conta para achar o id, " \
                    'ou pergunte à pessoa qual é.'
  end

  def limpos(parametros)
    parametros.to_h.each_with_object({}) do |(chave, valor), limpo|
      chave = chave.to_s
      next if chave == DA_SESSAO
      next unless valor.is_a?(String) || valor.is_a?(Integer)

      texto = valor.to_s.strip
      limpo[chave] = texto if texto.present? && texto.length <= MAX_VALOR
    end
  end

  # Um bloco por fluxo, cada campo como item de lista — o formato que
  # `scripts/guide-map/build.mjs` escreve:
  #   - rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
  #   - highlight: `settings-add-label`
  # Vários fluxos apontam para a mesma tela; os destaques de todos valem para ela.
  def ler(mapa)
    mapa.split("\n### ").drop(1).each_with_object({}) do |bloco, telas|
      nome, endereco = campo(bloco, 'rota').to_s.delete('`').split(' - ', 2).map(&:strip)
      next if nome.blank? || endereco.blank?

      tela = telas[nome] ||= parametros_do(endereco).merge(destaques: [], papeis: papeis_do(campo(bloco, 'gate')))
      destaque = campo(bloco, 'highlight').to_s.delete('`').strip
      tela[:destaques] |= [destaque] if destaque.present?
    end
  end

  # O gate que o gerador escreve a partir do `meta.permissions` da rota:
  #   feature flag `inbox_management`; papel `administrator` ou `inbox_view`
  # Sem `papel`, a tela não restringe perfil.
  MARCA_DO_PAPEL = 'papel '.freeze

  def papeis_do(gate)
    trecho = gate.to_s.split(';').map(&:strip).find { |parte| parte.start_with?(MARCA_DO_PAPEL) }
    return [] if trecho.nil?

    trecho.delete_prefix(MARCA_DO_PAPEL).split(' ou ').map { |papel| papel.delete('`').strip }.reject(&:empty?)
  end

  def campo(bloco, nome)
    prefixo = "- #{nome}:"
    bloco.lines.map(&:strip).find { |linha| linha.start_with?(prefixo) }&.delete_prefix(prefixo)
  end

  # `:tab(test|knowledge)?` é um parâmetro chamado `tab`, opcional, com valores
  # fechados: o nome é o que vem antes do parêntese, e o `?` do fim diz se é
  # opcional. Os valores ficam com o roteador, que recusa o que não casar.
  def parametros_do(endereco)
    variaveis = endereco.split('/').select { |parte| parte.start_with?(':') }
    opcionais, obrigatorios = variaveis.partition { |parte| parte.end_with?('?') }
    nomes = ->(partes) { partes.map { |parte| parte.delete_prefix(':').delete_suffix('?').split('(').first } }
    { endereco: endereco, obrigatorios: nomes.call(obrigatorios) - [DA_SESSAO], opcionais: nomes.call(opcionais) }
  end
end
