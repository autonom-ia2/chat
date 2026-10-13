# Modelo de mensagem do WhatsApp (#1333, épico #1320): o texto que a Meta revisa antes de aprovar. Primeiro consumidor:
# "Criar com IA" e "Melhorar com IA" da tela de Modelos (`Whatsapp::Templates::Redacao`). Prompt e schema calibrados na
# bateria da Modelos (29/30, 8/8 armadilhas): cada opção traz o corpo em "texto" e, em "whatsapp", cabeçalho, rodapé,
# botões e um nome sugerido, com o tipo previsto (serviço ou divulgação). O tipo é só previsão: quem decide é a Meta.
#
# A conferência é a comum (chaves, pontas, tamanho, base) mais a da Meta, só de estrutura e sem regex:
# corpo até 1024; campos sem palavra entre eles;
# cabeçalho até 60, com no máximo 1 campo e sem campo nas pontas; rodapé até 60 sem campo; até 3 botões de um grupo só
# (respostas rápidas, ou até 2 links e 1 telefone), texto até 25, campo só em link/telefone. O nome sugerido é
# normalizado (a-z, 0-9 e "_"), nunca motivo de descarte.
# "No máximo 5 campos, um para cada 4 palavras" fica só no prompt: é escolha nossa (a Meta não publica número), e no
# "melhorar" a base já pode ter mais campos que isso, que a opção é obrigada a manter.
class Ai::Redacao::Canais::WhatsappModelo < Ai::Redacao::Canais::Base
  CORPO_MAXIMO = 1024
  CABECALHO_MAXIMO = 60
  RODAPE_MAXIMO = 60
  BOTAO_MAXIMO = 25
  BOTOES_MAXIMO = 3
  NOME_MAXIMO = 40
  RESPOSTA = 'resposta_rapida'.freeze
  LINK = 'link'.freeze
  TELEFONE = 'telefone'.freeze
  TIPOS_DE_BOTAO = [RESPOSTA, LINK, TELEFONE].freeze
  LIMITE_POR_TIPO = { LINK => 2, TELEFONE => 1 }.freeze
  LETRAS_DO_NOME = [*'a'..'z', *'0'..'9', '_'].to_set.freeze
  SEPARADOR = '_'.freeze
  # Melhorias em que o campo da base pode ser o problema (a oferta num campo, o dado proibido): o comum.md manda tirar
  # e dizer em "o_que_mudou". Nas outras ("mais_curto", "mais_claro") os campos da base continuam obrigatórios.
  PODE_TIRAR_CAMPO = %w[manter_como_servico corrigir_recusa].freeze
  # "Mais curto" medido no texto fixo (sem os campos): pelo menos 30% menor; 25% quando a base tem 4 campos ou mais,
  # que sobra pouco texto para cortar (calibração r2, PN04). A explicação da IA não conta.
  CORTE_MINIMO = 0.30
  CORTE_MINIMO_COM_MUITOS_CAMPOS = 0.25
  MUITOS_CAMPOS = 4
  # Botões em que um campo do corpo da base pode ir morar (o link vai no botão, AG15).
  BOTOES_COM_CAMPO = [LINK, TELEFONE].freeze
  # Quem fala: o prompt pede o remetente na 1ª ou 2ª frase, então ele pode entrar até no "mais curto" (AG15).
  REMETENTE = 'minha_empresa.nome'.freeze

  class << self
    def nome
      'whatsapp_modelo'
    end

    # O cabeçalho e o campo de cada botão também levam chave (o do botão vira `{{chave}}` só para a conferência).
    def textos_com_chaves(opcao)
      whatsapp = whatsapp_de(opcao)
      [opcao['texto'].to_s, whatsapp['cabecalho'].to_s] +
        botoes_de(whatsapp).filter_map { |botao| "{{#{botao['chave']}}}" if botao['chave'].present? }
    end

    def normalizar_opcao(opcao)
      whatsapp = whatsapp_de(opcao)
      super.merge(
        chaves_usadas: textos_com_chaves(opcao).flat_map { |texto| Ai::Redacao::Chaves.extrair(texto) }.uniq,
        certeza_categoria: opcao['certeza_categoria'],
        whatsapp: {
          cabecalho: whatsapp['cabecalho'].to_s.strip.presence, rodape: whatsapp['rodape'].to_s.strip.presence,
          nome_sugerido: nome_normalizado(whatsapp['nome_sugerido']),
          botoes: botoes_de(whatsapp).map { |botao| { tipo: botao['tipo'], texto: botao['texto'].to_s.strip, chave: botao['chave'] } }
        }
      )
    end

    # Calibração r2 (AG15): o campo da base que saiu do corpo e foi para um botão de link ou telefone continua presente.
    # O "mais curto" segue sem campo novo no corpo.
    def validar(opcao, chaves:, limites:, base: nil, pedido: nil)
      motivo = super
      return motivo unless motivo == :campo_da_base_removido && campos_da_base_presentes?(opcao, chaves, base)

      return :campo_novo_no_mais_curto if campo_novo_no_mais_curto?(Ai::Redacao::Chaves.extrair(opcao['texto'].to_s), chaves, base, pedido)

      problema_do_canal(opcao, chaves: chaves, limites: limites, base: base, pedido: pedido)
    end

    # Letras fora dos campos: o que o "mais curto" mede.
    def tamanho_fixo(texto)
      Ai::Redacao::Chaves.partes(texto.to_s).reject(&:chave?).sum { |parte| parte.valor.length }
    end

    # Quanto o texto fixo encolheu da base para a opção (0,3 = 30% menor).
    def corte(base, texto)
      antes = tamanho_fixo(texto_da_base(base))
      return 0.0 if antes.zero?

      1 - tamanho_fixo(texto).fdiv(antes)
    end

    # O nome é cosmético (a pessoa troca na tela): fora do formato vira formato, sem descartar a opção. Minúsculas,
    # acento tirado, o resto que não é letra ou número vira "_", sem "_" repetido nem nas pontas, até 40.
    def nome_normalizado(nome)
      limpo = ActiveSupport::Inflector.transliterate(nome.to_s).downcase
      limpo = limpo.each_char.map { |char| LETRAS_DO_NOME.include?(char) ? char : SEPARADOR }.join.squeeze(SEPARADOR)
      limpo.delete_prefix(SEPARADOR).delete_suffix(SEPARADOR).first(NOME_MAXIMO).delete_suffix(SEPARADOR)
    end

    private

    def problema_do_canal(opcao, chaves:, base: nil, pedido: nil, **)
      whatsapp = whatsapp_de(opcao)
      problema_do_corpo(opcao['texto'].to_s) || problema_do_cabecalho(whatsapp['cabecalho']) ||
        problema_do_rodape(whatsapp['rodape']) || problema_dos_botoes(botoes_de(whatsapp), chaves) ||
        problema_do_corte(opcao['texto'].to_s, base, pedido)
    end

    def problema_do_corte(texto, base, pedido)
      return if base.blank? || !mais_curto?(pedido)

      muitos = Ai::Redacao::Chaves.extrair(texto_da_base(base)).uniq.size >= MUITOS_CAMPOS
      :corte_pequeno if corte(base, texto) < (muitos ? CORTE_MINIMO_COM_MUITOS_CAMPOS : CORTE_MINIMO)
    end

    def texto_da_base(base)
      (base.is_a?(Hash) ? base.to_h.stringify_keys['texto'] : base).to_s
    end

    def campos_da_base_presentes?(opcao, chaves, base)
      nos_botoes = botoes_de(whatsapp_de(opcao)).filter_map { |botao| botao['chave'] if BOTOES_COM_CAMPO.include?(botao['tipo']) }
      presentes = Ai::Redacao::Chaves.extrair(opcao['texto'].to_s) + nos_botoes
      ((chaves_da_base(base) & Array(chaves[:permitidas])) - presentes).empty?
    end

    # Calibração 13/10 (AG11): em "manter como serviço" e "corrigir recusa" a opção pode tirar campo da base. Campo
    # fora da lista segue barrado (`problema_das_chaves`), e no "mais curto" não entra campo novo.
    # Fase final (AG15): no "mais curto", o remetente ({{minha_empresa.nome}}) pode entrar; outro campo novo, não.
    def problema_da_base(usadas, chaves, base, pedido)
      return if base.blank?

      da_base = chaves_da_base(base) & Array(chaves[:permitidas])
      return :campo_da_base_removido if !pode_tirar_campo?(pedido) && !(da_base - usadas).empty?

      :campo_novo_no_mais_curto if campo_novo_no_mais_curto?(usadas, chaves, base, pedido)
    end

    # `corpo`: as chaves do corpo da opção.
    def campo_novo_no_mais_curto?(corpo, chaves, base, pedido)
      return false unless mais_curto?(pedido)

      !(corpo - (chaves_da_base(base) & Array(chaves[:permitidas])) - [REMETENTE]).empty?
    end

    def pode_tirar_campo?(pedido)
      melhorias = pedido.is_a?(Hash) ? Array(pedido.to_h.stringify_keys['melhorias']).map(&:to_s) : []
      melhorias.intersect?(PODE_TIRAR_CAMPO)
    end

    def problema_do_corpo(texto)
      return :longo if texto.length > CORPO_MAXIMO

      :campos_colados if campos_colados?(Ai::Redacao::Chaves.partes(texto))
    end

    # Dois campos com só espaço ou pontuação entre eles.
    def campos_colados?(partes)
      partes.each_cons(2).any? { |a, b| a.chave? && b.chave? } ||
        partes.each_cons(3).any? { |a, meio, b| a.chave? && b.chave? && !texto_com_letra?(meio) }
    end

    def problema_do_cabecalho(cabecalho)
      return if cabecalho.blank?

      :cabecalho_invalido if cabecalho.length > CABECALHO_MAXIMO || Ai::Redacao::Chaves.malformado?(cabecalho) ||
                             campos_do_cabecalho_ruins?(Ai::Redacao::Chaves.partes(cabecalho))
    end

    # No máximo 1 campo, e nunca na ponta.
    def campos_do_cabecalho_ruins?(partes)
      partes.count(&:chave?) > 1 || partes.first.chave? || partes.last.chave?
    end

    def problema_do_rodape(rodape)
      return if rodape.blank?

      :rodape_invalido if rodape.length > RODAPE_MAXIMO || rodape.include?(Ai::Redacao::Chaves::ABRE) ||
                          rodape.include?(Ai::Redacao::Chaves::FECHA)
    end

    def problema_dos_botoes(botoes, chaves)
      return :botoes_invalidos if botoes.size > BOTOES_MAXIMO || botoes.any? { |botao| botao_invalido?(botao, chaves) }

      problema_dos_grupos(botoes.pluck('tipo'))
    end

    # Um grupo só: respostas rápidas, ou até 2 links e 1 telefone.
    def problema_dos_grupos(tipos)
      return :botoes_misturados if tipos.include?(RESPOSTA) && tipos.uniq != [RESPOSTA]

      :botoes_invalidos if LIMITE_POR_TIPO.any? { |tipo, maximo| tipos.count(tipo) > maximo }
    end

    def botao_invalido?(botao, chaves)
      texto = botao['texto'].to_s.strip
      return true unless TIPOS_DE_BOTAO.include?(botao['tipo']) && texto.present? && texto.length <= BOTAO_MAXIMO
      return true if texto.include?(Ai::Redacao::Chaves::ABRE) || texto.include?(Ai::Redacao::Chaves::FECHA)

      chave_do_botao_invalida?(botao, chaves)
    end

    # Resposta rápida não tem campo; o campo de link ou telefone precisa estar na lista.
    def chave_do_botao_invalida?(botao, chaves)
      chave = botao['chave']
      return false if chave.nil?

      botao['tipo'] == RESPOSTA || Array(chaves[:permitidas]).exclude?(chave)
    end

    def whatsapp_de(opcao)
      opcao['whatsapp'].is_a?(Hash) ? opcao['whatsapp'] : {}
    end

    def botoes_de(whatsapp)
      Array(whatsapp['botoes']).select { |botao| botao.is_a?(Hash) }
    end

    def campos_da_opcao(_permitidas)
      {
        whatsapp: {
          type: 'object', additionalProperties: false, required: %w[cabecalho rodape botoes nome_sugerido],
          properties: {
            cabecalho: { type: %w[string null] }, rodape: { type: %w[string null] },
            botoes: { type: 'array', maxItems: BOTOES_MAXIMO, items: { '$ref': '#/$defs/botao' } },
            nome_sugerido: { type: 'string' }
          }
        }
      }
    end
  end

  # O `enum` da chave do botão depende das permitidas, então o schema do botão entra por chamada.
  def self.schema(permitidas:, opcoes:)
    botao = {
      type: 'object', additionalProperties: false, required: %w[tipo texto chave],
      properties: {
        tipo: { type: 'string', enum: TIPOS_DE_BOTAO }, texto: { type: 'string' },
        chave: { type: %w[string null], enum: permitidas + [nil] }
      }
    }
    super.deep_merge(schema: { '$defs': { botao: botao } })
  end
end
