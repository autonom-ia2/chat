import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AutonomiaBuilderImagesAPI from 'dashboard/api/autonomia/builderImages';
import AutonomiaBuildThreadsAPI from 'dashboard/api/autonomia/buildThreads';
import {
  ATUACAO,
  MAX_ARQUIVO_BYTES,
  PAPEL_AJUDANTE_NA_QUERY,
} from '../constants/criacao';
import { MAX_FONTES, ehSite, nomeDaFonte } from '../utils/pagina';
import { estadoDoMaterial as estadoReal } from '../utils/estadoDoMaterial';
import { useFase2 } from './useFase2';

// #1181 PR2 — a conversa da etapa Conte com o Construtor, pela store autonomiaBuildThreads (sem
// editá-la): start/send/retry/completeMaterials, e stopPolling ao sair (a store tem um poll único).
// - A IA fala primeiro: a conversa abre só com o modelo (`type`), a atuação (externa; interna para o
//   Copiloto da equipe, #1494) e com base (arquivos sempre opcionais; o rascunho nasce na primeira
//   resposta e dá o agentId).
// - Tema 14 (#1434): `papel` (função, lida ao abrir) devolve 'ajudante' para "Ajuda outros agentes": a
//   abertura vai com `papel: 'ajudante'` e atuação interna (o agente nasce interno e com a marca de origem).
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
// - #1503 — a base de conhecimento da criação (`base`): os arquivos e sites da mesma lista do clipe
//   (fotos não entram, vão no turno). A caixa da etapa Conte e a conversa mexem nela pelas mesmas
//   funções (anexarArquivo, anexarSite, tirar): o que entra por uma aparece na outra. Site, como
//   arquivo, espera o rascunho existir. Ao continuar um rascunho, o que já estava na base volta para
//   a caixa (fora da conversa, que não mostra o histórico).
export const ESPERA_DEMORANDO_MS = 60000;
// "Agora não" / sair com pelo menos duas respostas: fecha no servidor para o rascunho ter instrução
// (mesma regra do Construtor de hoje e do protótipo: hasInstruction = closed || answers >= 2).
const RESPOSTAS_PARA_FECHAR_AO_SAIR = 2;

const ehFoto = arquivo => (arquivo?.type || '').startsWith('image/');

// Material que ocupa uma das vagas da base no servidor (Source::MAX_KNOWLEDGE_SOURCES): o que está
// lá ou a caminho. Grande demais, acima do limite ou que nem chegou a subir não ocupa.
export const ocupaVaga = material =>
  ['fila', 'enviando'].includes(material.estado) || Boolean(material.fonteId);

// "https://www.loja.com.br/precos" vira "www.loja.com.br/precos": o endereço como a pessoa o lê.
const nomeDoSite = endereco => {
  try {
    const url = new URL(endereco);
    return url.pathname === '/' ? url.host : `${url.host}${url.pathname}`;
  } catch {
    return endereco;
  }
};

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

// #1426 — na Fase 2, o estado real (utils/estadoDoMaterial) nas palavras da caixa da criação: só é "pronto" depois de
// a revisão aprovar; revisando ainda é "lendo"; reprovado ou não lido é "atenção".
const NA_CAIXA_DA_CRIACAO = {
  lendo: 'lendo',
  revisando: 'lendo',
  pronto: 'pronto',
  atencao: 'atencao',
  falha: 'atencao',
};
const estadoNaFase2 = fonte =>
  fonte ? NA_CAIXA_DA_CRIACAO[estadoReal(fonte)] : 'lendo';

