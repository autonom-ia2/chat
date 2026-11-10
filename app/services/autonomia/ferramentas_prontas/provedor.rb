# UM PROVEDOR de uma fonte do catálogo (#2858, F0): o adaptador de uma API pública. Cada fonte tem o principal e a
# reserva (`Consulta#provedores`); cada um é uma subclasse com:
#   - `NOME` (curto, minúsculo: entra na chave do motivo, `brasilapi.tempo_esgotado`) e `HOST` (o único que ele chama);
#   - `consultar(consulta, params)`: monta o caminho só com os `params` já normalizados, chama `get` e devolve os dados
#     JÁ ENXUTOS (só o que o agente precisa), ou levanta `NaoEncontrado`/`Falha`;
#   - provedor LOCAL (`HOST = nil`): calcula aqui, sem rede (o CPF, o calendário dos feriados, o plano de numeração do
#     DDD). Não chama `get`, e o teto e o cliente HTTP não valem para ele;
#   - `aplica?(consulta, params)`, quando o provedor não atende todo pedido da consulta (ex.: a BrasilAPI só dá o preço
#     da FIPE pelo código). O que não se aplica é pulado sem contar como falha.
class Autonomia::FerramentasProntas::Provedor
  # A fonte respondeu e não tem o que foi pedido (CEP que não existe). Não é falha: a reserva ainda é consultada, e se
  # nenhuma tiver, o agente ouve que não há registro.
  class NaoEncontrado < StandardError; end

  # A fonte não respondeu como devia. `message` é o motivo curto do código (nunca texto de fora).
  class Falha < StandardError
    def motivo
      message
    end
  end

  class << self
    def nome
      self::NOME
    end

    def host
      self::HOST
    end

    def aplica?(_consulta, _params)
      true
    end

    # Quanto a resposta DESTE provedor vale no cache, quando difere da consulta: a reserva que responde só parte (o DDD
    # sem as cidades) declara `VALIDADE` curta, ou 0 (não grava). nil: a validade da consulta.
    def validade
      const_defined?(:VALIDADE, false) ? self::VALIDADE : nil
    end
  end

  def initialize(cliente, prazo:)
    @cliente = cliente
    @prazo = prazo
  end

  private

  def get(caminho, max_bytes: Autonomia::FerramentasProntas::ClienteHttp::MAX_BYTES)
    @cliente.get_json(self.class.host, caminho, prazo: @prazo, max_bytes: max_bytes)
  end

  def get_csv(caminho)
    @cliente.get_csv(self.class.host, caminho, prazo: @prazo)
  end

  # O parâmetro de texto que vai na URL, codificado (o resto do caminho é dígito ou opção da lista).
  def codificar(valor)
    ERB::Util.url_encode(valor.to_s)
  end

  # O dado veio, mas sem o que faz dele uma resposta (a fonte mudou o formato): falha, e a reserva tenta.
  def exigir!(valor)
    raise Falha, 'resposta_invalida' if valor.blank?

    valor
  end

  # A fonte devolveu outra coisa que não um objeto JSON (lista, texto): falha, e a reserva tenta.
  def objeto!(valor)
    raise Falha, 'resposta_invalida' unless valor.is_a?(Hash)

    valor
  end

  # A fonte devolveu outra coisa que não uma lista JSON: falha (não "não encontrado"), e a reserva tenta.
  def lista!(valor)
    raise Falha, 'resposta_invalida' unless valor.is_a?(Array)

    valor
  end

  def texto(valor)
    valor.to_s.strip.presence
  end
end
