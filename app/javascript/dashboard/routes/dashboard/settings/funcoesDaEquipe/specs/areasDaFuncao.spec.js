import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  MODULES,
  PRESETS,
  getLevel,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import {
  CONDICIONAL,
  CUIDADO,
  DENTRO_DE,
  DONO_DAS_CHAVES,
  LINHAS,
  RECOLHIDA,
  SO_ADMIN,
  areasDaRecolhida,
  gruposDoCuidado,
  ligaAgora,
  ligaJunto,
  resumoDaRecolhida,
  travaDoNivel,
} from '../areasDaFuncao';
import { chavesDoServidor } from '../semFuncao';
import {
  ADMIN,
  CARLA,
  CARLA_SEM_DISPARO,
  SEM_VER_VENDAS,
  TUDO_SEM_MEXER,
} from './quemMonta';

// #2308, especificação 6 e 7: o mapa fechado (24/24 módulos, 59/59 chaves), a recolhida e o Cuidado em três grupos.
const permissoesDoServidor = () => {
  const fonte = readFileSync(
    resolve(process.cwd(), 'enterprise/app/models/custom_role.rb'),
    'utf8'
  );
  const inicio =
    fonte.indexOf('PERMISSIONS = %w[') + 'PERMISSIONS = %w['.length;
  return fonte
    .slice(inicio, fonte.indexOf('].freeze', inicio))
    .split('\n')
    .flatMap(linha => linha.trim().split(' '))
    .filter(Boolean);
};

describe('mapa das áreas e chaves', () => {
  it('24/24 módulos têm lugar, sem repetir', () => {
    const lugares = [
      ...LINHAS,
      ...Object.keys(DENTRO_DE),
      ...RECOLHIDA,
      ...CONDICIONAL,
      ...SO_ADMIN,
    ];
    expect(lugares).toHaveLength(24);
    expect(new Set(lugares)).toEqual(new Set(MODULES.map(m => m.key)));
  });

  it('59/59 chaves de CustomRole::PERMISSIONS têm dono, sem repetir', () => {
    const donas = Object.values(DONO_DAS_CHAVES).flat();
    const servidor = permissoesDoServidor();

    expect(servidor).toHaveLength(59);
    expect(donas).toHaveLength(59);
    expect(new Set(donas)).toEqual(new Set(servidor));
  });
});

describe('recolhida de Ajustes (Carla + Atendente)', () => {
  const atendente = PRESETS.AGENT();

  // A Central de Ajuda saiu das telas de função (#2352); o exemplo de "só olha" passa a ser o Desempenho da equipe.
  it('título e estado: duas primeiras + "mais 10"; só olha o Desempenho da equipe', () => {
    const comDesempenho = setLevel(
      moduleByKey('DESEMPENHO'),
      'view',
      atendente
    );
    const areas = areasDaRecolhida({
      giver: CARLA,
      permissions: comDesempenho,
      inicial: comDesempenho,
      comCotacoes: false,
    });
    expect(areas.subiram).toEqual([]);
    // Seus posts (#2302): a Carla não tem posts_view, então a área inteira fica fora do alcance dela.
    expect(areas.cadeado.map(m => m.key)).toEqual(['POSTS', ...SO_ADMIN]);
    expect(resumoDaRecolhida(areas.recolhidas, comDesempenho)).toEqual({
      primeiras: ['REPORTS', 'DESEMPENHO'],
      mais: 10,
      olha: ['DESEMPENHO'],
      mexe: [],
    });
  });

  it('a área mudada sobe e o título se refaz', () => {
    const comRelatorios = setLevel(moduleByKey('REPORTS'), 'view', atendente);
    const areas = areasDaRecolhida({
      giver: CARLA,
      permissions: comRelatorios,
      inicial: atendente,
      comCotacoes: false,
    });
    expect(areas.subiram.map(m => m.key)).toEqual(['REPORTS']);
    expect(resumoDaRecolhida(areas.recolhidas, comRelatorios)).toMatchObject({
      primeiras: ['DESEMPENHO', 'CANNED_RESPONSES'],
      mais: 9,
    });
  });

  it('para o administrador, Integrações, Equipe e Financeiro entram como as outras', () => {
    const areas = areasDaRecolhida({
      giver: ADMIN,
      permissions: atendente,
      inicial: atendente,
      comCotacoes: true,
    });
    expect(areas.cadeado).toEqual([]);
    expect(areas.recolhidas).toHaveLength(17);
  });

  it('Anúncios: "Pode mexer" com cadeado de delegação; Cotações: as duas com MISSING', () => {
    const anuncios = moduleByKey('META_ADS');
    const cotacoes = moduleByKey('INSURANCE');
    expect(travaDoNivel(CARLA, anuncios, 'view')).toBeNull();
    expect(travaDoNivel(CARLA, anuncios, 'manage')).toBe('DELEGATION');
    expect(travaDoNivel(CARLA, cotacoes, 'view')).toBe('MISSING');
    expect(travaDoNivel(CARLA, cotacoes, 'manage')).toBe('MISSING');
    expect(travaDoNivel(ADMIN, anuncios, 'manage')).toBeNull();
  });
});

