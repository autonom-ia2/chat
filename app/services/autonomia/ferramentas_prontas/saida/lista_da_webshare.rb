# A lista do plano datacenter da Webshare, com a credencial de cada IP, para as consultas grátis (#2942). Reaproveita o
# cliente do WhatsApp Híbrido (`Webshare::Client.new(pool: :datacenter)`, #1516).
#   - a lista fica SÓ na memória deste processo, por VALIDADE: nunca no Redis, no banco ou no log (o `Webshare::Proxy` não
#     mostra a credencial em inspect, to_s nem JSON);
#   - um cliente só por processo: ele guarda o plano que resolveu (`Webshare::Client#plan_id`), e cada busca não lista
#     os planos de novo. Depois de uma falha, o cliente é refeito (o plano pode ter mudado);
#   - a trava não fica presa durante o HTTP: quem busca marca `@buscando`, solta a trava, e grava sob a trava; quem chega
#     enquanto isso espera a busca (até ESPERA_DA_BUSCA) e fica com o que ela trouxe;
#   - cada pedido à Webshare tem PRAZO, menor que o da consulta, que ainda vai à fonte depois;
#   - a Webshare fora: o erro é lembrado por ESPERA, para cada consulta não esperar o prazo de novo; a consulta sai pelo
#     IP do servidor (`Saida#sem_ip_proprio`).
module Autonomia::FerramentasProntas::Saida::ListaDaWebshare
  VALIDADE = 3.minutes.to_i
  ESPERA = 1.minute.to_i
  PRAZO = 2
  ESPERA_DA_BUSCA = PRAZO * 3
  TRAVA = Mutex.new
  BUSCOU = ConditionVariable.new

  class << self
    # `fresca: true` (a reconciliação) busca de novo, mesmo com a lista na validade.
    def proxies(fresca: false)
      TRAVA.synchronize do
        guardada = da_memoria(fresca)
        return guardada if guardada
        return esperar_a_busca if @buscando

        @buscando = true
      end
      buscar
    end

    # A credencial pode ter mudado (o proxy recusou o túnel): a próxima consulta busca de novo.
    def esquecer!
      TRAVA.synchronize { @lista = @lida_em = @falha = @falhou_em = @cliente = nil }
    end

    private

    # -> a lista na validade; levanta a falha recente; nil quando é preciso buscar.
    def da_memoria(fresca)
      return if fresca
      raise @falha if @falha && recente?(@falhou_em, ESPERA)

      @lista if @lista && recente?(@lida_em, VALIDADE)
    end

    # Chamado com a trava: `wait` a solta enquanto espera.
    def esperar_a_busca
      BUSCOU.wait(TRAVA, ESPERA_DA_BUSCA)
      return @lista if @lista
      raise @falha if @falha

      raise Webshare::Client::Error, 'webshare_busca_sem_resposta'
    end

    def buscar
      guardar(lista: cliente.proxies)
    rescue Webshare::Client::Error, *Autonomia::FerramentasProntas::Saida::ERROS_DE_REDE => e
      guardar(falha: e)
      raise
    ensure
      soltar_a_busca
    end

    def cliente
      @cliente ||= Webshare::Client.new(pool: :datacenter, timeout: PRAZO)
    end

    def guardar(lista: nil, falha: nil)
      TRAVA.synchronize do
        @lista = lista
        @lida_em = lista && agora
        @falha = falha
        @falhou_em = falha && agora
        @cliente = nil if falha
        lista
      end
    end

    # Também no erro inesperado: a marca não pode ficar presa.
    def soltar_a_busca
      TRAVA.synchronize do
        @buscando = false
        BUSCOU.broadcast
      end
    end

    def recente?(instante, segundos)
      instante && agora - instante < segundos
    end

    def agora
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
