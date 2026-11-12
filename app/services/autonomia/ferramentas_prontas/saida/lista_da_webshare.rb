# A lista do plano datacenter da Webshare, com a credencial de cada IP, para as consultas grátis (#2942). Reaproveita o
# cliente do WhatsApp Híbrido (`Webshare::Client.new(pool: :datacenter)`, #1516).
#   - a lista fica SÓ na memória deste processo, por VALIDADE: nunca no Redis, no banco ou no log (o `Webshare::Proxy` não
#     mostra a credencial em inspect, to_s nem JSON);
#   - um cliente só por processo: ele guarda o plano que resolveu (`Webshare::Client#plan_id`), e cada busca não lista
#     os planos de novo. Depois de uma falha, o cliente é refeito (o plano pode ter mudado);
#   - a trava não fica presa durante o HTTP: quem busca marca `@buscando`, solta a trava, e grava sob a trava;
#   - O PRAZO DA CONSULTA MANDA (`ate:`): a busca só começa se cabe no que resta dela (`orcamento`: PRAZO por pedido à
#     Webshare, e o 1º de cada cliente também lista os planos). Ressalva: o PRAZO do cliente vale para a abertura e para
#     a leitura de cada pedido, então o pior caso de um pedido é o dobro; contar o dobro deixaria quase toda consulta
#     sem buscar, e a Webshare responde bem abaixo do PRAZO. A lista vencida (até VENCIDA_SERVE) só serve à consulta
#     cujo prazo não cabe a busca, e nunca à reconciliação (`fresca`). Com outra busca em andamento, espera por ela só
#     até o prazo (`esperar_a_busca`). Sem lista e sem prazo, `Saida::SemTempo`: a consulta sai pelo servidor, e a
#     reconciliação alerta e tenta na rodada seguinte;
#   - a Webshare fora (ou a rede, `Saida::ERROS_DE_REDE`): o erro é lembrado por ESPERA, para cada consulta não esperar o
#     prazo de novo; a consulta sai pelo IP do servidor (`Saida#sem_ip_proprio`).
module Autonomia::FerramentasProntas::Saida::ListaDaWebshare
  VALIDADE = 3.minutes.to_i
  VENCIDA_SERVE = 30.minutes.to_i
  ESPERA = 1.minute.to_i
  PRAZO = 1.5
  ESPERA_DA_BUSCA = PRAZO * 4
  TRAVA = Mutex.new
  BUSCOU = ConditionVariable.new

  class << self
    # `fresca: true` (a reconciliação) busca de novo, mesmo com a lista na validade. `ate`: o instante (relógio
    # monotônico) até o qual a consulta pode esperar; nil, sem limite.
    def proxies(fresca: false, ate: nil)
      TRAVA.synchronize do
        guardada = da_memoria(fresca)
        return guardada if guardada

        reserva = sem_prazo_para_buscar(fresca, ate)
        return reserva if reserva
        return esperar_a_busca(ate) if @buscando
        raise Autonomia::FerramentasProntas::Saida::SemTempo unless cabe?(ate)

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

    # A lista vencida, só para a consulta cujo prazo não cabe a busca. A reconciliação (`fresca`) nunca a recebe.
    def sem_prazo_para_buscar(fresca, ate)
      return if fresca || cabe?(ate)

      @lista if @lista && recente?(@lida_em, VENCIDA_SERVE)
    end

    # O que a busca pode levar: um PRAZO por pedido; o cliente novo também lista os planos.
    def orcamento
      PRAZO * (@cliente ? 1 : 2)
    end

    def cabe?(ate)
      ate.nil? || ate - agora >= orcamento
    end

    # Chamado com a trava: `wait` a solta enquanto espera, só até o prazo da consulta.
    def esperar_a_busca(ate)
      espera = ate.nil? ? ESPERA_DA_BUSCA : [ESPERA_DA_BUSCA, ate - agora].min
      raise Autonomia::FerramentasProntas::Saida::SemTempo unless espera.positive?

      BUSCOU.wait(TRAVA, espera)
      return @lista if @lista
      raise @falha if @falha

      raise Autonomia::FerramentasProntas::Saida::SemTempo
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