export function useConversaDeCriacao({
  modelo,
  atuacao = ATUACAO.EXTERNA,
  papel = () => null,
}) {
  const store = useStore();
  const { t } = useI18n();
  const fase2 = useFase2();

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
  // A leitura da base de um rascunho continuado falhou (a caixa oferece "Tentar de novo").
  const erroDaBase = ref(false);
  // Tirar não deu certo no servidor: o item volta para a lista e a caixa avisa ({ nome }).
  const falhaAoTirar = ref(null);
  // Fontes tiradas (ou sendo tiradas): uma leitura da base em andamento não as traz de volta.
  const tiradas = new Set();
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
        .filter(m => m.naConversa !== false)
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
        (lista || []).map(fonte => [
          fonte.id,
          fase2.value ? estadoNaFase2(fonte) : estadoDaFonte(fonte),
        ])
      );
      estadosDasFontes.value = { ...estadosDasFontes.value, ...vistos };
    },
    { flush: 'sync' }
  );

  const estadoDoMaterial = material => {
    if (material.estado !== 'base') return material.estado;
    return estadosDasFontes.value[material.fonteId] || estadoDaFonte(null);
  };

  const opcoesDeInicio = () => {
    if (agenteExistente.value) return { agentId: agenteExistente.value.id };
    const ajudante = papel() === PAPEL_AJUDANTE_NA_QUERY;
    return {
      type: modelo,
      actuation: ajudante ? ATUACAO.INTERNA : atuacao,
      with_knowledge: true,
      ...(ajudante ? { papel: PAPEL_AJUDANTE_NA_QUERY } : {}),
    };
  };

  const abrir = (extra = {}) =>
    store
      .dispatch('autonomiaBuildThreads/start', {
        ...opcoesDeInicio(),
        ...extra,
      })
      .catch(() => null); // a falha fica no erro da store e vira o cartão "Tentar de novo"

  const comecar = () => abrir();

  const novoMaterial = (dados, extra) => {
    proximoMaterial += 1;
    const material = {
      id: proximoMaterial,
      ...dados,
      posicao: abertura.value.length + (mensagensDaStore.value || []).length,
      ...extra,
    };
    materiais.value = [...materiais.value, material];
    return material;
  };

  // O que já estava na base do rascunho (de outra vez) entra na caixa, nunca na conversa.
  // Uma leitura por vez: duas ao mesmo tempo poriam o mesmo arquivo duas vezes na caixa.
  let lendoBase = null;
  const lerBase = async id => {
    erroDaBase.value = false;
    try {
      const lidas = await store.dispatch('autonomiaSources/fetch', {
        agentId: id,
      });
      const conhecidas = materiais.value.map(m => m.fonteId);
      (lidas || [])
        .filter(fonte => (fonte.kind ?? 'knowledge') === 'knowledge')
        .filter(fonte => !conhecidas.includes(fonte.id))
        .filter(fonte => !tiradas.has(fonte.id))
        .forEach(fonte =>
          novoMaterial(
            {
              nome: ehSite(fonte)
                ? nomeDoSite(nomeDaFonte(fonte))
                : nomeDaFonte(fonte),
              tipo: ehSite(fonte) ? 'site' : 'arquivo',
            },
            { estado: 'base', fonteId: fonte.id, naConversa: false }
          )
        );
    } catch {
      erroDaBase.value = true;
    }
  };
  const carregarBase = () => {
    const id = agenteId.value;
    if (!id) return Promise.resolve();
    if (!lendoBase) {
      lendoBase = lerBase(id).finally(() => {
        lendoBase = null;
      });
    }
    return lendoBase;
  };

  const continuar = agente => {
    agenteExistente.value = agente;
    carregarBase();
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

  const doArquivo = arquivo => ({
    nome: arquivo.name,
    tipo: ehFoto(arquivo) ? 'foto' : 'arquivo',
  });

  // Se o servidor não tirou, o item volta (na ordem em que tinha entrado) e a caixa avisa.
  const tirarDoServidor = async material => {
    tiradas.add(material.fonteId);
    try {
      await store.dispatch('autonomiaSources/remove', {
        agentId: agenteId.value,
        sourceId: material.fonteId,
      });
    } catch {
      tiradas.delete(material.fonteId);
      materiais.value = [
        ...materiais.value.filter(m => m.id !== material.id),
        material,
      ].sort((a, b) => a.id - b.id);
      falhaAoTirar.value = { nome: material.nome };
    }
  };

  // `descritor` é { file } ou { url }, como a store espera.
  const mandarParaBase = async (material, descritor) => {
    trocarMaterial(material.id, { estado: 'enviando' });
    try {
      const fonte = await store.dispatch('autonomiaSources/create', {
        agentId: agenteId.value,
        descriptor: { ...descritor, kind: 'knowledge' },
      });
      // Tirado enquanto subia: o servidor já guardou, então sai de lá também.
      if (!materiais.value.some(m => m.id === material.id)) {
        if (fonte?.id) {
          await tirarDoServidor({
            ...material,
            estado: 'base',
            fonteId: fonte.id,
          });
        }
        return;
      }
      // A leitura da base pode ter trazido este mesmo arquivo antes da resposta: fica um só.
      materiais.value = materiais.value.filter(
        m => m.id === material.id || !fonte?.id || m.fonteId !== fonte.id
      );
      trocarMaterial(material.id, { estado: 'base', fonteId: fonte?.id });
    } catch {
      trocarMaterial(material.id, { estado: 'atencao' });
    }
  };

  // Arquivo ou site antes de existir o rascunho espera na fila ("Vou ler assim que começarmos").
  const filaDaBase = new Map();
  const paraBase = (dados, descritor) => {
    if (!agenteId.value) {
      const material = novoMaterial(dados, { estado: 'fila' });
      filaDaBase.set(material.id, descritor);
      return material;
    }
    const material = novoMaterial(dados, { estado: 'enviando' });
    mandarParaBase(material, descritor);
    return material;
  };

  const base = computed(() => materiais.value.filter(m => m.tipo !== 'foto'));
  const semVaga = () => base.value.filter(ocupaVaga).length >= MAX_FONTES;

  // Também pelo clipe da conversa: grande demais ou sem vaga não sobe (o material diz por quê).
  const anexarArquivo = arquivo => {
    if (arquivo.size > MAX_ARQUIVO_BYTES) {
      return novoMaterial(doArquivo(arquivo), { estado: 'grande' });
    }
    if (semVaga()) {
      return novoMaterial(doArquivo(arquivo), { estado: 'limite' });
    }
    return paraBase(doArquivo(arquivo), { file: arquivo });
  };

  // `endereco` já conferido (enderecoDoSite): a caixa só manda endereço válido.
  const anexarSite = endereco =>
    paraBase({ nome: nomeDoSite(endereco), tipo: 'site' }, { url: endereco });

  watch(agenteId, id => {
    if (!id) return;
    filaDaBase.forEach((descritor, materialId) => {
      const material = materiais.value.find(m => m.id === materialId);
      if (material) mandarParaBase(material, descritor);
    });
    filaDaBase.clear();
  });

  const enviarFotos = async fotos => {
    const enviadas = await Promise.all(
      fotos.map(async foto => {
        const material = novoMaterial(doArquivo(foto), { estado: 'enviando' });
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
    falhaAoTirar.value = null;
    filaDaBase.delete(material.id);
    materiais.value = materiais.value.filter(m => m.id !== material.id);
    if (material.fonteId && agenteId.value) return tirarDoServidor(material);
    return Promise.resolve();
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
    base,
    erroDaBase,
    falhaAoTirar,
    carregarBase,
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
    anexarArquivo,
    anexarSite,
    tirar,
  };
}
