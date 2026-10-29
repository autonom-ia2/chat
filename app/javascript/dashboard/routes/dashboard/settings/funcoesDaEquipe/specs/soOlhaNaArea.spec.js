import { mount } from '@vue/test-utils';
import {
  CONVERSATION_LEVELS,
  LEVELS,
  MODULES,
  PRESETS,
  getLevel,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { areasDaRecolhida, resumoDaRecolhida } from '../areasDaFuncao';
import { fraseDaFuncao, podeDaFuncao, queMudam } from '../fraseDaFuncao';
import { escolherNivelDeVendas, nivelDeVendas } from '../nivelDeVendas';
import { podeCurto } from '../podeCurto';
import { chavesEfetivas } from '../semFuncao';
import AjustesDaFuncao from '../guiada/AjustesDaFuncao.vue';
import ComoVaiFicar from '../guiada/ComoVaiFicar.vue';
import CartaoDaFuncao from '../components/CartaoDaFuncao.vue';
import { global } from './montar';
import { ADMIN } from './quemMonta';

// #2308: "Só olha" numa área só quando nada do que a função pode nela muda ou leva algo para fora. A mesma regra da
// Perda de acesso vale na frase, no cartão da lista, na prévia, em Ajustes e nos cartões prontos.
const contem = (texto, trecho) => texto.toLowerCase().includes(trecho);
const SO_OLHA = 'só olha';

const ajustes = permissions =>
  mount(AjustesDaFuncao, {
    props: {
      titulo: 'Quer mudar alguma coisa?',
      dica: 'Dica',
      permissions,
      inicial: permissions,
      giver: ADMIN,
    },
    global: global(),
  });
const previa = permissions =>
  mount(ComoVaiFicar, {
    props: { nome: 'Atendente', permissions, inicial: permissions },
    global: global(),
  })
    .find('[data-frase]')
    .text();
const cartao = permissions =>
  mount(CartaoDaFuncao, {
    props: {
      funcao: { id: 1, name: 'Atendente', permissions },
      tom: 'bg-n-blue-3 text-n-blue-11',
    },
    global: global(),
  }).text();

const ATENDENTE = PRESETS.AGENT();
const VENDAS_SO_OLHA = escolherNivelDeVendas(LEVELS.VIEW, ATENDENTE);

describe('"Só olha" só quando nada muda na área', () => {
  describe('Atendente que leva os contatos para uma planilha', () => {
    const comExportar = [...ATENDENTE, 'contact_export'];

    it('a frase diz "Vê os contatos."', () => {
      expect(fraseDaFuncao(comExportar).resto).toContain('CONTATOS_VE');
      expect(fraseDaFuncao(comExportar).resto).not.toContain(
        'CONTATOS_SO_OLHA'
      );
    });

    it('a prévia, o cartão e a linha Contatos de Ajustes não dizem "só olha"', () => {
      expect(previa(comExportar)).toContain('Vê os contatos.');
      expect(contem(previa(comExportar), SO_OLHA)).toBe(false);
      expect(contem(cartao(comExportar), SO_OLHA)).toBe(false);
      const linha = ajustes(comExportar).find('[data-linha="contatos"]').text();
      expect(contem(linha, SO_OLHA)).toBe(false);
      expect(linha).toContain('Vê');
    });

    it('o cartão pronto diz "Vê os contatos"', () => {
      const chaves = podeCurto(comExportar).map(item => item.chave);
      expect(chaves).toContain('VE_CONTATOS');
      expect(chaves).not.toContain('SO_OLHA_CONTATOS');
    });

    it('controle: sem levar para a planilha, continua "Só olha os contatos."', () => {
      expect(fraseDaFuncao(ATENDENTE).resto).toContain('CONTATOS_SO_OLHA');
      expect(previa(ATENDENTE)).toContain('Só olha os contatos.');
      expect(cartao(ATENDENTE)).toContain('Só olha os contatos.');
      expect(
        ajustes(ATENDENTE).find('[data-linha="contatos"]').text()
      ).toContain('Só olha');
      expect(podeCurto(ATENDENTE).map(item => item.chave)).toContain(
        'SO_OLHA_CONTATOS'
      );
    });
  });

  describe.each(['crm_manage_pipelines', 'crm_export', 'crm_manage_ai'])(
    'Vendas em "Só olha" com %s',
    chave => {
      const comChave = [...VENDAS_SO_OLHA, chave];

      it('a frase diz "Vê as vendas."; prévia, cartão e Ajustes sem "só olha"', () => {
        expect(nivelDeVendas(comChave)).toBe(LEVELS.VIEW);
        expect(fraseDaFuncao(comChave).resto).toContain('VENDAS_VE');
        expect(fraseDaFuncao(comChave).resto).not.toContain('VENDAS_SO_OLHA');
        expect(previa(comChave)).toContain('Vê as vendas.');
        expect(cartao(comChave)).not.toContain('Só olha as vendas.');
        const linha = ajustes(comChave).find('[data-linha="vendas"]').text();
        expect(contem(linha, SO_OLHA)).toBe(false);
        expect(linha).toContain('Vê');
      });
    }
  );

  it('controle: Vendas em "Só olha" sem nada a mais continua "Só olha as vendas."', () => {
    expect(fraseDaFuncao(VENDAS_SO_OLHA).resto).toContain('VENDAS_SO_OLHA');
    expect(previa(VENDAS_SO_OLHA)).toContain('Só olha as vendas.');
    expect(cartao(VENDAS_SO_OLHA)).toContain('Só olha as vendas.');
    expect(
      ajustes(VENDAS_SO_OLHA).find('[data-linha="vendas"]').text()
    ).toContain('Só olha');
  });

  // Os relatórios de atendimento contam como ver (Rodrigo, 28/10).
  it('Só consulta: só olha contatos, vendas, campanhas e relatórios', () => {
    expect(podeCurto(PRESETS.READ_ONLY())).toEqual([
      {
        chave: 'SO_OLHA_AREAS',
        tipo: 'soOlha',
        areas: ['CONTACTS', 'CRM', 'CAMPAIGNS', 'REPORTS'],
      },
      { chave: 'NAO_ATENDE', tipo: 'naoFaz' },
    ]);
  });
});

// A classe inteira: toda pronta, toda área com nível de ver, sem nada a mais e com cada chave da área ligada.
// O oráculo não chama soOlhaNaArea: compara o que muda ou leva algo com a área e sem ela.
const mudaNaArea = (area, permissions) => {
  const com = queMudam(podeDaFuncao(chavesEfetivas(permissions)));
  const sem = queMudam(
    podeDaFuncao(
      chavesEfetivas(setLevel(moduleByKey(area), LEVELS.NONE, permissions))
    )
  );
  return com.some(id => !sem.includes(id));
};

const nivelDaArea = (area, permissions) =>
  area === 'CRM'
    ? nivelDeVendas(permissions)
    : getLevel(moduleByKey(area), permissions);

const AREAS_DE_VER = MODULES.filter(
  module => module.type === 'conversations' || module.levels?.view
);

const variantes = (base, module) => {
  const naView = setLevel(
    module,
    LEVELS.VIEW,
    setLevel(module, LEVELS.NONE, base)
  );
  const extras = (module.extras || []).map(chave => [
    ...new Set([...naView, chave]),
  ]);
  return [naView, ...extras].filter(
    permissions =>
      nivelDaArea(module.key, permissions) === LEVELS.VIEW ||
      nivelDaArea(module.key, permissions) === CONVERSATION_LEVELS.VIEW
  );
};

const CASOS = Object.entries(PRESETS).flatMap(([pronta, preset]) =>
  AREAS_DE_VER.flatMap(module =>
    variantes(preset(), module).map(permissions => ({
      pronta,
      area: module.key,
      permissions,
    }))
  )
);

const FRASE_SO = {
  CONVERSATIONS: 'SO_OLHA_CONVERSAS',
  CONTACTS: 'CONTATOS_SO_OLHA',
  CRM: 'VENDAS_SO_OLHA',
};
const FRASE_VE = {
  CONVERSATIONS: 'VE_CONVERSAS',
  CONTACTS: 'CONTATOS_VE',
  CRM: 'VENDAS_VE',
};
const CURTO_SO = {
  CONVERSATIONS: 'SO_OLHA_CONVERSAS',
  CONTACTS: 'SO_OLHA_CONTATOS',
};
const CURTO_VE = { CONVERSATIONS: 'VE_CONVERSAS', CONTACTS: 'VE_CONTATOS' };
const LINHA = {
  CONVERSATIONS: 'conversas',
  CONTACTS: 'contatos',
  CRM: 'vendas',
};

const falaDaArea = (itens, area, chave, deAreas) =>
  itens.some(
    item =>
      item.chave === chave ||
      (item.chave === deAreas && item.areas.includes(area))
  );

describe('classe: nenhuma tela diz "só olha" quando algo ainda muda na área', () => {
  it('há casos das duas espécies', () => {
    expect(CASOS.some(c => mudaNaArea(c.area, c.permissions))).toBe(true);
    expect(CASOS.some(c => !mudaNaArea(c.area, c.permissions))).toBe(true);
  });

  it.each(CASOS)('$pronta, $area: $permissions', ({ area, permissions }) => {
    const muda = mudaNaArea(area, permissions);

    // Frase da função (cartão da lista e prévia).
    if (FRASE_SO[area]) {
      const { destaque, resto } = fraseDaFuncao(permissions);
      const chaves = [destaque, ...resto];
      expect(chaves.includes(FRASE_SO[area])).toBe(!muda);
      if (!muda) expect(chaves).not.toContain(FRASE_VE[area]);
    }

    // Cartões prontos: "só olha" nunca fala de uma área que muda; "vê" nunca de uma que só olha.
    const curtos = podeCurto(permissions);
    const curtoSo = falaDaArea(curtos, area, CURTO_SO[area], 'SO_OLHA_AREAS');
    const curtoVe = falaDaArea(curtos, area, CURTO_VE[area], 'VE_AREAS');
    expect(muda ? curtoSo : curtoVe).toBe(false);

    // Ajustes: a linha fixa da área e o estado da recolhida.
    const wrapper = ajustes(permissions);
    if (LINHA[area]) {
      const linha = wrapper.find(`[data-linha="${LINHA[area]}"]`).text();
      expect(contem(linha, SO_OLHA)).toBe(!muda);
    }
    const { recolhidas } = areasDaRecolhida({
      giver: ADMIN,
      permissions,
      inicial: permissions,
      comCotacoes: false,
    });
    const { olha } = resumoDaRecolhida(recolhidas, permissions);
    if (olha.includes(area)) {
      const algumaMuda = olha.some(chave => mudaNaArea(chave, permissions));
      const recolhida = wrapper.find('[data-recolhida]').text();
      expect(contem(recolhida, SO_OLHA)).toBe(!algumaMuda);
    }
    wrapper.unmount();
  });
});
