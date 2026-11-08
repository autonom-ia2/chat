import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { TEXTO_DO_ERRO, erroDoDono } from './useDonoDaLista';
import { enderecoParaChamar } from './useGavetaDaLista';
import {
  escolherDestino,
  lembrarDestino,
  lerUltimoDestino,
} from '../utils/destinoPronto';

// #2697 — F5, a fila "Para chamar" de verdade. Saiu de ParaChamarPage.vue para
// a página caber na trava de tamanho. Uma empresa por vez:
// - "Mandar para o funil": o mesmo envio da lista (leads/crm_cards), com o
//   funil e a etapa do destino pronto e o dono de "Com quem fica" (#2694). O
//   bloco de sucesso diz a etapa e com quem ficou (D13). A lista de "Com quem
//   fica" vem de useDonoDaLista, que a refaz quando o destino muda.
// - "Não serve": o descarte com um dos motivos; "Desfazer" volta o lead a
//   new_lead.
// - "Depois": some da fila desta pessoa até amanhã (leads/:id/
//   queue_postponement); "Desfazer" tira a marca.
// - "Chamar no WhatsApp" / "Ligar": abre o WhatsApp verificado ou o telefone.
// O fim do dia são as contas desta passada pela fila (foram, voltam, não
// servem), sem pedir nada ao servidor. Na demonstração nada é gravado.
const NS = 'PROSPECTING_ACHAR.FILA';
const ESPERA = 500;

