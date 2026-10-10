import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AutonomiaBuilderImagesAPI from 'dashboard/api/autonomia/builderImages';
import AutonomiaBuildThreadsAPI from 'dashboard/api/autonomia/buildThreads';
import { MAX_ARQUIVO_BYTES } from '../constants/criacao';

// #1181 PR2 — a conversa da etapa Conte com o Construtor, pela store autonomiaBuildThreads (sem
// editá-la): start/send/retry/completeMaterials, e stopPolling ao sair (a store tem um poll único).
// - A IA fala primeiro: a conversa abre só com o modelo (`type`), atuação externa e com base
//   (arquivos sempre opcionais; o rascunho nasce na primeira resposta e dá o agentId).
// - Continuar um rascunho: com instrução, já está pronto para testar (sem abrir conversa até a
//   pessoa escrever); sem instrução, abre a conversa ligada ao agente (o backend retoma a pergunta).
// - A conversa fecha quando o Construtor gera o agente (fase `reviewing` com `agent_id` na thread;
//   se a store não conseguir ler o agente, ele é lido à parte) ou por "Testar agora"
//   (completeMaterials = force_close, fecha com ou sem arquivo ainda em leitura). Ao sair, o fechamento
//   vai direto pela API: a store é limpa na mesma hora e a resposta não deve religar o poll.
// - "Tentar de novo": se o turno não chegou ao servidor (erro 'send'), reenvia o mesmo turno (texto e
//   fotos); se a geração falhou ('failed'/'timeout'), pede o retry.
// - Arquivos vão para a base (autonomiaSources); fotos vão no turno (builder_images), como no
//   Construtor de hoje. Nenhum é obrigatório.
export const ESPERA_DEMORANDO_MS = 60000;
// "Agora não" / sair com pelo menos duas respostas: fecha no servidor para o rascunho ter instrução
// (mesma regra do Construtor de hoje e do protótipo: hasInstruction = closed || answers >= 2).
const RESPOSTAS_PARA_FECHAR_AO_SAIR = 2;

const ehFoto = arquivo => (arquivo?.type || '').startsWith('image/');

// Estado do material lido da base (autonomiaSources): falhou ou o Revisor pediu outro = atenção;
// pronto com veredito = pronto; o resto ainda está sendo lido.
const VEREDITOS_OK = ['accepted', 'needs_review'];
const estadoDaFonte = fonte => {
  if (!fonte) return 'lendo';
  if (fonte.status === 'failed' || fonte.review?.status === 'needs_resend') {
    return 'atencao';
  }
  if (fonte.status === 'ready' && VEREDITOS_OK.includes(fonte.review?.status)) {
    return 'pronto';
  }
  return 'lendo';
};

