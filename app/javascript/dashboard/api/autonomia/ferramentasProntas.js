/* global axios */
import ApiClient from '../ApiClient';

// #2858 F2 — a vitrine de ferramentas prontas (FerramentasProntasController). Sem as flags
// agente_ferramentas_prontas e agente_ferramentas_prontas_vitrine na conta, 404; sem ser administrador nem ter a chave
// autonomia_tools_manage, 401.
//   listar        -> { fontes: [{ chave, premium? }], incluidas: [{ id, agente_id, fonte, ligada, usar_quando }] }
//                    `premium` (F7, só nos cards pagos): { gratis, restantes, precos: ['0.06', '0.15'] }
//   incluir       -> 201 a pronta | 422 { motivo }
//   mudarLigada   -> a pronta
//   tirar         -> 204
//   experimentar  -> { situacao: 'encontrado' | 'nao_encontrado' | 'nao_consegui_consultar' | 'pedido_invalido' |
//                    'desligada' | 'documento_invalido' | 'confirmar_preco', dados?, premium? } (F7: no card Premium,
//                    `premium` é o contador novo; `confirmar_preco`, as grátis acabaram e faltou o clique no preço,
//                    que vai em `confirmou_preco`). No card Premium com consulta, 202 { situacao: 'consultando',
//                    pedido, premium }: a consulta paga roda em segundo plano
//   acompanhar    -> o pedido do Experimente Premium: { situacao: 'consultando' } ou o resultado, como no
//                    `experimentar` | 404 (pedido vencido ou de outra conta)
//   buscaSemResultado -> 204
//   sugestoes     -> { ferramentas: [chave] } (F3: o cartão "pode ganhar"; sem a flag do Construtor, 404)
//   dispensar     -> 204 ("Agora não": aquela sugestão não volta para o agente)
class AutonomiaFerramentasProntasAPI extends ApiClient {
  constructor() {
    super('autonomia/ferramentas_prontas', { accountScoped: true });
  }

  listar() {
    return axios.get(this.url);
  }

  incluir({ fonte, agenteId, usarQuando }) {
    return axios.post(`${this.url}/incluir`, {
      fonte,
      agent_id: agenteId,
      usar_quando: usarQuando,
    });
  }

  mudarLigada(id, ligada) {
    return axios.patch(`${this.url}/${id}`, { ligada });
  }

  tirar(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  experimentar(fonte, valor, confirmouPreco = false) {
    return axios.post(`${this.url}/experimentar`, {
      fonte,
      valor,
      confirmou_preco: confirmouPreco,
    });
  }

  acompanhar(pedido) {
    return axios.get(`${this.url}/experimentar/${pedido}`);
  }

  buscaSemResultado(termo) {
    return axios.post(`${this.url}/buscas_sem_resultado`, { termo });
  }

  sugestoes(agenteId) {
    return axios.get(`${this.url}/sugestoes`, {
      params: { agent_id: agenteId },
    });
  }

  dispensar(agenteId, fonte) {
    return axios.post(`${this.url}/dispensar`, { agent_id: agenteId, fonte });
  }
}

export default new AutonomiaFerramentasProntasAPI();