// Os estados da demonstração que abrem a fila num momento da jornada.
const ESTADOS = {
  'fila-sucesso': { fase: 'sucesso' },
  'fila-sucesso-ligar': { indice: 2, fase: 'sucesso' },
  'fila-nao-serve': { fase: 'nao-serve' },
  'fila-depois': { indice: 1, depois: true },
  'fila-procurando-dono': { indice: 3 },
  'fila-sem-dono': { indice: 2 },
  'fila-so-telefone': { indice: 2 },
  'fila-fim': { fase: 'fim' },
  'fila-fim-adiados': { fase: 'fim' },
};

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export function useFilaParaChamar({
  demo,
  fonte,
  carregarAjustes,
  ajustes,
  contaId,
  usuarioId,
  destino,
  donoId,
  pessoaNome,
}) {
  const { t } = useI18n();
  const carregando = ref(true);
  const erro = ref(false);
  const cartoes = ref([]);
  const indice = ref(0);
  const fase = ref('cartao');
  const mandando = ref(false);
  const aviso = ref(null);
  const foram = ref(0);
  const voltam = ref(0);
  const naoServem = ref(0);
  const funis = ref([]);
  // D13: para onde a empresa foi, guardado na hora de mandar.
  const mandado = ref(null);

  const atual = computed(() => cartoes.value[indice.value] || null);
  const temWhatsapp = computed(() => atual.value?.whatsapp === 'tem');

  const andar = () => {
    fase.value = 'cartao';
    if (indice.value + 1 >= cartoes.value.length) {
      fase.value = 'fim';
      return;
    }
    indice.value += 1;
  };

  // Volta a empresa ao cartão dela (o "Desfazer").
  const voltarPara = posicao => {
    indice.value = posicao;
    fase.value = 'cartao';
  };

  const aplicarDemo = fila => {
    const preset = ESTADOS[demo.value] || {};
    const noFim = preset.fase === 'fim';
    indice.value = preset.indice || 0;
    fase.value = preset.fase || 'cartao';
    foram.value = noFim ? fila.fim?.foramParaOFunil || 0 : 0;
    voltam.value = noFim ? fila.fim?.voltamAmanha || 0 : 0;
    naoServem.value = noFim ? fila.fim?.naoServem || 0 : 0;
    if (preset.fase === 'sucesso') {
      mandado.value = {
        etapa: destino.value?.etapa.nome,
        pessoa: pessoaNome.value,
      };
    }
    aviso.value = preset.depois
      ? {
          chave: `${NS}.DEPOIS_AVISO`,
          params: { nome: fila.cartoes[0]?.nome },
          desfazer: () => voltarPara(indice.value - 1),
        }
      : null;
  };

  const carregar = async () => {
    carregando.value = true;
    erro.value = false;
    aviso.value = null;
    mandado.value = null;
    try {
      await carregarAjustes();
      const [fila, lista] = await Promise.all([
        fonte.value.fila(),
        fonte.value.funis(),
      ]);
      cartoes.value = fila.cartoes;
      funis.value = lista;
      destino.value = escolherDestino({
        funis: lista,
        ultimo: demo.value
          ? null
          : lerUltimoDestino(contaId.value, usuarioId.value),
        padrao: ajustes.value?.padrao || null,
      });
      foram.value = 0;
      voltam.value = 0;
      naoServem.value = 0;
      aplicarDemo(fila);
    } catch {
      cartoes.value = [];
      erro.value = true;
    }
    carregando.value = false;
  };

  const enviar = async empresa => {
    if (demo.value) {
      await esperar(ESPERA);
      return true;
    }
    let resumo;
    try {
      resumo = await fonte.value.mandarParaFunil({
        ids: [empresa.id],
        funilId: destino.value.funil.id,
        etapaId: destino.value.etapa.id,
        donoId: donoId.value,
      });
    } catch {
      useAlert(t(TEXTO_DO_ERRO.funil));
      return false;
    }
    if (!resumo.created.length && !resumo.existing.length) {
      useAlert(t(TEXTO_DO_ERRO[erroDoDono(resumo) || 'funil']));
      return false;
    }
    lembrarDestino(contaId.value, usuarioId.value, {
      funilId: destino.value.funil.id,
      etapaId: destino.value.etapa.id,
    });
    return true;
  };

  const mandar = async () => {
    if (mandando.value || !atual.value) return;
    mandando.value = true;
    const foi = await enviar(atual.value);
    mandando.value = false;
    if (!foi) return;
    foram.value += 1;
    mandado.value = {
      etapa: destino.value?.etapa.nome,
      pessoa: pessoaNome.value,
    };
    fase.value = 'sucesso';
  };

  const chamar = tipo => {
    const empresa = atual.value;
    if (demo.value || !empresa) {
      useAlert(t('PROSPECTING_ACHAR.COMUM.DEMO_WHATSAPP'));
      return;
    }
    const endereco = enderecoParaChamar(
      empresa,
      tipo || (temWhatsapp.value ? 'whatsapp' : 'ligar')
    );
    if (endereco) window.open(endereco, '_blank', 'noopener');
  };

  // Grava no servidor (fora da demonstração); na recusa, avisa e não anda.
  const gravar = async acao => {
    if (demo.value) return true;
    try {
      await acao();
      return true;
    } catch {
      useAlert(t(`${NS}.ERRO_ACAO`));
      return false;
    }
  };

  // Tira a empresa da fila (Não serve, Depois) com o "Desfazer" na faixa.
  const tirarDaFila = async ({ gravarIda, gravarVolta, contador, chave }) => {
    const empresa = atual.value;
    const posicao = indice.value;
    if (!empresa || !(await gravar(gravarIda(empresa)))) return;
    contador.value += 1;
    andar();
    aviso.value = {
      chave,
      params: { nome: empresa.nome },
      desfazer: async () => {
        if (!(await gravar(gravarVolta(empresa)))) return;
        contador.value -= 1;
        voltarPara(posicao);
      },
    };
  };

  const tirar = motivo =>
    tirarDaFila({
      gravarIda: empresa => () =>
        fonte.value.descartar({ id: empresa.id, motivo }),
      gravarVolta: empresa => () =>
        fonte.value.voltarNaoServe({ id: empresa.id }),
      contador: naoServem,
      chave: `${NS}.SAIU`,
    });

  const depois = () =>
    tirarDaFila({
      gravarIda: empresa => () => fonte.value.depois({ id: empresa.id }),
      gravarVolta: empresa => () =>
        fonte.value.desfazerDepois({ id: empresa.id }),
      contador: voltam,
      chave: `${NS}.DEPOIS_AVISO`,
    });

  const desfazer = async () => {
    const atualAviso = aviso.value;
    aviso.value = null;
    await atualAviso?.desfazer();
  };

  return {
    carregando,
    erro,
    cartoes,
    indice,
    fase,
    mandando,
    aviso,
    foram,
    voltam,
    naoServem,
    funis,
    mandado,
    atual,
    temWhatsapp,
    andar,
    carregar,
    mandar,
    chamar,
    tirar,
    depois,
    desfazer,
  };
}