export function useConversaDeCriacao({ modelo }) {
  const store = useStore();
  const { t } = useI18n();

  const mensagensDaStore = useMapGetter('autonomiaBuildThreads/getMessages');
  const status = useMapGetter('autonomiaBuildThreads/getStatus');
  const fase = useMapGetter('autonomiaBuildThreads/getPhase');
  const erroDaStore = useMapGetter('autonomiaBuildThreads/getError');
  const thread = useMapGetter('autonomiaBuildThreads/getThread');
  const agenteGerado = useMapGetter('autonomiaBuildThreads/getAgent');
  const flags = useMapGetter('autonomiaBuildThreads/getUIFlags');
  const fontes = useMapGetter('autonomiaSources/getSources');

  const agenteExistente = ref(null);
  const fechada = ref(false);
  // Falas do front antes das da store ("Vamos continuar de onde paramos.").
  const abertura = ref([]);
  const materiais = ref([]);
  const aviso = ref(null);
  const demorando = ref(false);
  // Quantas vezes a conversa fechou de novo depois de fechada (o teste avisa "Atualizado").
  const atualizacoes = ref(0);
  const encerrando = ref(false);
  // Fotos subindo e o turno indo: um envio por vez (pensando ainda não sabe disso).
  const enviando = ref(false);
  // Último estado visto de cada arquivo da base: a store esvazia a lista a cada leitura.
  const estadosDasFontes = ref({});
  let proximoMaterial = 0;
  let relogioDemora = null;
  // O último turno mandado ({ conteudo, extra, echo }), para reenviar se não chegou.
  let ultimoEnvio = null;

  const threadId = computed(() => thread.value?.id || null);
  const agenteId = computed(
    () =>
      thread.value?.agent_id ||
      agenteGerado.value?.id ||
      agenteExistente.value?.id ||
      null
  );
  const pensando = computed(
    () =>
      enviando.value ||
      Boolean(flags.value?.creating || flags.value?.sending) ||
      status.value === 'processing'
  );
  const falhou = computed(
    () =>
      ['send', 'failed', 'timeout'].includes(erroDaStore.value) ||
      status.value === 'failed'
  );
  const respostas = computed(
    () => (mensagensDaStore.value || []).filter(m => m.role === 'user').length
  );

  // A conversa inteira, na ordem: falas do front, turnos da store e os materiais na posição em que
  // foram mandados.
  const falas = computed(() => {
    const turnos = [
      ...abertura.value.map(texto => ({ de: 'assistente', texto })),
      ...(mensagensDaStore.value || []).map(m => ({
        de: m.role === 'user' ? 'voce' : 'assistente',
        texto: m.content,
      })),
    ];
    // Material mandado com N turnos na tela aparece depois do turno N (0 = antes de todos).
    const materiaisEm = posicao =>
      materiais.value
        .filter(m => Math.min(m.posicao, turnos.length) === posicao)
        .map(m => ({ de: 'material', material: m, chave: `m${m.id}` }));
    return turnos.reduce(
      (lista, turno, indice) => [
        ...lista,
        { ...turno, chave: `t${indice}` },
        ...materiaisEm(indice + 1),
      ],
      materiaisEm(0)
    );
  });

  watch(
    fontes,
    lista => {
      const vistos = Object.fromEntries(
        (lista || []).map(fonte => [fonte.id, estadoDaFonte(fonte)])
      );
      estadosDasFontes.value = { ...estadosDasFontes.value, ...vistos };
    },
    { flush: 'sync' }
  );

  const estadoDoMaterial = material => {
    if (material.estado !== 'base') return material.estado;
    return estadosDasFontes.value[material.fonteId] || estadoDaFonte(null);
  };

  const opcoesDeInicio = () =>
    agenteExistente.value
      ? { agentId: agenteExistente.value.id }
      : { type: modelo, actuation: 'external', with_knowledge: true };

  const abrir = (extra = {}) =>
    store
      .dispatch('autonomiaBuildThreads/start', {
        ...opcoesDeInicio(),
        ...extra,
      })
      .catch(() => null); // a falha fica no erro da store e vira o cartão "Tentar de novo"

  const comecar = () => abrir();

  const continuar = agente => {
    agenteExistente.value = agente;
    abertura.value = [t('AGENTS.JORNADA.CRIAR.CONTE.CONTINUAR')];
    if (agente.has_instruction) {
      abertura.value = [
        ...abertura.value,
        t('AGENTS.JORNADA.CRIAR.CONTE.FECHOU', {
          nome: agente.name || t('AGENTS.JORNADA.COMUM.NOVO_AGENTE'),
        }),
      ];
      fechada.value = true;
      return Promise.resolve(null);
    }
    return abrir();
  };

  const trocarMaterial = (id, mudanca) => {
    materiais.value = materiais.value.map(m =>
      m.id === id ? { ...m, ...mudanca } : m
    );
  };

  const novoMaterial = (arquivo, extra) => {
    proximoMaterial += 1;
    const material = {
      id: proximoMaterial,
      nome: arquivo.name,
      tipo: ehFoto(arquivo) ? 'foto' : 'arquivo',
      posicao: abertura.value.length + (mensagensDaStore.value || []).length,
      ...extra,
    };
    materiais.value = [...materiais.value, material];
    return material;
  };

  const mandarParaBase = async (material, arquivo) => {
    trocarMaterial(material.id, { estado: 'enviando' });
    try {
      const fonte = await store.dispatch('autonomiaSources/create', {
        agentId: agenteId.value,
        descriptor: { file: arquivo, kind: 'knowledge' },
      });
      trocarMaterial(material.id, { estado: 'base', fonteId: fonte?.id });
    } catch {
      trocarMaterial(material.id, { estado: 'atencao' });
    }
  };

  // Arquivo antes de existir o rascunho espera na fila ("Vou ler assim que começarmos").
  const filaDeArquivos = new Map();
  const anexarArquivo = arquivo => {
    if (arquivo.size > MAX_ARQUIVO_BYTES) {
      novoMaterial(arquivo, { estado: 'grande' });
      return;
    }
    if (!agenteId.value) {
      const material = novoMaterial(arquivo, { estado: 'fila' });
      filaDeArquivos.set(material.id, arquivo);
      return;
    }
    mandarParaBase(novoMaterial(arquivo, { estado: 'enviando' }), arquivo);
  };

  watch(agenteId, id => {
    if (!id) return;
    filaDeArquivos.forEach((arquivo, materialId) => {
      const material = materiais.value.find(m => m.id === materialId);
      if (material) mandarParaBase(material, arquivo);
    });
    filaDeArquivos.clear();
  });

  const enviarFotos = async fotos => {
    const enviadas = await Promise.all(
      fotos.map(async foto => {
        const material = novoMaterial(foto, { estado: 'enviando' });
        try {
          const { data } = await AutonomiaBuilderImagesAPI.upload(foto);
          trocarMaterial(material.id, { estado: 'pronto' });
          return data.signed_id;
        } catch {
          trocarMaterial(material.id, { estado: 'atencao' });
          return null;
        }
      })
    );
    return enviadas.filter(Boolean);
  };

  // Manda um turno: abre a conversa com ele se ainda não há thread. `echo: false` não repete o
  // balão (sinal de fechar, ou reenvio do turno que já está na tela).
  const mandarTurno = ({ conteudo, extra, echo }) => {
    if (!threadId.value) {
      return store.dispatch('autonomiaBuildThreads/start', {
        ...opcoesDeInicio(),
        message: conteudo,
        ...extra,
      });
    }
    return store.dispatch('autonomiaBuildThreads/send', {
      threadId: threadId.value,
      content: conteudo,
      extra,
      ...(echo ? {} : { echo: false }),
    });
  };

  // true = o turno entrou (ou a falha virou o cartão "Tentar de novo"); false = não entrou e a tela
  // devolve o texto ao campo (ainda pensando, ou 409 da resposta anterior em andamento).
  const enviar = async ({ texto = '', anexos = [] } = {}) => {
    if (pensando.value) {
      aviso.value = 'espere';
      return false;
    }
    aviso.value = null;
    anexos.filter(arquivo => !ehFoto(arquivo)).forEach(anexarArquivo);
    const fotos = anexos.filter(ehFoto);
    const conteudo =
      texto.trim() ||
      (fotos.length ? t('AGENTS.JORNADA.CRIAR.CONTE.FOTO') : '');
    if (!conteudo) return true;

    enviando.value = true;
    try {
      const fotosEnviadas = await enviarFotos(fotos);
      const extra = fotosEnviadas.length
        ? { image_signed_ids: fotosEnviadas }
        : {};
      ultimoEnvio = { conteudo, extra, echo: true };
      await mandarTurno(ultimoEnvio);
      return true;
    } catch (error) {
      // 409: a resposta anterior ainda está sendo gerada; a store tira o eco e volta a esperar.
      if (error?.response?.status !== 409) return true;
      aviso.value = 'espere';
      return false;
    } finally {
      enviando.value = false;
    }
  };

  // O turno que não chegou volta igual (a store reusa o client_message_id dele). O eco que a store
  // deixou na tela não se repete.
  const reenviar = () => {
    const ultimaFala = (mensagensDaStore.value || []).at(-1);
    const naTela =
      ultimaFala?.role === 'user' &&
      ultimaFala.content === ultimoEnvio.conteudo;
    return mandarTurno({
      ...ultimoEnvio,
      echo: ultimoEnvio.echo && !naTela,
    }).catch(error => {
      if (error?.response?.status === 409) aviso.value = 'espere';
    });
  };

  const tentarDeNovo = () => {
    const turnoNaoChegou = erroDaStore.value === 'send';
    store.commit('autonomiaBuildThreads/SET_ERROR', null);
    if (turnoNaoChegou && ultimoEnvio) return reenviar();
    if (threadId.value) {
      return store
        .dispatch('autonomiaBuildThreads/retry', { threadId: threadId.value })
        .catch(() =>
          store.dispatch('autonomiaBuildThreads/poll', {
            threadId: threadId.value,
          })
        );
    }
    return abrir();
  };

  const sinalDeFechar = () => t('AGENTS.BUILDER.FINALIZE_SIGNAL');

  const fecharNoServidor = () => {
    if (!threadId.value || encerrando.value) return null;
    encerrando.value = true;
    ultimoEnvio = {
      conteudo: sinalDeFechar(),
      extra: { force_close: true },
      echo: false,
    };
    return store
      .dispatch('autonomiaBuildThreads/completeMaterials', {
        threadId: threadId.value,
        content: sinalDeFechar(),
      })
      .catch(() => {
        encerrando.value = false;
      });
  };

  const podeTestarAgora = computed(
    () =>
      !fechada.value &&
      !pensando.value &&
      Boolean(agenteId.value && threadId.value) &&
      respostas.value >= RESPOSTAS_PARA_FECHAR_AO_SAIR &&
      !encerrando.value
  );

  const testarAgora = () => (podeTestarAgora.value ? fecharNoServidor() : null);

  // Saindo: direto na API, porque a store é limpa logo em seguida (RESET) e a resposta do send dela
  // voltaria a encher a thread e a ligar o poll. Sem tela, a falha não tem a quem avisar: o rascunho
  // só fica sem instrução, como se a pessoa tivesse saído antes da segunda resposta.
  const encerrarAoSair = () => {
    if (fechada.value || encerrando.value || !threadId.value) return;
    if (respostas.value < RESPOSTAS_PARA_FECHAR_AO_SAIR) return;
    AutonomiaBuildThreadsAPI.sendMessage(threadId.value, sinalDeFechar(), {
      force_close: true,
    }).catch(() => null);
  };

  const tirar = material => {
    filaDeArquivos.delete(material.id);
    materiais.value = materiais.value.filter(m => m.id !== material.id);
    if (material.fonteId && agenteId.value) {
      store
        .dispatch('autonomiaSources/remove', {
          agentId: agenteId.value,
          sourceId: material.fonteId,
        })
        .catch(() => null);
    }
  };

  // Fecha (ou conta mais uma atualização) uma vez por geração: observa a fase e o agent_id da
  // thread, cada um pelo valor. A store faz SET_PHASE('reviewing') e só depois do GET do agente o
  // SET_AGENT, que não pode contar de novo. Se esse GET falhou (a store engole), o agente é lido à
  // parte: a página precisa dele para começar a atender.
  watch([() => fase.value, () => thread.value?.agent_id], ([agora, id]) => {
    if (agora !== 'reviewing' || !id) return;
    if (fechada.value && !encerrando.value) atualizacoes.value += 1;
    fechada.value = true;
    encerrando.value = false;
    if (agenteGerado.value?.id !== id) {
      store.dispatch('autonomiaAgents/show', id).catch(() => null);
    }
  });

  const pararRelogio = () => {
    if (relogioDemora) clearTimeout(relogioDemora);
    relogioDemora = null;
  };

  watch(pensando, agora => {
    pararRelogio();
    demorando.value = false;
    if (!agora) return;
    relogioDemora = setTimeout(() => {
      demorando.value = true;
    }, ESPERA_DEMORANDO_MS);
  });

  // Começo limpo e saída limpa: as stores são únicas no app (outra tela do Construtor ou da base
  // deixaria os dados dela aqui).
  const limpar = () => {
    store.dispatch('autonomiaBuildThreads/stopPolling');
    store.dispatch('autonomiaSources/stopPolling');
    store.commit('autonomiaSources/SET', []);
    store.commit('autonomiaBuildThreads/RESET');
  };

  onBeforeUnmount(() => {
    pararRelogio();
    encerrarAoSair();
    limpar();
  });

  return {
    falas,
    materiais,
    estadoDoMaterial,
    agenteId,
    agenteGerado,
    fechada,
    pensando,
    demorando,
    falhou,
    aviso,
    respostas,
    atualizacoes,
    podeTestarAgora,
    encerrando,
    limpar,
    comecar,
    continuar,
    enviar,
    tentarDeNovo,
    testarAgora,
    encerrarAoSair,
    tirar,
  };
}