describe('Cuidado em três grupos', () => {
  const chaves = itens => itens.map(item => item.chave);

  it('Carla + Atendente = tabela da especificação 7.2', () => {
    const grupos = gruposDoCuidado(CARLA, PRESETS.AGENT());

    expect(chaves(grupos.ligaJunto)).toEqual([
      'contact_delete',
      'campaign_send',
    ]);
    expect(chaves(grupos.ligaAgora)).toEqual([
      'contact_export',
      'conversation_message_delete',
      'crm_manage_ai',
    ]);
    expect(grupos.naoPode).toEqual([
      expect.objectContaining({ chave: 'crm_export', motivo: 'MISSING' }),
      expect.objectContaining({
        chave: 'crm_metas_manage',
        motivo: 'DELEGATION',
      }),
    ]);
  });

  // Os predicados, não os grupos: grupoDe testa (b) antes de (a), então comparar os grupos nunca acharia uma chave nos
  // dois. Aqui cada par quem monta × função × chave confere que ligaJunto e ligaAgora nunca valem ao mesmo tempo.
  it('"liga junto" e "liga agora" nunca valem juntos para a mesma chave', () => {
    const quemMonta = [CARLA, ADMIN, CARLA_SEM_DISPARO];
    const funcoes = Object.values(PRESETS).map(preset => preset());
    const juntos = quemMonta.flatMap(giver =>
      funcoes.flatMap(funcao =>
        CUIDADO.filter(
          item =>
            ligaJunto(giver, item, funcao) && ligaAgora(giver, item, funcao)
        ).map(item => item.chave)
      )
    );
    expect(juntos).toEqual([]);
  });

  it('apagar contatos com Contatos só em ver: não liga agora, liga junto com Mexer', () => {
    const item = CUIDADO.find(linha => linha.chave === 'contact_delete');
    expect(ligaAgora(CARLA, item, PRESETS.AGENT())).toBe(false);
    expect(ligaJunto(CARLA, item, PRESETS.AGENT())).toBe(true);
  });

  it('metas sem R$, para o administrador: grupo (b), porque o R$ entra junto', () => {
    const semRs = PRESETS.SDR().filter(chave => chave !== 'sales_value_view');
    const { ligaJunto: junto } = gruposDoCuidado(ADMIN, semRs);
    expect(chaves(junto)).toContain('crm_metas_manage');
  });

  it('com a área já em manage, a mesma chave liga agora', () => {
    const comContatos = setLevel(
      moduleByKey('CONTACTS'),
      'manage',
      PRESETS.AGENT()
    );
    expect(chaves(gruposDoCuidado(CARLA, comContatos).ligaAgora)).toContain(
      'contact_delete'
    );
    expect(getLevel(moduleByKey('CONTACTS'), comContatos)).toBe('manage');
  });

  it('sem disparar campanhas, a Carla vê 3 coisas no cadeado', () => {
    const grupos = gruposDoCuidado(CARLA_SEM_DISPARO, PRESETS.AGENT());
    expect(chaves(grupos.naoPode)).toEqual([
      'campaign_send',
      'crm_export',
      'crm_metas_manage',
    ]);
  });

  // Rodada 4: o alcance é o do servidor (gravadas + implicadas), não o que o crm_admin dá.
  it('função com crm_admin: o alcance conta as chaves gravadas, não as que o crm_admin dá', () => {
    const outra = ['contact_view', 'crm_view', 'crm_admin'];
    const grupos = gruposDoCuidado(TUDO_SEM_MEXER, outra);
    expect(chaves(grupos.ligaJunto)).toContain('contact_delete');
    expect(chaves(grupos.naoPode)).not.toContain('contact_delete');
  });

  // Rodada 5: chamado como a tela chama (PerguntaCuidado: as chaves lidas pelo servidor como terceiro argumento), com
  // funções que têm crm_admin.
  it('todo item no cadeado tem motivo', () => {
    const comoATela = (giver, permissions) =>
      gruposDoCuidado(giver, permissions, chavesDoServidor(permissions));
    const funcoes = [
      ...Object.values(PRESETS).map(preset => preset()),
      [...PRESETS.AGENT(), 'contact_manage', 'crm_admin'],
      ['contact_view', 'crm_view', 'crm_admin'],
    ];
    const motivos = [CARLA, CARLA_SEM_DISPARO, SEM_VER_VENDAS, TUDO_SEM_MEXER]
      .flatMap(giver =>
        funcoes.flatMap(permissions => comoATela(giver, permissions).naoPode)
      )
      .map(item => item.motivo);
    expect(motivos.length).toBeGreaterThan(0);
    motivos.forEach(motivo => expect(motivo).toBeTruthy());
  });

  it('o administrador liga tudo; quem não atende conversas não vê "Apagar mensagens"', () => {
    const grupos = gruposDoCuidado(ADMIN, PRESETS.MARKETING());
    expect(grupos.naoPode).toEqual([]);
    expect([
      ...chaves(grupos.ligaJunto),
      ...chaves(grupos.ligaAgora),
    ]).not.toContain('conversation_message_delete');
  });
});
