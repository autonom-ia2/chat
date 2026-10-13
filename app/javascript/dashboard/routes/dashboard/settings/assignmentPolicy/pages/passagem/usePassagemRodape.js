import { computed, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import {
  ETAPA_PROPRIA,
  faltaParaQuem,
  faltaPessoa,
  faltaQuemRecebe,
} from './passagem';

// #1385 — o rodapé de cada tela, como no funil (#1384): cada tela de detalhe tem "Cancelar" e "Salvar", e "Salvar"
// grava na hora e volta. O resumo nunca fica com nada por salvar: tem só "Fechar" (cinza) e, depois de salvar, o
// aviso "Salvo". A lista de etapas não muda nada sozinha: tem só "Voltar".
const R = 'CRM_KANBAN.PASSAGEM.RODAPE';

const irAoErro = async () => {
  await nextTick();
  document
    .querySelector('[data-passagem] [role="alert"]')
    ?.scrollIntoView({ block: 'center', behavior: 'smooth' });
};

// Quem salva pela tela "Como entregar" fica com o que ela promete: a assistente segura a conversa até alguém ficar
// online (prefer_online). A regra antiga, que entrega para quem está fora, não é oferecida aqui.
const comOnline = regra => ({ ...regra, prefer_online: true });

export function usePassagemRodape({
  passagem,
  view,
  passo,
  etapa,
  funilId,
  mostrarErros,
  irPara,
  fechar,
  t,
}) {
  const { regra, salvando, salvoAgora } = passagem;

  const barrar = falta => {
    if (!falta) return false;
    mostrarErros.value = true;
    irAoErro();
    return true;
  };

  const destinoDe = () => (view.value === 'etapa' ? 'etapas' : 'home');

  const cancelar = () => {
    passagem.restaurarCopia();
    irPara(destinoDe(), { guardar: false });
  };

  const gravar = async () => {
    const destino = destinoDe();
    const deuCerto = await passagem.salvar(funilId.value);
    if (!deuCerto) {
      useAlert(t('CRM_KANBAN.PASSAGEM.ERRO_SALVAR'));
      return;
    }
    passagem.descartarCopia();
    irPara(destino, { guardar: false });
  };

  // O que falta conferir antes de gravar, e o ajuste do "Como entregar".
  const salvarDetalhe = () => {
    if (view.value === 'quem' && barrar(faltaQuemRecebe(regra.value))) return;
    if (view.value === 'como') {
      if (barrar(faltaParaQuem(regra.value))) return;
      regra.value = comOnline(regra.value);
    }
    gravar();
  };

  const salvarEtapa = () => {
    const atual = etapa.value;
    if (atual?.modo === ETAPA_PROPRIA) {
      if (barrar(faltaPessoa(atual.regra))) return;
      etapa.value = { ...atual, regra: comOnline(atual.regra) };
    }
    gravar();
  };

  const botaoSalvar = acao =>
    salvando.value
      ? {
          rotulo: t(`${R}.SALVANDO`),
          icone: 'i-lucide-check',
          carregando: true,
          acao: () => {},
        }
      : { rotulo: t(`${R}.SALVAR`), icone: 'i-lucide-check', acao };

  const rodapeDoResumo = () => {
    const principal = {
      rotulo: t(`${R}.FECHAR`),
      neutro: true,
      acao: fechar,
    };
    if (salvando.value) {
      return {
        principal,
        status: {
          texto: t(`${R}.SALVANDO`),
          icone: 'i-lucide-loader-circle animate-spin',
          tom: 'text-n-slate-11',
        },
      };
    }
    if (!salvoAgora.value) return { principal };
    return {
      principal,
      status: {
        texto: t(`${R}.SALVO`),
        icone: 'i-lucide-circle-check',
        tom: 'text-n-teal-11',
      },
    };
  };

  const rodapeDaEtapa = () => {
    const propria = etapa.value?.modo === ETAPA_PROPRIA;
    const secundaria =
      passo.value > 0
        ? {
            rotulo: t(`${R}.VOLTAR`),
            acao: () => {
              passo.value -= 1;
            },
          }
        : { rotulo: t(`${R}.CANCELAR`), acao: cancelar };
    if (propria && passo.value < 3) {
      const acao = () => {
        if (passo.value === 2 && barrar(faltaQuemRecebe(etapa.value.regra))) {
          return;
        }
        mostrarErros.value = false;
        passo.value += 1;
      };
      return {
        principal: {
          rotulo: t(`${R}.CONTINUAR`),
          icone: 'i-lucide-arrow-right',
          depois: true,
          acao,
        },
        secundaria,
      };
    }
    return { principal: botaoSalvar(salvarEtapa), secundaria };
  };

  const rodape = computed(() => {
    if (view.value === 'home') return rodapeDoResumo();
    if (view.value === 'etapas') {
      return {
        principal: {
          rotulo: t(`${R}.VOLTAR`),
          neutro: true,
          acao: () => irPara('home', { guardar: false }),
        },
      };
    }
    if (view.value === 'etapa') return rodapeDaEtapa();
    return {
      principal: botaoSalvar(salvarDetalhe),
      secundaria: { rotulo: t(`${R}.CANCELAR`), acao: cancelar },
    };
  });

  // A seta do herói: na lista de etapas volta ao resumo; numa tela de detalhe é o mesmo que "Cancelar".
  const voltar = () => {
    if (view.value === 'etapas') {
      irPara('home', { guardar: false });
      return;
    }
    cancelar();
  };

  return { rodape, voltar };
}
