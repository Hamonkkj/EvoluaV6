-- ============================================================
-- V5 — EVOLUTION CELL
-- Arquivo único: main.lua
-- Seções marcadas com ── N. NOME ──
-- ============================================================

-- ── 1.1 CONFIGURAÇÃO BASE ────────────────────────────────
 
VW, VH = 960, 540            -- resolução virtual
BASE_H = 540
DT_MAX = 1/30                -- clamp do dt (evita física explodir)

function ajustarResolucaoVirtual()
  local ww, wh = love.graphics.getDimensions()
  local aspect = ww / wh
  VH = BASE_H
  VW = math.floor(VH * aspect)
  VW = VW - (VW % 2)   -- arredonda pra par (evita serrilhado)

  -- reposiciona botões do touch/mobile que usam VW/VH
  if INPUT then
    INPUT.joystickArea = {x=90, y=VH-100, r=70}
    INPUT.botaoHab     = {x=VW-90, y=VH-100, r=48}
    INPUT.botaoPausa   = {x=VW-40, y=40, r=22}
  end

  reposicionarBotoesHUD()
end

-- Balance global (item 7 da sua lista)
BAL = {
  player = {
  baseHp      = 100,
  baseSpeed   = 220,
  baseDmg     = 6,
  baseSize    = 14,
  xpToLevel   = 40,
  levelCurve  = 1.18,
  iframes     = 0.6,
  hpRegen     = 0.3,
  atkRange    = 160,     -- alcance do ataque automatico
  atkCooldown = 0.7,     -- segundos entre ataques
  atkDmgMult  = 1.0,     -- multiplicador do dano (sobe com parts)
},
  npc = {
    baseHp      = 30,
    baseSpeed   = 70,
    baseDmg     = 5,
    baseSize    = 12,
    xpDrop      = 12,
    eliteMult   = 3.3,       -- elite = 3.3x HP, dá 40 xp
  },
  boss = {
    phaseThresholds = {0.70, 0.40},  -- 3 fases por boss (100-70, 70-40, 40-0)
    invulnOnPhase   = 1.2,           -- pausa curta na transição
    enrageMult      = 1.35,          -- buff de dano na fase 3
  },
  predator = {               -- item 11 — balanceado
    spawnEvery   = 8 * 60,   -- a cada 8 minutos (em segundos)
    hpMult       = 4.0,
    dmgMult      = 1.6,
    speedMult    = 1.15,
    slashRange   = 180,
    slashCd      = 3.0,
    slashTelegraph = 0.9,    -- tempo do aviso antes do slash
  },
  npcMass = {
      spawnIntervalo = 1.0,
      spawnPorWave = 3,
      cap = 80,
      raioAgressao = 350,
   },   
  killStreak = {             -- item 5 — volta
    window   = 5.0,          -- tempo pra manter streak
    tiers    = {             -- kills -> bônus
      {kills=5,  xp=50,  buff="speed",  mult=1.2, dur=6},
      {kills=10, xp=120, buff="damage", mult=1.35, dur=8},
      {kills=20, xp=300, buff="god",    mult=1.6, dur=10},
    },
  },
  comportamento = {
  tempoAgressivo   = 5.0,
  tempoFrustracao = 8.0,   -- se ficar 8s agressivo sem acertar o player, desiste
  -- NPC vs NPC (ecossistema)
  raioCaca      = 320,     -- alcance pra procurar alvo
  danoNpcNpc    = 0.6,     -- NPCs dão 60% do dano entre si
  cdCaca        = 0.6,     -- segundos entre mordidas
  tempoCacaMax  = 15.0,    -- desiste do alvo após 15s
  tempoAlerta      = 5.0,
  tempoMemoria     = 12.0,
  raioAlerta       = 220,
  maxAlertados     = 3,
  maxPerseguindo   = 5,
  limiarFuga       = 0.75,
  limiarPerigo     = 1.30,
  velocidadePassiva = 35,
  velocidadeFuga    = 110,
  raioFuga          = 160,
  maxAgressivosTrait = 3,
},
}
-- ── ESTADOS DE COMPORTAMENTO DOS NPCs ───────────────────

ESTADO = {
  PASSIVO   = "passivo",
  ALERTA    = "alerta",
  AGRESSIVO = "agressivo",
  FUGINDO   = "fugindo",
  CACANDO = "cacando",
}

ESTADO_COR = {
  [ESTADO.PASSIVO]   = {0.45, 0.95, 0.55},
  [ESTADO.ALERTA]    = {1.00, 0.85, 0.30},
  [ESTADO.AGRESSIVO] = {1.00, 0.35, 0.35},
  [ESTADO.FUGINDO]   = {0.45, 0.75, 1.00},
  [ESTADO.CACANDO]   = {1.00, 0.60, 0.20},   -- ← NOVO (laranja)
}

NPCsPerseguindo = 0

-- ── ESTADOS DE CONTROLE ─────────────────────────────────
autoAtaque   = true
dashCd       = 0
DASH_CD_MAX  = 2.0
DASH_DUR     = 0.18
DASH_FORCE   = 520

-- ── INDICADOR DE BOSS OFF-SCREEN ────────────────────────
BOSS_ARROW = {
  margem  = 40,        -- distância da borda
  tamanho = 22,        -- tamanho da seta
  cor     = {1, 0.25, 0.25},
  corPredador = {1, 0.15, 0.15},   -- predador pisca mais
}

-- ── TELEGRAPH DE BOSSES (V6) ────────────────────────────
TELEGRAPH = {
  cor       = {1, 0.3, 0.3},
  corEnrage = {1, 0.1, 0.1},     -- fase 3
  -- chance de feint (ataque falso)
  feintChanceF2 = 0.30,
  feintChanceF3 = 0.50,
  -- combo sequencial na fase 3
  comboChanceF3 = 0.60,
  comboDelay    = 0.4,
}

-- ── AVISO DE BOSS ───────────────────────────────────────
BOSS_WARN = {
  ativo      = false,
  t          = 0,
  dur        = 3.0,        -- duração do aviso
  nome       = "",
  bossId     = nil,
  fase       = nil,
  cor        = {1, 0.2, 0.2},
}

-- ── TRANSIÇÃO DE FASE ───────────────────────────────────
TRANSICAO = {
  ativo = false,
  t     = 0,
  dur   = 3.0,
  nomeFase = "",
  subFase  = "",
  proxFase = nil,      -- qual fase vai carregar depois
  pular    = false,
}

-- adaptação do boss: acumula pra onde o player desvia
desvioBias = 0   -- -1 (sempre esquerda) a +1 (sempre direita)

-- ── EFEITOS DE NÍVEL UP ─────────────────────────────────
NIVEL_UP = {
  flash    = 0,      -- 0..1 (flash dourado na tela)
  texto    = nil,    -- {nivel=X, t=0, dur=1.2}
}

-- ── MINIMAP ─────────────────────────────────────────────
MINIMAP = {
  x = 0, y = 0,        -- posição (calculada em runtime)
  w = 160, h = 160,    -- tamanho
  ativo = false,
}

-- ── BOTÕES DO HUD ───────────────────────────────────────
BOTOES_HUD = {
  pause = {x=0, y=0, r=22, label="II"},
  auto  = {x=0, y=0, r=26, label="AUTO"},
  evo   = {x=0, y=0, r=30, label="EVO"},
  dash  = {x=0, y=0, r=44, label="DASH"},
  hab   = {x=0, y=0, r=44, label=""},
}

function reposicionarBotoesHUD()
  BOTOES_HUD.pause.x, BOTOES_HUD.pause.y = VW-40, 40
  BOTOES_HUD.auto.x,  BOTOES_HUD.auto.y  = VW-76, 100
  BOTOES_HUD.evo.x,   BOTOES_HUD.evo.y   = VW-76, 168
  BOTOES_HUD.dash.x,  BOTOES_HUD.dash.y  = VW-90, VH-100
  BOTOES_HUD.hab.x,   BOTOES_HUD.hab.y   = VW-200, VH-100

  if INPUT then
    INPUT.botaoPausa = BOTOES_HUD.pause
    INPUT.botaoHab   = BOTOES_HUD.hab
  end
end

-- ── MENU EVO ────────────────────────────────────────────
MENU_EVO = {
  ativo = false,
  aba = "upgrades",
  pagina = 1,
  itensPorPagina = 6,
  hover = nil,
}

-- ── MISSOES ─────────────────────────────────────────────
MISSOES_ATIVAS = {}
MISSOES_POOL = {
  { id="mate10", txt="Mate 10 criaturas",  alvo=10,  tipo="kill", recompensa={xp=80,  dna=3} },
  { id="mate25", txt="Mate 25 criaturas",  alvo=25,  tipo="kill", recompensa={xp=180, dna=6} },
  { id="mate50", txt="Mate 50 criaturas",  alvo=50,  tipo="kill", recompensa={xp=350, dna=12} },
  { id="dna100", txt="Colete 100 DNA",     alvo=100, tipo="dna",  recompensa={xp=120, dna=5} },
  { id="dna200", txt="Colete 200 DNA",     alvo=200, tipo="dna",  recompensa={xp=250, dna=10} },
  { id="bau5",   txt="Abra 5 baus",        alvo=5,   tipo="bau",  recompensa={xp=100, dna=4} },
  { id="bau15",  txt="Abra 15 baus",       alvo=15,  tipo="bau",  recompensa={xp=280, dna=9} },
  { id="boss1",  txt="Derrote 1 boss",     alvo=1,   tipo="boss", recompensa={xp=200, dna=8} },
  { id="boss3",  txt="Derrote 3 bosses",   alvo=3,   tipo="boss", recompensa={xp=500, dna=15} },
}

function reposicionarBotoesHUD()
  BOTOES_HUD.pause.x, BOTOES_HUD.pause.y = VW-40, 40
  BOTOES_HUD.auto.x,  BOTOES_HUD.auto.y  = VW-76, 100
  BOTOES_HUD.evo.x,   BOTOES_HUD.evo.y   = VW-76, 168
  BOTOES_HUD.dash.x,  BOTOES_HUD.dash.y  = VW-90, VH-100
  BOTOES_HUD.hab.x,   BOTOES_HUD.hab.y   = VW-200, VH-100

  -- compat: mantém INPUT.botao* atualizado pra não quebrar código antigo
  if INPUT then
    INPUT.botaoPausa = BOTOES_HUD.pause
    INPUT.botaoHab   = BOTOES_HUD.hab
  end
end

-- ── 1.2 NASCIMENTOS (12) + HABILIDADES ÚNICAS ────────────
-- Cada nascimento tem stats próprios e UMA habilidade ativa.
-- A habilidade é acionada com ESPAÇO (ou botão na tela no mobile).
-- Efeitos são resolvidos na Parte 10 por id.

BIRTHS = {
  {
    id = "natural",
    name = "Natural",
    desc = "Célula comum. Equilibrada em tudo.",
    color = {0.55, 0.85, 0.55},
    stats = {hp=100, speed=110, dmg=6, size=14, xpGain=1.00},
    ability = {
      id="boom", name="Boom", desc="Explosão em área ao redor.",
      cd=8, dur=0.35, color={1, 0.7, 0.2},
    },
  },
  {
    id = "lab",
    name = "Laboratório",
    desc = "Criada em tubo de ensaio. Analítica.",
    color = {0.7, 0.85, 1.0},
    stats = {hp=90, speed=115, dmg=7, size=13, xpGain=1.10},
    ability = {
      id="analise", name="Análise", desc="Marca inimigos: +50% dano neles por 5s.",
      cd=10, dur=5, color={0.4, 0.8, 1},
    },
  },
  {
    id = "cosmic",
    name = "Espacial",
    desc = "Veio do vácuo. Poder destrutivo.",
    color = {0.6, 0.4, 0.9},
    stats = {hp=85, speed=100, dmg=9, size=15, xpGain=1.00},
    ability = {
      id="meteoro", name="Meteoro", desc="Invoca meteoro no cursor. Dano massivo em área.",
      cd=12, dur=1.0, color={1, 0.4, 0.3},
    },
  },
  {
    id = "symbiote",
    name = "Symbiote",
    desc = "Fusão de dois organismos. Vampírica.",
    color = {0.4, 0.8, 0.5},
    stats = {hp=105, speed=105, dmg=6, size=14, xpGain=1.05},
    ability = {
      id="linkvital", name="Link Vital", desc="30% do dano causado vira cura por 6s.",
      cd=14, dur=6, color={0.3, 1, 0.4},
    },
  },
  {
    id = "ancestral",
    name = "Ancestral",
    desc = "Gene antigo. Inspira medo.",
    color = {0.8, 0.6, 0.3},
    stats = {hp=120, speed=95, dmg=7, size=16, xpGain=0.95},
    ability = {
      id="rugido", name="Rugido", desc="NPCs fogem por 4s e perdem 15% de dano.",
      cd=11, dur=4, color={0.9, 0.7, 0.4},
    },
  },
  {
    id = "fulgor",
    name = "Fulgor",
    desc = "Velocidade é sua arma.",
    color = {1.0, 0.9, 0.4},
    stats = {hp=80, speed=145, dmg=6, size=12, xpGain=1.10},
    ability = {
      id="dashturbo", name="Dash Turbo", desc="Dash sem cooldown por 3s (sem i-frames).",
      cd=10, dur=3, color={1, 1, 0.5},
    },
  },
  {
    id = "falha",
    name = "Falha",
    desc = "Erro genético que virou vantagem.",
    color = {0.9, 0.5, 0.7},
    stats = {hp=95, speed=110, dmg=7, size=14, xpGain=1.15},
    ability = {
      id="adaptacao", name="Adaptação", desc="Copia o dano do inimigo mais forte por 8s.",
      cd=16, dur=8, color={1, 0.5, 0.8},
    },
  },
  {
    id = "matrix",
    name = "Matrix",
    desc = "Código puro. Controla o tempo local.",
    color = {0.3, 1.0, 0.7},
    stats = {hp=90, speed=115, dmg=6, size=13, xpGain=1.05},
    ability = {
      id="overclock", name="Overclock", desc="Inimigos 50% mais lentos por 4s.",
      cd=13, dur=4, color={0.4, 1, 0.8},
    },
  },
  {
    id = "parasita",
    name = "Parasita",
    desc = "Vive do que os outros têm.",
    color = {0.6, 0.3, 0.5},
    stats = {hp=100, speed=105, dmg=6, size=14, xpGain=1.10},
    ability = {
      id="colheita", name="Colheita", desc="Rouba 25% do HP atual do inimigo mais próximo.",
      cd=9, dur=0.2, color={0.8, 0.3, 0.6},
    },
  },
  {
    id = "cristalina",
    name = "Cristalina",
    desc = "Casca mineral. Defesa absurda.",
    color = {0.7, 0.9, 1.0},
    stats = {hp=130, speed=85, dmg=6, size=17, xpGain=0.95},
    ability = {
      id="barreira", name="Barreira", desc="Escudo absorve 100% do dano por 3s.",
      cd=15, dur=3, color={0.7, 0.95, 1},
    },
  },
  {
    id = "eletrica",
    name = "Elétrica",
    desc = "Descarga viva. Cadeia energética.",
    color = {1.0, 0.9, 0.3},
    stats = {hp=88, speed=120, dmg=7, size=13, xpGain=1.05},
    ability = {
      id="cadeia", name="Cadeia", desc="Descarga em cadeia entre até 5 inimigos.",
      cd=11, dur=0.4, color={1, 1, 0.4},
    },
  },
  {
    id = "predatoria",
    name = "Predatória",
    desc = "Feita pra caçar. Troca defesa por dano.",
    color = {0.9, 0.3, 0.3},
    stats = {hp=95, speed=125, dmg=8, size=14, xpGain=1.10},
    ability = {
      id="frenesi", name="Frenesi", desc="+80% dano e -40% defesa por 5s.",
      cd=12, dur=5, color={1, 0.3, 0.3},
    },
  },
}

-- Mapa rápido id -> birth
BIRTH_BY_ID = {}
for i, b in ipairs(BIRTHS) do BIRTH_BY_ID[b.id] = b; b.index = i end

-- ── 1.3 PARTS (8 upgrades, sem duplicatas) ───────────────
-- Cada part tem níveis; custo crescente. Aplicado no player.

PARTS = {
  { id="membrana",   name="Membrana",   desc="+12 HP máx por nível",       maxLv=5, cost=25, stat="hpMax",    perLv=12 },
  { id="flagelo",    name="Flagelo",    desc="+8 velocidade por nível",    maxLv=5, cost=25, stat="speed",   perLv=8  },
  { id="nucleo",     name="Núcleo",     desc="+10% XP por nível",          maxLv=5, cost=30, stat="xpGain",   perLv=0.10 },
  { id="mitocondria",name="Mitocôndria",desc="+0.5 regen HP/s por nível",  maxLv=4, cost=35, stat="hpRegen",  perLv=0.5 },
  { id="vacuolo",    name="Vacúolo",    desc="+25% raio de coleta",        maxLv=4, cost=20, stat="pickRange",perLv=0.25 },
  { id="espinho",    name="Espinho",    desc="+2 dano por nível",          maxLv=5, cost=30, stat="dmg",      perLv=2 },
  { id="cilio",      name="Cílio",      desc="+10% aceleração / controle", maxLv=4, cost=20, stat="accel",    perLv=0.10 },
  { id="tentaculo",  name="Tentáculo",  desc="+8% alcance de ataque",      maxLv=4, cost=25, stat="range",    perLv=0.08 },
}
PART_BY_ID = {}
for _, p in ipairs(PARTS) do PART_BY_ID[p.id] = p end

-- ── 1.4 MUTAÇÕES (5, compradas com DNA raro) ─────────────

MUTATIONS = {
  { id="fotossintese", name="Fotossíntese", desc="+1 HP/s de regeneração passiva.",       cost=2 },
  { id="camuflagem",   name="Camuflagem",   desc="NPCs demoram 2x mais pra te detectar.", cost=2 },
  { id="reflexo",      name="Reflexo",      desc="20% de chance de refletir 50% do dano.",cost=3 },
  { id="metabolismo",  name="Metabolismo",  desc="Comida dá +40% XP.",                     cost=2 },
  { id="regenmorte",   name="Regeneração",  desc="Mata inimigo = cura 5% do HP máx.",     cost=3 },
}
MUT_BY_ID = {}
for _, m in ipairs(MUTATIONS) do MUT_BY_ID[m.id] = m end

-- ── 1.5 TRAITS DE NPC (7) ────────────────────────────────
-- Cada NPC nasce com 1-2 traits. Bosses têm 1 trait fixo.

TRAITS = {
  agressivo  = { name="Agressivo",  desc="Sempre persegue. +15% velocidade.",
                 speedMult=1.15, alwaysChase=true },
  cauteloso  = { name="Cauteloso",  desc="Foge com HP abaixo de 40%.",
                 fleeHp=0.40 },
  gregario   = { name="Gregário",   desc="Se aproxima de outros NPCs.",
                 groupRadius=140 },
  solitario  = { name="Solitário",  desc="Foge quando há muitos NPCs por perto.",
                 avoidRadius=120 },
  tanque     = { name="Tanque",     desc="+50% HP, -30% velocidade.",
                 hpMult=1.5, speedMult=0.7 },
  explosivo  = { name="Explosivo",  desc="Explode ao morrer, causando dano em área.",
                 explodeOnDeath={radius=70, dmg=15} },
  curandeiro = { name="Curandeiro", desc="Cura NPCs aliados por perto.",
                 healAura={radius=90, hps=3} },
}
TRAIT_IDS = {"agressivo","cauteloso","gregario","solitario","tanque","explosivo","curandeiro"}

-- ── 1.6 BOSSES (5 por fase = 10) ─────────────────────────
-- Cada boss tem 3 fases (thresholds em BAL.boss.phaseThresholds).
-- pattern = qual IA especial ele usa (resolvido na Parte 10).

BOSSES = {
  cell = {
    {
      id="protozoo", name="Protozoo Alfa", trait="agressivo",
      hp=220, dmg=8, speed=65, size=30, xp=120,
      color={0.9,0.5,0.5}, pattern="spike",
      desc="Dispara espinhos em cone.",
    },
    {
      id="ameba", name="Ameba Voraz", trait="tanque",
      hp=260, dmg=7, speed=55, size=34, xp=140,
      color={0.5,0.9,0.6}, pattern="split",
      desc="Se divide ao chegar em 50% HP.",
    },
    {
      id="ciliado", name="Ciliado Titan", trait="cauteloso",
      hp=240, dmg=9, speed=70, size=32, xp=140,
      color={0.5,0.7,1.0}, pattern="pull",
      desc="Te puxa com cílios e te ataca de perto.",
    },
    {
      id="colonia", name="Colônia Bacteriana", trait="gregario",
      hp=200, dmg=6, speed=60, size=38, xp=160,
      color={0.9,0.8,0.4}, pattern="multiply",
      desc="Se multiplica em 4 clones ao longo da luta.",
    },
    {
      id="predador_ancestral", name="Predador Ancestral", trait="agressivo", final=true,
      hp=420, dmg=13, speed=85, size=44, xp=400,
      color={0.7,0.2,0.3}, pattern="charge_summon",
      desc="Carrega em linha reta e invoca filhotes.",
    },
  },
  aquatic = {
    {
      id="kraken", name="Kraken", trait="agressivo",
      hp=520, dmg=14, speed=70, size=46, xp=300,
      color={0.4,0.3,0.6}, pattern="tentacles",
      desc="Tentáculos em 8 direções.",
    },
    {
      id="mob_dick", name="Mob Dick", trait="cauteloso",
      hp=560, dmg=12, speed=60, size=48, xp=320,
      color={0.95,0.95,0.95}, pattern="song_pull",
      desc="Canto que te atrai + investida.",
    },
    {
      id="megalodonte", name="Megalodonte", trait="tanque",
      hp=640, dmg=16, speed=78, size=52, xp=340,
      color={0.35,0.45,0.55}, pattern="burst_dash",
      desc="Rajada de 3 dashes em sequência.",
    },
    {
      id="serpente", name="Serpente Abissal", trait="solitario",
      hp=500, dmg=13, speed=88, size=30, xp=360,
      color={0.2,0.6,0.4}, pattern="segments",
      desc="Corpo em segmentos, ataque em espiral.",
    },
    {
      id="leviata", name="Leviatã Primordial", trait="agressivo", final=true,
      hp=900, dmg=20, speed=82, size=58, xp=800,
      color={0.15,0.25,0.5}, pattern="all",
      desc="Combina todos os ataques dos bosses anteriores.",
    },
  },
}

-- Índice rápido
BOSS_BY_ID = {}
for _, list in pairs(BOSSES) do
  for _, b in ipairs(list) do BOSS_BY_ID[b.id] = b end
end

-- ── 1.7 EVENTOS ALEATÓRIOS (10 = 5 antigos + 5 novos) ────
-- Item 9 — mais variedade.

EVENTS = {
  -- antigos (referência, ajuste os valores se quiser)
  { id="cardume",    name="Cardume",        dur=10, desc="Muitos NPCs passivos aparecem." },
  { id="corrente",   name="Corrente Forte", dur=8,  desc="Empurra tudo numa direção." },
  { id="escassez",   name="Escassez",       dur=12, desc="Comida escassa, inimigos mais fortes." },
  { id="abundancia", name="Abundância",     dur=12, desc="Comida dobrada." },
  { id="nevoa",      name="Névoa",          dur=10, desc="Visão reduzida." },
  -- novos
  { id="eclipse",    name="Eclipse",        dur=20, desc="Tela escurece, NPCs +30% agressivos." },
  { id="migracao",   name="Migração",       dur=8,  desc="~30 NPCs passivos atravessam a tela." },
  { id="tempestade", name="Tempestade",     dur=12, desc="Raios caem em posições aleatórias." },
  { id="chuvadna",   name="Chuva de DNA",   dur=15, desc="Todos os drops valem 3x." },
  { id="ninho",      name="Ninho",          dur=0,  desc="NPC gigante invulnerável spawna filhotes até morrer." },
}
EVENT_BY_ID = {}
for _, e in ipairs(EVENTS) do EVENT_BY_ID[e.id] = e end

-- ── 1.8 FONTES DE XP (item 10) ───────────────────────────

XP_SOURCES = {
  comida         = 3,
  comida_rara    = 15,   -- esporo dourado
  npc            = 12,
  npc_elite      = 40,
  boss           = 0,    -- cada boss define seu xp próprio
  bau_aberto     = 5,
  combo_10em5s   = 50,   -- bônus por 10 kills em 5s
  missao         = 100,
  bioma_primeiro = 200,
}

-- ── 1.9 CUTSCENE FINAL (Célula → Terrestre) ──────────────
-- Item 3 (B): animação da célula saindo da água → terra com texto.

CUTSCENE_TERRESTRE = {
  dur_total   = 6.0,
  textos = {
    {t=0.5, txt="A célula deixa o oceano..."},
    {t=2.5, txt="A vida encontra a terra."},
    {t=4.5, txt="Em breve: Fase Terrestre"},
  },
  cor_agua  = {0.10, 0.25, 0.45},
  cor_terra = {0.35, 0.45, 0.25},
}

-- ── 2.1 CONQUISTAS ───────────────────────────────────────
-- Sistema simples: cada conquista tem condição checada no update.
-- Desbloqueio dá XP bônus e aparece um toast.

ACHIEVEMENTS = {
  { id="primeiro_kill",   name="Primeira Morte",     desc="Mate seu primeiro NPC.",              reward=30  },
  { id="primeiro_boss",   name="Caçador de Bosses",  desc="Derrote seu primeiro boss.",          reward=80  },
  { id="streak_10",       name="Em Chamas",          desc="Alcance 10 kills em 5s.",             reward=100 },
  { id="streak_20",       name="Máquina de Matar",   desc="Alcance 20 kills em 5s.",             reward=250 },
  { id="nivel_10",        name="Evoluindo",          desc="Chegue ao nível 10.",                 reward=150 },
  { id="nivel_25",        name="Superorganismo",     desc="Chegue ao nível 25.",                 reward=400 },
  { id="fase_aquatica",   name="Descida às Profundezas", desc="Entrou na fase aquática.",         reward=200 },
  { id="matar_predador",  name="Predador Predado",   desc="Derrote o Predador.",                 reward=350 },
  { id="todos_bosses_cel",name="Senhor da Célula",   desc="Derrote os 5 bosses da fase célula.", reward=300 },
  { id="todos_bosses_aq", name="Senhor do Oceano",   desc="Derrote os 5 bosses da fase aquática.",reward=600 },
  { id="dna_max",         name="Cofre Genético",     desc="Tenha 10 DNA raro ao mesmo tempo.",   reward=200 },
  { id="bestiario_10",    name="Biologista",         desc="Registre 10 criaturas no bestiário.", reward=250 },
  { id="bestiario_all",   name="Enciclopédia Viva",  desc="Registre todas as criaturas.",        reward=1000 },
  { id="sem_dano_boss",   name="Intocável",          desc="Derrote um boss sem levar dano.",     reward=400 },
  { id="vitoria",         name="Além do Oceano",     desc="Chegue à cutscene final.",            reward=1000 },
}
ACH_BY_ID = {}
for _, a in ipairs(ACHIEVEMENTS) do ACH_BY_ID[a.id] = a end

-- ── 2.2 BESTIÁRIO ────────────────────────────────────────
-- Lista de todas as criaturas (NPCs + bosses). Registra ao encontrar.

BESTIARY = {
  -- NPCs comuns
  { id="npc_comum",   name="Protozoário",       tipo="npc",   desc="Célula comum. Inofensiva sozinha." },
  { id="npc_agress",  name="Ciliado Caçador",   tipo="npc",   desc="Ciliado agressivo. Persegue sem parar." },
  { id="npc_tanque",  name="Ameba Blindada",    tipo="npc",   desc="Ameba com membrana grossa. Lenta, mas dura." },
  { id="npc_explo",   name="Vesícula Instável", tipo="npc",   desc="Explode ao morrer. Cuidado." },
  -- bosses célula
  { id="protozoo",           name="Protozoo Alfa",       tipo="boss", desc="Dispara espinhos em cone." },
  { id="ameba",              name="Ameba Voraz",         tipo="boss", desc="Se divide ao chegar em 50% HP." },
  { id="ciliado",            name="Ciliado Titan",       tipo="boss", desc="Te puxa com cílios e ataca de perto." },
  { id="colonia",            name="Colônia Bacteriana",  tipo="boss", desc="Se multiplica em 4 clones." },
  { id="predador_ancestral", name="Predador Ancestral",  tipo="boss", desc="Boss final da célula." },
  -- bosses aquáticos
  { id="kraken",       name="Kraken",            tipo="boss", desc="Tentáculos em 8 direções." },
  { id="mob_dick",     name="Mob Dick",          tipo="boss", desc="Canto que te atrai." },
  { id="megalodonte",  name="Megalodonte",       tipo="boss", desc="Rajada de dashes." },
  { id="serpente",     name="Serpente Abissal",  tipo="boss", desc="Corpo segmentado, espiral." },
  { id="leviata",      name="Leviatã Primordial",tipo="boss", desc="Combina todos os ataques." },
  -- especial
  { id="predador",     name="Predador",          tipo="especial", desc="Aparece a cada 8 min. Slash teleguiado." },
}
BEST_BY_ID = {}
for _, b in ipairs(BESTIARY) do BEST_BY_ID[b.id] = b end

-- ── 2.3 STATS DE CARREIRA (lifetime) ─────────────────────

STATS_DEFAULT = {
  kills        = 0,
  bossesKilled = 0,
  deaths       = 0,
  xpTotal      = 0,
  dnaTotal     = 0,
  runsTotal    = 0,
  bestLevel    = 1,
  bestStreak   = 0,
  tempoTotal   = 0,     -- em segundos
  distancia    = 0,     -- em pixels (aprox)
}

-- ── 2.4 SAVE ─────────────────────────────────────────────

SAVE_FILE = "v5_save.dat"

-- save carregado é uma tabela global SAVE
function saveInit()
  SAVE = {
    achievements = {},   -- [id] = true
    bestiary     = {},   -- [id] = true
    stats        = {},
    unlocks      = {},   -- [birthId] = true (nascimentos desbloqueados)
    mutacoes     = {},   -- [id] = true
    options      = { som=true, musica=true },
    versao       = 5,
  }
  for k, v in pairs(STATS_DEFAULT) do SAVE.stats[k] = v end
  -- desbloqueia o natural por padrão
  SAVE.unlocks["natural"] = true
end

function saveLoad()
  saveInit()
  local info = love.filesystem.getInfo(SAVE_FILE)
  if not info then return false end
  local raw = love.filesystem.read(SAVE_FILE)
  local fn = loadstring or load
  local ok, data = pcall(fn, "return " .. raw)
  if not ok or type(data) ~= "table" then return false end
  -- merge suave (garante campos novos)
  for k, v in pairs(data) do
    if type(v) == "table" and type(SAVE[k]) == "table" then
      for k2, v2 in pairs(v) do SAVE[k][k2] = v2 end
    else
      SAVE[k] = v
    end
  end
  for k, v in pairs(STATS_DEFAULT) do
    if SAVE.stats[k] == nil then SAVE.stats[k] = v end
  end
  return true
end

-- ── SALVA O ESTADO DA RUN ATUAL ─────────────────────────
function salvarRunAtual()
  if not player or not player.alive then return end
  if not FASES or not FASES.atual then return end

  SAVE.runAtiva = {
    birthId         = player.birth.id,
    level           = player.level,
    xp              = player.xp,
    xpNext          = player.xpNext,
    hp              = player.hp,
    dnaRaro         = player.dnaRaro or 0,
    parts           = player.parts or {},
    mutacoes        = player.mutacoes or {},
    x               = player.x,
    y               = player.y,
    avisouAgressao  = player._avisouAgressao or false,

    fasedKey        = FASES.atual.key,
    tempoDecorrido  = FASES.atual.tempoDecorrido or 0,
    bossIdx         = FASES.atual.bossIdx or 1,
    FASESatualIdx   = FASES.atualIdx or 1,

    missoes         = MISSOES_ATIVAS or {},
  }
end

function saveWrite()
 salvarRunAtual()
 -- ── CARREGA A RUN SALVA ─────────────────────────────────
function carregarRunSalva()
  local r = SAVE.runAtiva
  if not r or not r.birthId then return false end
  if not BIRTH_BY_ID[r.birthId] then
    SAVE.runAtiva = nil
    return false
  end

  -- reconstrói o player
  player = Cell.new(0, 0, r.birthId, true)
  player.level   = r.level or 1
  player.xp      = r.xp or 0
  player.xpNext  = r.xpNext or BAL.player.xpToLevel
  player.dnaRaro = r.dnaRaro or 0
  player.parts   = r.parts or {}
  player.mutacoes = r.mutacoes or {}
  player._avisouAgressao = r.avisouAgressao or false
  player:recalcularStats()
  player.hp = r.hp or player.hpMax
  if player.hp > player.hpMax then player.hp = player.hpMax end
  if player.hp <= 0 then player.hp = player.hpMax * 0.5 end

  -- reconstroi a fase (limpa NPCs, comida, etc.)
  FASES.atualIdx = r.FASESatualIdx or 1
  setupFase(r.fasedKey or "cell")
  FASES.atual.tempoDecorrido = r.tempoDecorrido or 0
  FASES.atual.bossIdx        = r.bossIdx or 1

  -- restaura posição
  player.x = r.x or FASES.atual.w / 2
  player.y = r.y or FASES.atual.h / 2
  player.vx, player.vy = 0, 0
  CAM.x = clamp(player.x - VW/2, 0, FASES.atual.w - VW)
  CAM.y = clamp(player.y - VH/2, 0, FASES.atual.h - VH)

  -- estados
  gameState = "jogando"
  dashCd = 0
  autoAtaque = true
  MENU_EVO.ativo = false
  MENU_EVO.pagina = 1
  autosaveTimer = 0

  -- missões
  if r.missoes and #r.missoes > 0 then
    MISSOES_ATIVAS = r.missoes
  else
    inicializarMissoes()
  end

  table.insert(TOASTS, {
    txt = "Jogo retomado!", t=0, dur=2.5, color={0.6, 1, 0.8},
  })

  return true
end
 
 
  local function serialize(t, indent)
    indent = indent or ""
    local s = "{\n"
    for k, v in pairs(t) do
      local key
      if type(k) == "string" then key = string.format("[%q]", k)
      else key = "[" .. tostring(k) .. "]" end
      if type(v) == "table" then
        s = s .. indent .. "  " .. key .. "=" .. serialize(v, indent .. "  ") .. ",\n"
      elseif type(v) == "string" then
        s = s .. indent .. "  " .. key .. "=" .. string.format("%q", v) .. ",\n"
      else
        s = s .. indent .. "  " .. key .. "=" .. tostring(v) .. ",\n"
      end
    end
    return s .. indent .. "}"
  end
  love.filesystem.write(SAVE_FILE, "return " .. serialize(SAVE))
end

-- autosave a cada N segundos + ao morrer
AUTOSAVE_INTERVAL = 30
autosaveTimer = 0

-- ── 2.5 HELPERS DE PROGRESSO ─────────────────────────────

function unlockAchievement(id)
  if SAVE.achievements[id] then return end
  SAVE.achievements[id] = true
  local a = ACH_BY_ID[id]
  if a and player then
    player:addXP(a.reward)
  end
  -- toast
  table.insert(TOASTS, {
    txt = "🏆 " .. (a and a.name or id),
    t = 0, dur = 3.0,
    color = {1, 0.85, 0.3},
  })
  saveWrite()
end

function registerBestiary(id)
  if SAVE.bestiary[id] then return end
  SAVE.bestiary[id] = true
  local b = BEST_BY_ID[id]
  table.insert(TOASTS, {
    txt = "📖 " .. (b and b.name or id),
    t = 0, dur = 3.0,
    color = {0.7, 0.9, 1},
  })
  -- checa conquistas de bestiário
  local count = 0
  for _ in pairs(SAVE.bestiary) do count = count + 1 end
  if count >= 10 then unlockAchievement("bestiario_10") end
  if count >= #BESTIARY then unlockAchievement("bestiario_all") end
  saveWrite()
end

function registerKill()
  SAVE.stats.kills = SAVE.stats.kills + 1
  if SAVE.stats.kills == 1 then unlockAchievement("primeiro_kill") end
end

function registerBossKill(bossId)
  SAVE.stats.bossesKilled = SAVE.stats.bossesKilled + 1
  registerBestiary(bossId)
  unlockAchievement("primeiro_boss")
  -- checa se matou todos de uma fase
  if FASES and FASES.cell and FASES.cell.bossesDerrotados then
    if #FASES.cell.bossesDerrotados >= 5 then unlockAchievement("todos_bosses_cel") end
  end
  if FASES and FASES.aquatic and FASES.aquatic.bossesDerrotados then
    if #FASES.aquatic.bossesDerrotados >= 5 then unlockAchievement("todos_bosses_aq") end
  end
end

function registerDeath()
  SAVE.stats.deaths = SAVE.stats.deaths + 1
  saveWrite()
end

function registerRunStart()
  SAVE.stats.runsTotal = SAVE.stats.runsTotal + 1
end

-- ── 3.1 CLASSE CELL ──────────────────────────────────────
-- A mesma classe é usada pra player e NPCs. Comportamento
-- difere pelas flags e pelos métodos chamados.

Cell = {}
Cell.__index = Cell

function Cell.new(x, y, birthId, isPlayer, traitIds)
  local birth = BIRTH_BY_ID[birthId] or BIRTHS[1]
  local self = setmetatable({}, Cell)
  self.x, self.y   = x, y
  self.vx, self.vy = 0, 0
  self.birth       = birth
  self.isPlayer    = isPlayer or false

  -- stats base do nascimento
  self.hpMax   = birth.stats.hp
  self.hp      = self.hpMax
  self.speed   = birth.stats.speed
  self.dmg     = birth.stats.dmg
  self.size    = birth.stats.size
  self.xpGain  = birth.stats.xpGain or 1.0

  -- progressão
  self.level    = 1
  self.xp       = 0
  self.xpNext   = BAL.player.xpToLevel
  self.dnaRaro  = 0
  self.parts    = {}    -- [partId] = nível
  self.mutacoes = {}    -- [mutId] = true

  -- estado
  self.alive      = true
  self.iframes    = 0
  self.hpRegenBonus = 0
  self.pickRange  = 60
  self.accel      = 1.0
  self.range      = 1.0
  self.speedMul   = 1.0
  self.dmgMul     = 1.0
  self.defMul     = 1.0

  -- habilidade ativa
  self.ability = {
    id      = birth.ability.id,
    name    = birth.ability.name,
    cd      = birth.ability.cd,
    cdMax   = birth.ability.cd,
    dur     = birth.ability.dur,
    ativa   = false,
    tAtiva  = 0,
    color   = birth.ability.color or {1, 1, 1},
  }

  -- kill streak
  self.streak      = 0
  self.streakTimer = 0
  self.buffStreak  = nil   -- {stat=, mult=, t=}

  -- NPC: traits
  self.traits = {}
  if traitIds then
    for _, id in ipairs(traitIds) do
      if TRAITS[id] then
        table.insert(self.traits, { id=id, def=TRAITS[id] })
      end
    end
  end
  self.iaState  = "idle"     -- idle, chase, flee, group
  self.iaTimer  = 0
  self.isElite  = false

  -- boss
  self.isBoss     = false
  self.bossDef    = nil
  self.bossFase   = 1
  self.bossInvuln = 0
  self.bossPatternTimer = 0

  -- dano acumulado pra detecção de "sem dano no boss"
  self.danoRecebidoTotal = 0

  return self
end

-- ── aplica stats do nascimento + parts + mutações (só player) ──
function Cell:recalcularStats()
  if not self.isPlayer then return end
  local b = self.birth.stats
  local hpMax   = b.hp
  local speed   = b.speed
  local dmg     = b.dmg
  local xpGain  = b.xpGain or 1.0
  local hpRegen = BAL.player.hpRegen
  local pickR   = 60
  local accel   = 1.0
  local range   = 1.0

  for id, lv in pairs(self.parts) do
    local p = PART_BY_ID[id]
    if p then
      if     p.stat == "hpMax"    then hpMax   = hpMax   + p.perLv * lv
      elseif p.stat == "speed"    then speed   = speed   + p.perLv * lv
      elseif p.stat == "dmg"      then dmg     = dmg     + p.perLv * lv
      elseif p.stat == "xpGain"   then xpGain  = xpGain  + p.perLv * lv
      elseif p.stat == "hpRegen"  then hpRegen = hpRegen + p.perLv * lv
      elseif p.stat == "pickRange"then pickR   = pickR * (1 + p.perLv * lv)
      elseif p.stat == "accel"    then accel   = accel   + p.perLv * lv
      elseif p.stat == "range"    then range   = range   + p.perLv * lv
      end
    end
  end

  if self.mutacoes["fotossintese"] then hpRegen = hpRegen + 1.0 end
  if self.mutacoes["metabolismo"]  then xpGain  = xpGain  * 1.4 end

  self.hpMax    = hpMax
  self.speed    = speed
  self.dmg      = dmg
  self.xpGain   = xpGain
  self.hpRegenBonus = hpRegen
  self.pickRange = pickR
  self.accel     = accel
  self.range     = range
  if self.hp > self.hpMax then self.hp = self.hpMax end
-- guarda o dano base pra permitir Adaptação sobrescrever sem perder
  self.dmgBase = self.dmg
end

-- ── ganho de XP (só player) ──────────────────────────────
function Cell:addXP(amount)
  if not self.isPlayer then return end
  amount = amount * self.xpGain
  self.xp = self.xp + amount
  SAVE.stats.xpTotal = SAVE.stats.xpTotal + amount
  while self.xp >= self.xpNext do
    self.xp = self.xp - self.xpNext
    self.level = self.level + 1
    self.xpNext = math.floor(BAL.player.xpToLevel * (BAL.player.levelCurve ^ (self.level - 1)))
    -- cura ao subir
    self.hp = math.min(self.hpMax, self.hp + self.hpMax * 0.15)
    -- conquistas de nível
    if self.level >= 10 then unlockAchievement("nivel_10") end
    if self.level >= 25 then unlockAchievement("nivel_25") end
    if self.level > SAVE.stats.bestLevel then SAVE.stats.bestLevel = self.level end
    -- toast
    -- efeitos V6 de nível up
if self.isPlayer then
  NIVEL_UP.flash = 1.0
  NIVEL_UP.texto = { nivel = self.level, t = 0, dur = 1.2 }
  camShake(5, 0.3)
  -- partículas douradas
  burst(self.x, self.y, 30, {1, 0.85, 0.3}, 240, 1.0, 5)
end
    table.insert(TOASTS, {
      txt = "⬆ Nível " .. self.level,
      t = 0, dur = 2.0,
      color = {0.5, 1, 0.6},
    })
  end
end

-- ── tomar dano ──────────────────────────────────────────
function Cell:takeDamage(amount, fromX, fromY)
  if not self.alive then return false end
  if self.iframes > 0 then return false end

  -- escudo barreira
  if self.ability and self.ability.ativa and self.ability.id == "barreira" then
    return false
  end

  -- reflexo (mutação)
  if self.mutacoes["reflexo"] and math.random() < 0.20 then
    -- refletiu 50% — quem bateu que se vire (tratado pelo chamador)
    return "refletiu"
  end

  amount = amount * self.defMul
  self.hp = self.hp - amount
  -- player tem 0.6s; NPC tem só 0.15s (senão o ataque de contato trava)
if self.isPlayer then
  self.iframes = BAL.player.iframes
else
  self.iframes = 0.15
end
  self.danoRecebidoTotal = self.danoRecebidoTotal + amount

  -- knockback
  if fromX and fromY then
    local dx, dy = self.x - fromX, self.y - fromY
    local d = math.sqrt(dx*dx + dy*dy)
    if d > 0 then
      self.vx = self.vx + (dx/d) * 60
      self.vy = self.vy + (dy/d) * 60
    end
  end

  if self.hp <= 0 then
    self.hp = 0
    self.alive = false
  end
  return true
end

-- ── curar ───────────────────────────────────────────────
function Cell:heal(amount)
  self.hp = math.min(self.hpMax, self.hp + amount)
end

-- ── usar habilidade ─────────────────────────────────────
function Cell:usarHabilidade()
  if not self.isPlayer then return end
  local a = self.ability
  if a.cd > 0 then return end
  a.cd    = a.cdMax
  a.ativa = true
  a.tAtiva = a.dur
  -- efeitos iniciais (o resto acontece no update)
  if a.id == "boom" then
    -- explosão imediata
    triggerBoom(self)
  elseif a.id == "meteoro" then
    triggerMeteoro(self)
  elseif a.id == "cadeia" then
    triggerCadeia(self)
  elseif a.id == "colheita" then
    triggerColheita(self)
  end
end

-- ── update básico da célula (movimento e timers) ────────
function Cell:updateTimers(dt)
  if self.iframes > 0 then self.iframes = self.iframes - dt end

  -- REGEN: todas as células recuperam +1 HP/s
  if self.alive and self.hp < self.hpMax then
    self.hp = math.min(self.hpMax, self.hp + 1.0 * dt)
  end
  if self.ability then
    if self.ability.cd > 0 then
      self.ability.cd = math.max(0, self.ability.cd - dt)
    end
    if self.ability.ativa then
      self.ability.tAtiva = self.ability.tAtiva - dt
      if self.ability.tAtiva <= 0 then
        self.ability.ativa = false
      end
    end
  end
  if self.streakTimer > 0 then
    self.streakTimer = self.streakTimer - dt
    if self.streakTimer <= 0 then self.streak = 0 end
  end
  if self.buffStreak then
    self.buffStreak.t = self.buffStreak.t - dt
    if self.buffStreak.t <= 0 then
      self.speedMul = 1.0; self.dmgMul = 1.0
      self.buffStreak = nil
    end
  end
end

-- ── kill streak ─────────────────────────────────────────
function Cell:onKillStreak()
  if not self.isPlayer then return end
  self.streak = self.streak + 1
  self.streakTimer = BAL.killStreak.window
  if self.streak > SAVE.stats.bestStreak then SAVE.stats.bestStreak = self.streak end

  if self.streak == 10 then
    self:addXP(BAL.killStreak.tiers[1].xp)
    unlockAchievement("streak_10")
  elseif self.streak == 20 then
    self:addXP(BAL.killStreak.tiers[2].xp)
    unlockAchievement("streak_20")
  end

  -- aplica buff por tier
  for _, tier in ipairs(BAL.killStreak.tiers) do
    if self.streak >= tier.kills then
      self.buffStreak = { stat=tier.buff, mult=tier.mult, t=tier.dur }
      if tier.buff == "speed" then
        self.speedMul = tier.mult; self.dmgMul = 1.0
      elseif tier.buff == "damage" then
        self.speedMul = 1.0; self.dmgMul = tier.mult
      elseif tier.buff == "god" then
        self.speedMul = 1.2; self.dmgMul = 1.6
      end
    end
  end
end

-- ── 3.2 TOASTS (avisos flutuantes no canto) ──────────────
-- Usados por conquistas, bestiário, level up, etc.

TOASTS = {}

function updateToasts(dt)
  for i = #TOASTS, 1, -1 do
    local t = TOASTS[i]
    t.t = t.t + dt
    if t.t >= t.dur then table.remove(TOASTS, i) end
  end
end

function drawToasts()
  local y = 80
  for _, t in ipairs(TOASTS) do
    local alpha = 1.0
    if t.t > t.dur - 0.5 then alpha = (t.dur - t.t) / 0.5 end
    if t.t < 0.3 then alpha = t.t / 0.3 end
    love.graphics.setColor(t.color[1], t.color[2], t.color[3], alpha)
    love.graphics.print(t.txt, VW - 260, y)
    y = y + 26
  end
  love.graphics.setColor(1, 1, 1)
end

-- ── 3.3 MÚSICA PROCEDURAL ────────────────────────────────
-- Sintetiza tons sem arquivos. Diferentes temas por fase.
-- Requer love.audio ativo (padrão no LÖVE).

Music = {
  ativa     = true,
  temaAtual = "menu",
  bpm       = 100,
  tempo     = 0,
  beat      = 0,
  source    = nil,
  notas     = {},   -- fila de notas a tocar
}

-- escala menor natural (semitons a partir da tônica)
local ESCALA_MENOR = {0, 2, 3, 5, 7, 8, 10}

local TEMAS = {
  menu    = {base=220, bpm=70,  pad={1,3,5},        batida=false},
  celula  = {base=196, bpm=100, pad={0,2,4},        batida=true },
  aquatic = {base=174, bpm=90,  pad={0,3,7},        batida=true },
  boss    = {base=147, bpm=140, pad={0,3,6},        batida=true, rock=true},
  perigo  = {base=233, bpm=160, pad={0,2,3,5},      batida=true, rock=true},
}

-- gera waveform de uma nota por N segundos (com envelope)
function Music:gerarNota(freq, dur, volume, tipo)
  local rate = 44100
  local n = math.floor(rate * dur)
  local samples = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local t = i / rate
    local env = 1.0
    -- ataque curto + decay
    if t < 0.01 then env = t / 0.01
    else env = math.exp(-t * 3.0) end
    local v = 0
    if tipo == "pad" then
      -- senoidal pura com vibrato leve
      v = math.sin(2*math.pi*freq*t) * 0.7
        + math.sin(2*math.pi*freq*2*t) * 0.2
    elseif tipo == "bass" then
      -- onda quadrada suave pra grave
      v = math.sin(2*math.pi*freq*t) * 0.6
        + (math.sin(2*math.pi*freq*t) > 0 and 0.4 or -0.4)
    elseif tipo == "rock" then
      -- mais harmônicos (distorção)
      v = math.sin(2*math.pi*freq*t)
      v = v + 0.4 * math.sin(2*math.pi*freq*2*t)
      v = v + 0.25 * math.sin(2*math.pi*freq*3*t)
      v = math.tanh(v * 2.0) * 0.5
    else
      v = math.sin(2*math.pi*freq*t)
    end
    samples:setSample(i, v * env * volume)
  end
  return samples
end

function Music:setTema(nome)
  if self.temaAtual == nome then return end
  self.temaAtual = nome
  local t = TEMAS[nome] or TEMAS.celula
  self.bpm    = t.bpm
  self.tempo  = 0
  self.beat   = 0
  self.base   = t.base
  self.pad    = t.pad
  self.rock   = t.rock or false
end

-- chamar 1x no love.load
function Music:init()
  self.temaAtual = nil
  self:setTema("menu")
  -- cria cache de notas (gera sob demanda)
  self.cache = {}
end

function Music:getNota(freq, dur, tipo)
  local key = string.format("%.1f_%.2f_%s", freq, dur, tipo)
  if self.cache[key] then return self.cache[key] end
  local s = self:gerarNota(freq, dur, 0.35, tipo)
  self.cache[key] = s
  return s
end

-- toca uma nota específica (cria Source e toca)
function Music:tocar(freq, dur, tipo, vol)
  if not self.ativa or not SAVE.options.musica then return end
  local s = self:getNota(freq, dur, tipo or "pad")
  local src = love.audio.newSource(s, "static")
  src:setVolume((vol or 1.0) * 0.4)
  src:play()
end

-- progressão simples (4 acordes que se repetem)
local PROGRESSAO = {0, 5, 3, 7}

function Music:update(dt)
  if not self.ativa or not SAVE.options.musica then return end
  local t = TEMAS[self.temaAtual] or TEMAS.celula
  self.tempo = self.tempo + dt
  local beatDur = 60.0 / t.bpm

  if self.tempo >= beatDur then
    self.tempo = self.tempo - beatDur
    self.beat = self.beat + 1

    -- a cada 4 beats troca o acorde
    local acorde = PROGRESSAO[(math.floor(self.beat / 4) % #PROGRESSAO) + 1]
    local notaBase = t.base * (2 ^ (acorde / 12))

    -- baixo no beat 1
    if self.beat % 4 == 0 then
      self:tocar(notaBase / 2, beatDur * 2, "bass", 0.9)
    end

    -- pad
    if self.beat % 2 == 0 then
      for _, grau in ipairs(t.pad) do
        local freq = notaBase * (2 ^ (ESCALA_MENOR[grau + 1] / 12))
        self:tocar(freq, beatDur * 1.5, "pad", 0.5)
      end
    end

    -- rock (boss) — kick + riff
    if t.rock then
      if self.beat % 2 == 1 then
        -- kick grave
        self:tocar(60, 0.15, "bass", 1.0)
      end
      if self.beat % 4 == 2 or self.beat % 4 == 3 then
        local freq = notaBase * 2 * (2 ^ (ESCALA_MENOR[3] / 12))
        self:tocar(freq, beatDur * 0.5, "rock", 0.6)
      end
    end
  end
end

-- ── MENU BACKGROUND ANIMADO (bolhas) ────────────────────
MENU_BG = { bolhas = {}, t = 0 }

function menuBgInit()
  MENU_BG.bolhas = {}
  for i = 1, 30 do
    MENU_BG.bolhas[i] = {
      x = love.math.random() * VW,
      y = love.math.random() * VH,
      r = 12 + love.math.random() * 55,
      vx = (love.math.random() - 0.5) * 22,
      vy = (love.math.random() - 0.5) * 22,
      alpha = 0.05 + love.math.random() * 0.15,
      cor = love.math.random() < 0.5 and {0.4,0.6,0.95} or {0.5,0.85,0.75},
    }
  end
end

function menuBgUpdate(dt)
  MENU_BG.t = MENU_BG.t + dt
  for _, b in ipairs(MENU_BG.bolhas) do
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    if b.x < -b.r then b.x = VW + b.r end
    if b.x > VW + b.r then b.x = -b.r end
    if b.y < -b.r then b.y = VH + b.r end
    if b.y > VH + b.r then b.y = -b.r end
  end
end

function menuBgDraw()
  -- gradiente azul escuro
  for i = 0, 30 do
    local t = i / 30
    love.graphics.setColor(0.04 + t*0.05, 0.06 + t*0.07, 0.14 + t*0.10)
    love.graphics.rectangle("fill", 0, i * VH/30, VW, VH/30 + 1)
  end
  -- bolhas
  for _, b in ipairs(MENU_BG.bolhas) do
    love.graphics.setColor(b.cor[1], b.cor[2], b.cor[3], b.alpha)
    love.graphics.circle("fill", b.x, b.y, b.r)
    love.graphics.setColor(b.cor[1], b.cor[2], b.cor[3], b.alpha * 1.6)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", b.x, b.y, b.r)
  end
  love.graphics.setColor(1, 1, 1)
end

-- ── DETECÇÃO DE ROTAÇÃO ─────────────────────────────────
function isPortrait()
  return love.graphics.getWidth() < love.graphics.getHeight()
end

function desenharRotacaoNecessaria()
  local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
  love.graphics.setColor(0.05, 0.08, 0.15)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  love.graphics.setColor(1, 1, 1)
  setFonte("grande")
  love.graphics.printf("Gire o celular", 0, wh/2 - 60, ww, "center")
  setFonte("normal")
  love.graphics.setColor(0.75, 0.85, 0.95)
  love.graphics.printf("Este jogo funciona na horizontal", 0, wh/2 + 10, ww, "center")
  love.graphics.setColor(1, 1, 1)
end

-- ── 4.1 ESTADO GLOBAL DA APLICAÇÃO ──────────────────────
gameState = "menu"  -- "menu" | "jogando" | "pausa" | "cutscene" | "gameover" | "vitoria"

MENU = {
  tela          = "principal",  -- principal | nascimentos | conquistas | bestiario | stats | opcoes
  birthSel      = "natural",
  pagina        = 1,
  hover         = nil,
}
ITENS_POR_PAGINA = 5

-- ── 4.2 FONTES ───────────────────────────────────────────

FONTES = {
  pequena = love.graphics.newFont(12),
  normal  = love.graphics.newFont(16),
  media   = love.graphics.newFont(20),
  grande  = love.graphics.newFont(32),
  titulo  = love.graphics.newFont(48),
}

function setFonte(nome)
  love.graphics.setFont(FONTES[nome] or FONTES.normal)
end

-- ── 4.3 HELPERS DE UI ────────────────────────────────────

function pontoEmRetangulo(px, py, x, y, w, h)
  return px >= x and px <= x+w and py >= y and py <= y+h
end

function desenharBotao(x, y, w, h, texto, hover, cor)
  cor = cor or {0.22, 0.32, 0.42}
  if hover then
    love.graphics.setColor(
      math.min(cor[1]+0.18, 1),
      math.min(cor[2]+0.18, 1),
      math.min(cor[3]+0.18, 1))
  else
    love.graphics.setColor(cor[1], cor[2], cor[3])
  end
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)
  love.graphics.setColor(1, 1, 1)
  setFonte("normal")
  love.graphics.printf(texto, x, y + h/2 - 9, w, "center")
end

function desenharFundoMenu()
  for i = 0, 20 do
    local t = i / 20
    love.graphics.setColor(0.05 + t*0.05, 0.10 + t*0.05, 0.18 + t*0.08)
    love.graphics.rectangle("fill", 0, i * VH/20, VW, VH/20 + 1)
  end
  love.graphics.setColor(1, 1, 1)
end

function desenharTituloMenu(txt, sub)
  setFonte("titulo")
  love.graphics.setColor(0.6, 0.9, 1.0)
  love.graphics.printf(txt, 0, 30, VW, "center")
  if sub then
    setFonte("normal")
    love.graphics.setColor(0.7, 0.8, 0.9)
    love.graphics.printf(sub, 0, 88, VW, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

-- ── 4.4 TELA: PRINCIPAL ──────────────────────────────────

function botoesPrincipal()
  local w, h = 340, 52
  local x = VW/2 - w/2
  local y0 = 200
  local gap = 14
  local btns = {}

  if SAVE.runAtiva then
    -- tem save: CONTINUAR no topo
    btns[#btns+1] = { id="continuar", x=x, y=y0, w=w, h=h,
      txt="CONTINUAR", cor={0.20, 0.55, 0.30} }
    btns[#btns+1] = { id="jogar", x=x, y=y0 + (h+gap), w=w, h=h,
      txt="NOVO JOGO", cor={0.25, 0.40, 0.60} }
    btns[#btns+1] = { id="nascimentos", x=x, y=y0 + (h+gap)*2, w=w, h=h,
      txt="ESCOLHER NASCIMENTO", cor={0.25, 0.40, 0.60} }
  else
    btns[#btns+1] = { id="jogar", x=x, y=y0, w=w, h=h,
      txt="JOGAR", cor={0.20, 0.55, 0.30} }
    btns[#btns+1] = { id="nascimentos", x=x, y=y0 + (h+gap), w=w, h=h,
      txt="ESCOLHER NASCIMENTO", cor={0.25, 0.40, 0.60} }
  end

  return btns
end

function botoesMini()
  local w, h = 130, 38
  local gap = 12
  local totalW = w*4 + gap*3
  local x0 = VW/2 - totalW/2
  local y = VH - 90
  return {
    { id="conquistas", x=x0 + (w+gap)*0, y=y, w=w, h=h, txt="CONQ." },
    { id="bestiario",  x=x0 + (w+gap)*1, y=y, w=w, h=h, txt="BEST." },
    { id="stats",      x=x0 + (w+gap)*2, y=y, w=w, h=h, txt="STATS" },
    { id="opcoes",     x=x0 + (w+gap)*3, y=y, w=w, h=h, txt="OPC." },
  }
end

function desenharMenuPrincipal()
  menuBgDraw()

  local t = love.timer.getTime()
  local dy = math.sin(t*2) * 3

  -- título
  setFonte("titulo")
  love.graphics.setColor(0.5, 0.9, 1.0)
  love.graphics.printf("EVOLUTION CELL", 0, 60 + dy, VW - 60, "center")

  -- "V5" ao lado direito do título
  setFonte("media")
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.print("V5", VW/2 + 240, 82 + dy)

  -- subtítulo
  setFonte("normal")
  love.graphics.setColor(0.75, 0.85, 0.95)
  love.graphics.printf("A vida nao pede permissao para existir.",
    0, 145, VW, "center")

  -- botões principais
  for _, b in ipairs(botoesPrincipal()) do
    desenharBotao(b.x, b.y, b.w, b.h, b.txt, MENU.hover == b.id, b.cor)
  end

  -- botões mini
  for _, b in ipairs(botoesMini()) do
    desenharBotao(b.x, b.y, b.w, b.h, b.txt, MENU.hover == b.id)
  end

  -- rodapé
  setFonte("pequena")
  love.graphics.setColor(0.5, 0.6, 0.7)
  love.graphics.printf("v5.0 - LOVE", VW - 160, VH - 24, 150, "right")
  love.graphics.setColor(1, 1, 1)
end

function clickMenuPrincipal(mx, my)
  for _, b in ipairs(botoesPrincipal()) do
    if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then
      if b.id == "continuar" then
        if carregarRunSalva() then
          return true
        end
      elseif b.id == "jogar" then
        SAVE.runAtiva = nil   -- novo jogo apaga o save antigo
        local birthId = BIRTHS[love.math.random(#BIRTHS)].id
        table.insert(TOASTS, {
          txt = "Nascimento: " .. BIRTH_BY_ID[birthId].name,
          t = 0, dur = 3, color = {0.9, 0.8, 1},
        })
        startGame(birthId)
      else
        MENU.tela = b.id
        MENU.pagina = 1
      end
      return true
    end
  end
  for _, b in ipairs(botoesMini()) do
    if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then
      MENU.tela = b.id
      MENU.pagina = 1
      return true
    end
  end
  return false
end

-- ── 4.5 TELA: NASCIMENTOS (grid 3x4) ─────────────────────

function celulasNascimentos()
  local cols, rows = 3, 4
  local cw, ch = 280, 70
  local gapx, gapy = 20, 12
  local totalW = cols*cw + (cols-1)*gapx
  local x0 = (VW - totalW)/2
  local y0 = 130
  local celulas = {}
  for i, b in ipairs(BIRTHS) do
    local col = (i-1) % cols
    local row = math.floor((i-1) / cols)
    celulas[#celulas+1] = {
      id = b.id, birth = b,
      x = x0 + col*(cw+gapx),
      y = y0 + row*(ch+gapy),
      w = cw, h = ch,
    }
  end
  return celulas
end

function desenharMenuNascimentos()
  desenharFundoMenu()
  desenharTituloMenu("NASCIMENTOS", "Escolha sua origem genetica")

  for _, c in ipairs(celulasNascimentos()) do
    local sel   = MENU.birthSel == c.id
    local hover = MENU.hover == c.id
    local b = c.birth
    if sel then
      love.graphics.setColor(b.color[1]*0.4, b.color[2]*0.4, b.color[3]*0.4)
    elseif hover then
      love.graphics.setColor(0.20, 0.28, 0.36)
    else
      love.graphics.setColor(0.14, 0.18, 0.24)
    end
    love.graphics.rectangle("fill", c.x, c.y, c.w, c.h, 6, 6)
    if sel then
      love.graphics.setColor(b.color[1], b.color[2], b.color[3])
    else
      love.graphics.setColor(1, 1, 1, 0.15)
    end
    love.graphics.rectangle("line", c.x, c.y, c.w, c.h, 6, 6)

    love.graphics.setColor(b.color[1], b.color[2], b.color[3])
    love.graphics.circle("fill", c.x + 26, c.y + c.h/2, 13)

    love.graphics.setColor(1, 1, 1)
    setFonte("normal")
    love.graphics.print(b.name, c.x + 50, c.y + 12)
    setFonte("pequena")
    love.graphics.setColor(
      b.color[1]*0.9 + 0.1,
      b.color[2]*0.9 + 0.1,
      b.color[3]*0.9 + 0.1)
    love.graphics.print(b.ability.name .. "  -  cd " .. b.ability.cd .. "s",
      c.x + 50, c.y + 38)
  end

  love.graphics.setColor(1, 1, 1)
  setFonte("normal")
  local bw, bh = 160, 44
  desenharBotao(VW/2 - bw - 12, VH - 70, bw, bh, "VOLTAR",
    MENU.hover == "voltar")
  desenharBotao(VW/2 + 12,      VH - 70, bw, bh, "INICIAR",
    MENU.hover == "iniciar", {0.20, 0.45, 0.30})
end

function clickMenuNascimentos(mx, my)
  for _, c in ipairs(celulasNascimentos()) do
    if pontoEmRetangulo(mx, my, c.x, c.y, c.w, c.h) then
      MENU.birthSel = c.id
      return true
    end
  end
  local bw, bh = 160, 44
  if pontoEmRetangulo(mx, my, VW/2 - bw - 12, VH - 70, bw, bh) then
    MENU.tela = "principal"
    return true
  end
  if pontoEmRetangulo(mx, my, VW/2 + 12, VH - 70, bw, bh) then
    -- startGame é implementado na Parte 7
    if startGame then startGame(MENU.birthSel) end
    return true
  end
  return false
end

-- ── 5.1 HELPERS DE PAGINAÇÃO ─────────────────────────────

function linhasLista()
  -- 5 linhas por página
  local x = 60
  local w = VW - 120
  local h = 58
  local gap = 8
  local y0 = 130
  local linhas = {}
  for i = 1, ITENS_POR_PAGINA do
    linhas[#linhas+1] = {
      x = x, y = y0 + (i-1)*(h+gap),
      w = w, h = h,
    }
  end
  return linhas
end

function totalPaginas(totalItens)
  return math.max(1, math.ceil(totalItens / ITENS_POR_PAGINA))
end

function desenharPaginacao(pagina, total, prefix)
  local bw, bh = 110, 36
  local y = VH - 58
  local cx = VW/2
  desenharBotao(cx - bw*1.5 - 60, y, bw, bh, "<< ANT", MENU.hover == prefix.."prev")
  setFonte("normal")
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(pagina .. " / " .. total, cx - 60, y + 9, 120, "center")
  desenharBotao(cx + bw*0.5 + 60, y, bw, bh, "PROX >>", MENU.hover == prefix.."next")
  desenharBotao(VW - 140, y, 100, bh, "VOLTAR", MENU.hover == prefix.."voltar")
end

-- ── 5.2 TELA: CONQUISTAS ─────────────────────────────────

function desenharMenuConquistas()
  desenharFundoMenu()
  desenharTituloMenu("CONQUISTAS", tostring(#ACHIEVEMENTS) .. " no total")

  local total = totalPaginas(#ACHIEVEMENTS)
  MENU.pagina = math.max(1, math.min(MENU.pagina, total))
  local start = (MENU.pagina - 1) * ITENS_POR_PAGINA

  for i, linha in ipairs(linhasLista()) do
    local idx = start + i
    local a = ACHIEVEMENTS[idx]
    if a then
      local ok = SAVE.achievements[a.id]
      if ok then
        love.graphics.setColor(0.18, 0.30, 0.22)
      else
        love.graphics.setColor(0.14, 0.16, 0.20)
      end
      love.graphics.rectangle("fill", linha.x, linha.y, linha.w, linha.h, 6, 6)
      love.graphics.setColor(1, 1, 1, 0.10)
      love.graphics.rectangle("line", linha.x, linha.y, linha.w, linha.h, 6, 6)

      setFonte("media")
      if ok then
        love.graphics.setColor(0.4, 1, 0.5)
        love.graphics.print("OK", linha.x + 20, linha.y + 16)
      else
        love.graphics.setColor(0.4, 0.4, 0.5)
        love.graphics.print("--", linha.x + 20, linha.y + 16)
      end

      setFonte("normal")
      love.graphics.setColor(1, 1, 1)
      love.graphics.print(a.name, linha.x + 86, linha.y + 8)
      setFonte("pequena")
      love.graphics.setColor(0.75, 0.8, 0.85)
      love.graphics.print(a.desc, linha.x + 86, linha.y + 30)
      love.graphics.setColor(0.9, 0.85, 0.5)
      love.graphics.printf("+" .. a.reward .. " XP", linha.x, linha.y + 18, linha.w - 20, "right")
    end
  end

  love.graphics.setColor(1, 1, 1)
  desenharPaginacao(MENU.pagina, total, "c_")
end

function clickMenuConquistas(mx, my)
  local total = totalPaginas(#ACHIEVEMENTS)
  local bw, bh = 110, 36
  local y = VH - 58
  local cx = VW/2
  if pontoEmRetangulo(mx, my, cx - bw*1.5 - 60, y, bw, bh) then
    MENU.pagina = math.max(1, MENU.pagina - 1); return true
  end
  if pontoEmRetangulo(mx, my, cx + bw*0.5 + 60, y, bw, bh) then
    MENU.pagina = math.min(total, MENU.pagina + 1); return true
  end
  if pontoEmRetangulo(mx, my, VW - 140, y, 100, bh) then
    MENU.tela = "principal"; return true
  end
  return false
end

-- ── 5.3 TELA: BESTIARIO ──────────────────────────────────

function desenharMenuBestiario()
  desenharFundoMenu()
  desenharTituloMenu("BESTIARIO", tostring(#BESTIARY) .. " criaturas")

  local total = totalPaginas(#BESTIARY)
  MENU.pagina = math.max(1, math.min(MENU.pagina, total))
  local start = (MENU.pagina - 1) * ITENS_POR_PAGINA

  for i, linha in ipairs(linhasLista()) do
    local idx = start + i
    local b = BESTIARY[idx]
    if b then
      local ok = SAVE.bestiary[b.id]
      if ok then
        love.graphics.setColor(0.18, 0.24, 0.32)
      else
        love.graphics.setColor(0.12, 0.14, 0.18)
      end
      love.graphics.rectangle("fill", linha.x, linha.y, linha.w, linha.h, 6, 6)
      love.graphics.setColor(1, 1, 1, 0.10)
      love.graphics.rectangle("line", linha.x, linha.y, linha.w, linha.h, 6, 6)

      local tagCor = {0.6, 0.6, 0.6}
      if     b.tipo == "boss"     then tagCor = {0.9, 0.5, 0.5}
      elseif b.tipo == "especial" then tagCor = {0.9, 0.7, 0.3}
      elseif b.tipo == "npc"      then tagCor = {0.5, 0.8, 0.6}
      end
      love.graphics.setColor(tagCor)
      setFonte("pequena")
      love.graphics.printf(string.upper(b.tipo), linha.x + 8, linha.y + 20, 74, "center")

      if ok then
        setFonte("normal")
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(b.name, linha.x + 92, linha.y + 8)
        setFonte("pequena")
        love.graphics.setColor(0.75, 0.8, 0.85)
        love.graphics.print(b.desc, linha.x + 92, linha.y + 30)
      else
        setFonte("normal")
        love.graphics.setColor(0.4, 0.4, 0.5)
        love.graphics.print("???", linha.x + 92, linha.y + 8)
        setFonte("pequena")
        love.graphics.print("Nao registrado ainda.", linha.x + 92, linha.y + 30)
      end
    end
  end

  love.graphics.setColor(1, 1, 1)
  desenharPaginacao(MENU.pagina, total, "b_")
end

function clickMenuBestiario(mx, my)
  local total = totalPaginas(#BESTIARY)
  local bw, bh = 110, 36
  local y = VH - 58
  local cx = VW/2
  if pontoEmRetangulo(mx, my, cx - bw*1.5 - 60, y, bw, bh) then
    MENU.pagina = math.max(1, MENU.pagina - 1); return true
  end
  if pontoEmRetangulo(mx, my, cx + bw*0.5 + 60, y, bw, bh) then
    MENU.pagina = math.min(total, MENU.pagina + 1); return true
  end
  if pontoEmRetangulo(mx, my, VW - 140, y, 100, bh) then
    MENU.tela = "principal"; return true
  end
  return false
end

-- ── 5.4 TELA: STATS ──────────────────────────────────────

function statsLinhas()
  local s = SAVE.stats
  return {
    {"Kills totais",        s.kills},
    {"Bosses derrotados",   s.bossesKilled},
    {"Mortes",              s.deaths},
    {"XP total",            math.floor(s.xpTotal)},
    {"DNA raro coletado",   s.dnaTotal},
    {"Runs jogadas",        s.runsTotal},
    {"Melhor nivel",        s.bestLevel},
    {"Melhor kill streak",  s.bestStreak},
    {"Tempo total",         string.format("%d:%02d",
        math.floor(s.tempoTotal/60), math.floor(s.tempoTotal%60))},
    {"Distancia",           string.format("%.0f px", s.distancia)},
  }
end

function desenharMenuStats()
  desenharFundoMenu()
  desenharTituloMenu("ESTATISTICAS", "Sua carreira completa")

  local x, y0 = 180, 132
  local w, h = VW - 360, 32
  for i, par in ipairs(statsLinhas()) do
    local y = y0 + (i-1)*(h+4)
    if i % 2 == 0 then
      love.graphics.setColor(1, 1, 1, 0.04)
      love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    end
    setFonte("normal")
    love.graphics.setColor(0.75, 0.85, 0.95)
    love.graphics.print(par[1], x + 16, y + 6)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(tostring(par[2]), x, y + 6, w - 16, "right")
  end

  desenharBotao(VW/2 - 60, VH - 56, 120, 38, "VOLTAR", MENU.hover == "voltar")
end

function clickMenuStats(mx, my)
  if pontoEmRetangulo(mx, my, VW/2 - 60, VH - 56, 120, 38) then
    MENU.tela = "principal"; return true
  end
  return false
end

-- ── 5.5 TELA: OPCOES ─────────────────────────────────────

function opcoesBotoes()
  local w, h = 280, 44
  local x = VW/2 - w/2
  local y0 = 200
  local gap = 10
  return {
    { id="musica", x=x, y=y0 + (h+gap)*0, w=w, h=h,
      txt="MUSICA: " .. (SAVE.options.musica and "ON" or "OFF") },
    { id="som",    x=x, y=y0 + (h+gap)*1, w=w, h=h,
      txt="SOM: "    .. (SAVE.options.som    and "ON" or "OFF") },
    { id="reset",  x=x, y=y0 + (h+gap)*2, w=w, h=h,
      txt="APAGAR SAVE", cor={0.5, 0.2, 0.2} },
    { id="voltar", x=x, y=y0 + (h+gap)*3, w=w, h=h,
      txt="VOLTAR" },
  }
end

function desenharMenuOpcoes()
  desenharFundoMenu()
  desenharTituloMenu("OPCOES")
  for _, b in ipairs(opcoesBotoes()) do
    desenharBotao(b.x, b.y, b.w, b.h, b.txt, MENU.hover == b.id, b.cor)
  end
end

function clickMenuOpcoes(mx, my)
  for _, b in ipairs(opcoesBotoes()) do
    if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then
      if b.id == "musica" then
        SAVE.options.musica = not SAVE.options.musica
        saveWrite()
      elseif b.id == "som" then
        SAVE.options.som = not SAVE.options.som
        saveWrite()
      elseif b.id == "reset" then
        love.filesystem.remove(SAVE_FILE)
        saveInit()
        saveWrite()
        table.insert(TOASTS, {txt="Save apagado.", t=0, dur=2, color={1, 0.5, 0.5}})
      elseif b.id == "voltar" then
        MENU.tela = "principal"
      end
      return true
    end
  end
  return false
end

-- ── 5.6 DISPATCHER ───────────────────────────────────────

function menuUpdate(dt)
  menuBgUpdate(dt)
  updateToasts(dt)
  Music:update(dt)
end

function menuDraw()
  if     MENU.tela == "principal"   then desenharMenuPrincipal()
  elseif MENU.tela == "nascimentos" then desenharMenuNascimentos()
  elseif MENU.tela == "conquistas"  then desenharMenuConquistas()
  elseif MENU.tela == "bestiario"   then desenharMenuBestiario()
  elseif MENU.tela == "stats"       then desenharMenuStats()
  elseif MENU.tela == "opcoes"      then desenharMenuOpcoes()
  end
  drawToasts()
end

function menuMouseMove(mx, my)
  MENU.hover = nil
  local t = MENU.tela
  if t == "principal" then
    for _, b in ipairs(botoesPrincipal()) do
      if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then MENU.hover = b.id; return end
    end
    for _, b in ipairs(botoesMini()) do
      if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then MENU.hover = b.id; return end
    end
  elseif t == "nascimentos" then
    for _, c in ipairs(celulasNascimentos()) do
      if pontoEmRetangulo(mx, my, c.x, c.y, c.w, c.h) then MENU.hover = c.id; return end
    end
    local bw, bh = 160, 44
    if pontoEmRetangulo(mx, my, VW/2 - bw - 12, VH - 70, bw, bh) then MENU.hover = "voltar";  return end
    if pontoEmRetangulo(mx, my, VW/2 + 12,      VH - 70, bw, bh) then MENU.hover = "iniciar"; return end
  elseif t == "conquistas" then
    local bw, bh = 110, 36
    local y, cx = VH - 58, VW/2
    if pontoEmRetangulo(mx, my, cx - bw*1.5 - 60, y, bw, bh) then MENU.hover = "c_prev";   return end
    if pontoEmRetangulo(mx, my, cx + bw*0.5 + 60, y, bw, bh) then MENU.hover = "c_next";   return end
    if pontoEmRetangulo(mx, my, VW - 140,          y, 100, bh) then MENU.hover = "c_voltar"; return end
  elseif t == "bestiario" then
    local bw, bh = 110, 36
    local y, cx = VH - 58, VW/2
    if pontoEmRetangulo(mx, my, cx - bw*1.5 - 60, y, bw, bh) then MENU.hover = "b_prev";   return end
    if pontoEmRetangulo(mx, my, cx + bw*0.5 + 60, y, bw, bh) then MENU.hover = "b_next";   return end
    if pontoEmRetangulo(mx, my, VW - 140,          y, 100, bh) then MENU.hover = "b_voltar"; return end
  elseif t == "stats" then
    if pontoEmRetangulo(mx, my, VW/2 - 60, VH - 56, 120, 38) then MENU.hover = "voltar"; return end
  elseif t == "opcoes" then
    for _, b in ipairs(opcoesBotoes()) do
      if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then MENU.hover = b.id; return end
    end
  end
end

function menuMouseClick(mx, my)
  local t = MENU.tela
  if     t == "principal"   then return clickMenuPrincipal(mx, my)
  elseif t == "nascimentos" then return clickMenuNascimentos(mx, my)
  elseif t == "conquistas"  then return clickMenuConquistas(mx, my)
  elseif t == "bestiario"   then return clickMenuBestiario(mx, my)
  elseif t == "stats"       then return clickMenuStats(mx, my)
  elseif t == "opcoes"      then return clickMenuOpcoes(mx, my)
  end
  return false
end

function menuKeyPressed(key)
  if key == "escape" then
    if MENU.tela == "principal" then
      love.event.quit()
    else
      MENU.tela = "principal"
    end
    return true
  end
  return false
end

-- ── 6.1 HELPERS MATEMÁTICOS ──────────────────────────────

function clamp(v, lo, hi)  return v < lo and lo or (v > hi and hi or v) end
function lerp(a, b, t)     return a + (b - a) * t end
function dist2(x1,y1,x2,y2)
  local dx, dy = x2-x1, y2-y1
  return dx*dx + dy*dy
end
function dist(x1,y1,x2,y2) return math.sqrt(dist2(x1,y1,x2,y2)) end
function angleTo(x1,y1,x2,y2) return math.atan2(y2-y1, x2-x1) end

-- ── 6.2 CÂMERA ───────────────────────────────────────────
-- Segue o player com clamp no mapa. Screen shake pra impacto.

CAM = { x = 0, y = 0, shakeT = 0, shakeMag = 0 }

function camShake(mag, dur)
  CAM.shakeMag = math.max(CAM.shakeMag, mag or 6)
  CAM.shakeT   = math.max(CAM.shakeT,   dur or 0.25)
end

function camUpdate(dt)
  if not player then return end
  local tx = player.x - VW/2
  local ty = player.y - VH/2
  if FASES and FASES.atual then
    tx = clamp(tx, 0, FASES.atual.w - VW)
    ty = clamp(ty, 0, FASES.atual.h - VH)
  end
  CAM.x = lerp(CAM.x, tx, 1 - 0.001 ^ dt)
  CAM.y = lerp(CAM.y, ty, 1 - 0.001 ^ dt)
  if CAM.shakeT > 0 then
    CAM.shakeT = CAM.shakeT - dt
    if CAM.shakeT <= 0 then CAM.shakeMag = 0 end
  end
end

function camOffsetX()
  if CAM.shakeT > 0 then
    return -CAM.x + (love.math.random()*2-1) * CAM.shakeMag
  end
  return -CAM.x
end
function camOffsetY()
  if CAM.shakeT > 0 then
    return -CAM.y + (love.math.random()*2-1) * CAM.shakeMag
  end
  return -CAM.y
end

-- ── 6.3 PARTÍCULAS ───────────────────────────────────────
-- Sistema simples pra juice: hit spark, morte, explosão, cura.

PARTICULAS = {}

function spawnPart(x, y, vx, vy, dur, cor, size, tipo)
  PARTICULAS[#PARTICULAS+1] = {
    x=x, y=y, vx=vx, vy=vy,
    t=0, dur=dur,
    cor=cor, size=size or 3, tipo=tipo or "spark",
  }
end

function burst(x, y, qtd, cor, speed, dur, size)
  for i = 1, qtd do
    local a = math.random() * math.pi * 2
    local s = speed * (0.4 + math.random() * 0.6)
    spawnPart(x, y, math.cos(a)*s, math.sin(a)*s,
      dur * (0.6 + math.random()*0.6), cor, size)
  end
end

function updateParticulas(dt)
  for i = #PARTICULAS, 1, -1 do
    local p = PARTICULAS[i]
    p.t = p.t + dt
    if p.t >= p.dur then
      table.remove(PARTICULAS, i)
    else
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vx = p.vx * (1 - 3*dt)
      p.vy = p.vy * (1 - 3*dt)
    end
  end
end

function drawParticulas()
  for _, p in ipairs(PARTICULAS) do
    local a = 1 - (p.t / p.dur)
    love.graphics.setColor(p.cor[1], p.cor[2], p.cor[3], a)
    if p.tipo == "spark" then
      love.graphics.circle("fill", p.x, p.y, p.size * a)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- ── 6.4 TEXTO FLUTUANTE (dano, cura, xp) ────────────────

TEXTO_FLUT = {}

function spawnTexto(x, y, txt, cor, size)
  TEXTO_FLUT[#TEXTO_FLUT+1] = {
    x=x, y=y, txt=txt, cor=cor, size=size or 14,
    t=0, dur=1.0, vy=-30,
  }
end

function updateTextoFlut(dt)
  for i = #TEXTO_FLUT, 1, -1 do
    local t = TEXTO_FLUT[i]
    t.t = t.t + dt
    t.y = t.y + t.vy * dt
    t.vy = t.vy + 40 * dt
    if t.t >= t.dur then table.remove(TEXTO_FLUT, i) end
  end
end

function drawTextoFlut()
  for _, t in ipairs(TEXTO_FLUT) do
    local a = 1 - (t.t / t.dur)
    love.graphics.setColor(t.cor[1], t.cor[2], t.cor[3], a)
    love.graphics.print(t.txt, t.x, t.y)
  end
  love.graphics.setColor(1, 1, 1)
end

-- ── 6.5 FÁBRICA DE FASES ─────────────────────────────────

FASES = {
  atual   = nil,
  ordem   = {"cell", "aquatic"},
  atualIdx = 0,
  bossesDerrotados = {},   -- por fase
}

local FASES_DEF = {
  cell = {
    nome     = "Fase Celular",
    w        = 1800,
    h        = 1800,
    corFundo = {0.06, 0.10, 0.18},
    corGrid  = {0.10, 0.18, 0.28},
    tema     = "celula",
    bossList = "cell",
  },
  aquatic = {
    nome     = "Fase Aquatica",
    w        = 2600,
    h        = 2600,
    corFundo = {0.04, 0.12, 0.22},
    corGrid  = {0.08, 0.20, 0.34},
    tema     = "aquatic",
    bossList = "aquatic",
  },
}

FOODS = {}     -- {x, y, tipo="comum"|"rara", valor, t}

function spawnComidaAleatoria(fase, qtd)
  for i = 1, qtd do
    local x = math.random(40, fase.w - 40)
    local y = math.random(40, fase.h - 40)
    FOODS[#FOODS+1] = {
      x=x, y=y, tipo="comum", valor=XP_SOURCES.comida,
      t=0, pulso=math.random()*6.28,
    }
  end
end

function spawnComidaRara(fase, qtd)
  for i = 1, qtd do
    local x = math.random(40, fase.w - 40)
    local y = math.random(40, fase.h - 40)
    FOODS[#FOODS+1] = {
      x=x, y=y, tipo="rara", valor=XP_SOURCES.comida_rara,
      t=0, pulso=math.random()*6.28,
    }
  end
end

function setupFase(nome)
  local def = FASES_DEF[nome]
  if not def then return false end

  FASES.atual = {
    nome      = def.nome,
    key       = nome,
    w         = def.w,
    h         = def.h,
    corFundo  = def.corFundo,
    corGrid   = def.corGrid,
    tema      = def.tema,
    bossList  = def.bossList,
    bossIdx   = 1,        -- qual boss da lista será o próximo
    tempoDecorrido = 0,
    proximoPredador = BAL.predator.spawnEvery,   -- ← TEM QUE SER ISSO
  }

  -- limpa entidades
  NPCS       = {}
  BOSSES_ATIVOS = {}
  BALAS      = {}
  BAUIS      = {}
  EVENTOS_ATIVOS = {}
  PARTICULAS = {}
  TEXTO_FLUT = {}
  FOODS      = {}

  -- comida inicial
  spawnComidaAleatoria(FASES.atual, 60)
  spawnComidaRara(FASES.atual, 4)

  -- posiciona player no centro
  if player then
    player.x = FASES.atual.w / 2
    player.y = FASES.atual.h / 2
    player.vx, player.vy = 0, 0
  end

  -- câmera
  CAM.x = clamp(player.x - VW/2, 0, FASES.atual.w - VW)
  CAM.y = clamp(player.y - VH/2, 0, FASES.atual.h - VH)

  Music:setTema(def.tema)
  return true
end

function avancarFase()
  FASES.atualIdx = FASES.atualIdx + 1
  if FASES.atualIdx > #FASES.ordem then
    gameState = "cutscene"
    cutsceneInit()
    return
  end

  -- dispara a transição visual em vez de carregar direto
  local proxKey = FASES.ordem[FASES.atualIdx]
  TRANSICAO.ativo    = true
  TRANSICAO.t        = 0
  TRANSICAO.proxFase = proxKey
  TRANSICAO.pular    = false

  if proxKey == "aquatic" then
    TRANSICAO.nomeFase = "FASE 2"
    TRANSICAO.subFase  = "AQUATICA"
  elseif proxKey == "cell" then
    TRANSICAO.nomeFase = "FASE 1"
    TRANSICAO.subFase  = "CELULAR"
  else
    TRANSICAO.nomeFase = "FASE"
    TRANSICAO.subFase  = string.upper(proxKey)
  end

  gameState = "transicao"
end

function setupFaseInicial()
  FASES.atualIdx = 1
  setupFase(FASES.ordem[1])
end

-- ── 6.6 START GAME ───────────────────────────────────────
-- Chamada pelo menu de nascimentos.

function startGame(birthId)
  registerRunStart()
  SAVE.runAtiva = nil
  runTempoInicio = love.timer.getTime()
  runDistancia   = 0
  player = Cell.new(0, 0, birthId, true)
  player:recalcularStats()
  player.hp = player.hpMax
  setupFaseInicial()
  gameState = "jogando"
  autosaveTimer = 0
  -- registra bestiário do nascimento se aplicável (opcional)
  
 dashCd = 0
autoAtaque = true
MENU_EVO.ativo = false
MENU_EVO.pagina = 1
player._avisouAgressao = false
if SAVE.moedaDNA == nil then SAVE.moedaDNA = 0 end
inicializarMissoes()
  NPCsPerseguindo = 0
player._avisouAgressao = false
desvioBias = 0
 
  saveWrite()
end

-- ── 7.1 LISTAS DE ENTIDADES ATIVAS ───────────────────────

NPCS          = {}   -- NPCs comuns/elites
BOSSES_ATIVOS = {}   -- bosses vivos
BALAS         = {}   -- projéteis (dos NPCs ou do player)
BAUIS         = {}   -- baús biológicos
EVENTOS_ATIVOS = {}  -- eventos em andamento
DROPS         = {}   -- orbes de XP/DNA no chão

-- Spawn timer base
spawnTimer = 0
SPAWN_INTERVALO_BASE = 3.5      -- segundos entre waves de NPC

-- ── 7.2 ESCOLHA ALEATÓRIA DE TRAITS ──────────────────────

function escolherTraits(qtd)
  local escolhidos = {}
  local pool = {}
  for _, id in ipairs(TRAIT_IDS) do pool[#pool+1] = id end
  qtd = math.min(qtd or 1, #pool)
  for i = 1, qtd do
    local idx = math.random(#pool)
    escolhidos[#escolhidos+1] = pool[idx]
    table.remove(pool, idx)
  end
  return escolhidos
end

-- ── 7.3 SPAWN DE NPC ─────────────────────────────────────
-- Spawna em uma borda do mapa fora da câmera.

function posicaoSpawnBorda(fase)
  local lado = math.random(1, 4)
  local x, y
  if lado == 1 then      -- topo
    x = math.random(40, fase.w - 40); y = 40
  elseif lado == 2 then  -- direita
    x = fase.w - 40; y = math.random(40, fase.h - 40)
  elseif lado == 3 then  -- baixo
    x = math.random(40, fase.w - 40); y = fase.h - 40
  else                   -- esquerda
    x = 40; y = math.random(40, fase.h - 40)
  end
  return x, y
end

function spawnNPC(fase, opts)
  opts = opts or {}
  local isElite = opts.elite or (math.random() < 0.08)

  local playerSize = (player and player.size) or 14
  local razaoTam = 0.55 + math.random() * 0.95
  local tamanhoBase = math.floor(playerSize * razaoTam)

  if math.random() < 0.15 then
    tamanhoBase = math.floor(playerSize * (1.35 + math.random() * 0.4))
  end

  local x, y = posicaoSpawnBorda(fase)

  local birthPool = {"natural", "lab", "cosmic", "symbiote", "ancestral"}
  local birthId   = birthPool[math.random(#birthPool)]

  local traits = escolherTraits(math.random(1, 2))
  local npc = Cell.new(x, y, birthId, false, traits)
  npc.npcId = birthId .. "_" .. tostring(love.math.random(100000))

  local mult = 1.0
  if FASES.atual.key == "aquatic" then mult = 1.6 end
  npc.hpMax = npc.hpMax * mult
  npc.hp    = npc.hpMax
  npc.dmg   = npc.dmg * mult
  npc.speed = npc.speed * (0.9 + math.random() * 0.2)

  npc.size = tamanhoBase

  for _, t in ipairs(npc.traits) do
    local d = t.def
    if d.hpMult    then npc.hpMax = npc.hpMax * d.hpMult; npc.hp = npc.hpMax end
    if d.speedMult then npc.speed = npc.speed * d.speedMult end
  end

  if isElite then
    npc.isElite = true
    npc.hpMax = npc.hpMax * BAL.npc.eliteMult
    npc.hp    = npc.hpMax
    npc.size  = npc.size * 1.4
    npc.dmg   = npc.dmg * 1.3
    npc.xpDrop = XP_SOURCES.npc_elite
  else
    npc.xpDrop = XP_SOURCES.npc
  end

  npc.estado     = ESTADO.PASSIVO
  npc.hostil     = false
  npc.passivo    = opts.passivo or false
  npc.agressivoTimer = 0
  npc.alertaTimer    = 0
  npc.wanderTimer    = 0
  npc.wanderAng      = math.random() * math.pi * 2

  if isElite then registerBestiary("npc_agress")
  else registerBestiary("npc_comum") end

  NPCS[#NPCS+1] = npc
  return npc
end

-- ── 7.4 SPAWN DE BOSS ────────────────────────────────────
-- Chama quando tempo na fase atinge marco OU wave específica.
-- Aqui, é chamado por progresso (matou X NPCs ou tempo).

function spawnBoss(fase, bossId)
  local bdef = BOSS_BY_ID[bossId]
  if not bdef then return end
  local x, y = posicaoSpawnBorda(fase)
  local boss = Cell.new(x, y, "natural", false, {bdef.trait or "agressivo"})
  boss.isBoss    = true
  boss.bossDef   = bdef
  boss.hpMax     = bdef.hp
  boss.hp        = bdef.hp
  boss.dmg       = bdef.dmg
  boss.speed     = bdef.speed
  boss.size      = bdef.size
  boss.xpDrop    = bdef.xp
  boss.bossFase  = 1
  boss.cor       = bdef.color
  boss.danoRecebidoTotal = 0
  boss.dmgBase = boss.dmg
  
  BOSSES_ATIVOS[#BOSSES_ATIVOS+1] = boss
  registerBestiary(bdef.id)
  Music:setTema("boss")
  camShake(10, 0.5)

  table.insert(TOASTS, {
    txt = "BOSS: " .. bdef.name,
    t = 0, dur = 4, color = {1, 0.5, 0.4},
  })
  return boss
end

-- ── SPAWN DO PREDADOR ────────────────────────────────────
function spawnPredador()
  if not FASES or not FASES.atual or not player then return end

  local cfg = BAL.predator
  local x, y = posicaoSpawnBorda(FASES.atual)

  local predador = Cell.new(x, y, "predatoria", false, {"agressivo"})
  predador.isBoss     = true
  predador.isPredador = true
  predador.bossDef    = {
    id      = "predador",
    name    = "Predador",
    final   = false,
    pattern = "predador_slash",
    xp = 300,
  }
  predador.hpMax    = player.hpMax * cfg.hpMult
  predador.hp       = predador.hpMax
  predador.dmg      = player.dmg * cfg.dmgMult
  predador.speed    = player.speed * cfg.speedMult
  predador.size     = 34
  predador.xpDrop   = 300
  predador.cor      = {0.85, 0.25, 0.35}
  predador.bossFase = 1
  predador.danoRecebidoTotal = 0
  predador.dmgBase = predador.dmg

  FASES.atual.predadorAtivo = true

  BOSSES_ATIVOS[#BOSSES_ATIVOS+1] = predador
  registerBestiary("predador")

  table.insert(TOASTS, {
    txt = "PREDADOR SE APROXIMA!",
    t = 0, dur = 4, color = {1, 0.3, 0.3},
  })
  Music:setTema("perigo")
  camShake(12, 0.6)
  burst(x, y, 40, {1, 0.3, 0.3}, 260, 1.2, 6)

  return predador
end

-- chamado quando o player derrota um boss
function onBossDefeated(boss)
  local bdef = boss.bossDef

  -- se for predador, libera pra aparecer de novo
  if boss.isPredador then
    FASES.atual.predadorAtivo = false
    FASES.atual.proximoPredador = FASES.atual.tempoDecorrido + BAL.predator.spawnEvery
  end

  progredirMissao("boss", 1)
  registerBossKill(bdef.id)
  player:addXP(bdef.xp or 200)

  -- DNA raro de boss
  player.dnaRaro = player.dnaRaro + (bdef.final and 3 or 1)
  SAVE.stats.dnaTotal = SAVE.stats.dnaTotal + (bdef.final and 3 or 1)
  if player.dnaRaro >= 10 then unlockAchievement("dna_max") end

  -- conquista "intocável"
  if boss.danoRecebidoTotal <= 0 then
    unlockAchievement("sem_dano_boss")
  end

-- registra na fase
if not FASES.bossesDerrotados[bdef.id] then
  FASES.bossesDerrotados[bdef.id] = true
end

  -- avança o índice de boss
  if FASES.atual and FASES.atual.bossIdx then
    FASES.atual.bossIdx = FASES.atual.bossIdx + 1
  end

  -- partículas + shake
  burst(boss.x, boss.y, 40, boss.cor, 260, 1.2, 6)
  camShake(14, 0.6)

  -- se era boss final da fase, avança
  if bdef.final then
    table.insert(TOASTS, {
      txt = "FASE COMPLETA!",
      t = 0, dur = 4, color = {0.5, 1, 0.6},
    })
    avancarFase()
  else
    Music:setTema(FASES.atual.tema)
  end
-- ═══ AGENDA PRÓXIMO BOSS (robusto) ═══
if not bdef.final and not boss.isPredador then
  -- reseta o timer pro ponto certo: próximo boss em 90s
  FASES.atual.tempoDecorrido = 60 + (FASES.atual.bossIdx - 2) * 90
  if FASES.atual.tempoDecorrido < 0 then FASES.atual.tempoDecorrido = 0 end
  FASES.atual._bossJaAvisou = nil
  BOSS_WARN.ativo = false   -- limpa qualquer aviso preso
end
end

-- ── 7.5 BAÚS BIOLÓGICOS (3 tipos) ────────────────────────
-- Tipos: comum (XP), raro (DNA), lendário (part grátis)

function spawnBau(fase)
  local x = math.random(80, fase.w - 80)
  local y = math.random(80, fase.h - 80)
  local r = math.random()
  local tipo = "comum"
  if r < 0.10 then tipo = "lendario"
  elseif r < 0.40 then tipo = "raro" end

  BAUIS[#BAUIS+1] = {
    x=x, y=y, tipo=tipo, t=0, aberto=false,
    cor = tipo == "lendario" and {1, 0.8, 0.3}
       or tipo == "raro"     and {0.6, 0.5, 1}
       or                       {0.5, 0.9, 0.6},
  }
end

function abrirBau(bau)
  if bau.aberto then return end
  bau.aberto = true
  progredirMissao("bau", 1)
  burst(bau.x, bau.y, 22, bau.cor, 160, 0.9, 5)
  camShake(4, 0.2)
  player:addXP(XP_SOURCES.bau_aberto)

  if bau.tipo == "comum" then
    spawnTexto(bau.x, bau.y - 10, "+" .. XP_SOURCES.bau_aberto .. " XP",
      {0.6, 1, 0.6}, 16)
  elseif bau.tipo == "raro" then
    player.dnaRaro = player.dnaRaro + 1
    SAVE.stats.dnaTotal = SAVE.stats.dnaTotal + 1
    spawnTexto(bau.x, bau.y - 10, "+1 DNA", {0.7, 0.6, 1}, 16)
  elseif bau.tipo == "lendario" then
    -- garante uma part aleatória grátis (se ainda não tiver no máximo)
    local escolhida = nil
    for _, p in ipairs(PARTS) do
      local lv = player.parts[p.id] or 0
      if lv < p.maxLv then escolhida = p; break end
    end
    if escolhida then
      player.parts[escolhida.id] = (player.parts[escolhida.id] or 0) + 1
      player:recalcularStats()
      spawnTexto(bau.x, bau.y - 10, escolhida.name .. " +1", {1, 0.9, 0.4}, 16)
    else
      player.dnaRaro = player.dnaRaro + 2
      SAVE.stats.dnaTotal = SAVE.stats.dnaTotal + 2
      spawnTexto(bau.x, bau.y - 10, "+2 DNA", {0.7, 0.6, 1}, 16)
    end
  end
end

-- ── 7.6 EVENTOS ALEATÓRIOS ───────────────────────────────
-- Sorteia a cada intervalo. Só um evento ativo por vez.

eventoTimer = 0
EVENTO_INTERVALO = 45      -- a cada 45s tenta sortear um evento

function sortearEvento()
  -- evita repetir o último
  local ultimo = FASES.ultimoEvento
  local pool = {}
  for _, e in ipairs(EVENTS) do
    if e.id ~= ultimo then pool[#pool+1] = e end
  end
  local ev = pool[math.random(#pool)]
  FASES.ultimoEvento = ev.id
  iniciarEvento(ev)
end

function iniciarEvento(ev)
  local ativo = { def = ev, t = 0, dur = ev.dur or 10 }
  EVENTOS_ATIVOS[#EVENTOS_ATIVOS+1] = ativo

  table.insert(TOASTS, {
    txt = "EVENTO: " .. ev.name,
    t = 0, dur = 4, color = {1, 0.85, 0.4},
  })

  -- efeito inicial por tipo
  if ev.id == "abundancia" then
    spawnComidaAleatoria(FASES.atual, 40)
    spawnComidaRara(FASES.atual, 3)
  elseif ev.id == "escassez" then
    -- limpa metade da comida
    for i = #FOODS, 1, -2 do table.remove(FOODS, i) end
  elseif ev.id == "migracao" or ev.id == "cardume" then
    for i = 1, 30 do
      local x = -60
      local y = math.random(60, FASES.atual.h - 60)
      local npc = spawnNPC(FASES.atual, { elite = false })
      npc.x, npc.y = x, y
      npc.vx = 180 + math.random()*60
      npc.passivo = true      -- não persegue, só atravessa
    end
  elseif ev.id == "chuvadna" then
    for i = 1, 5 do spawnBau(FASES.atual) end
  elseif ev.id == "ninho" then
    -- spawn de NPC gigante invulnerável que gera filhotes
    -- Ninho: NPC gigante que spawna filhotes por tempo limitado
local x, y = FASES.atual.w/2, FASES.atual.h/2
local ninho = Cell.new(x, y, "ancestral", false, {"tanque"})
ninho.isNinho    = true
ninho.hpMax      = 250
ninho.hp         = 250
ninho.size       = 40
ninho.speed      = 0
ninho.dmg        = 10
ninho.xpDrop     = 200
ninho.invuln     = false
ninho.spawnTimer = 0
ninho.filhotesMortos = 0
ninho.filhotesVivos  = 0          -- contador
ninho.maxFilhotes    = 10         -- limite
ninho.vidaTimer      = 30.0       -- 30 segundos de vida
ninho.estado         = ESTADO.AGRESSIVO
ninho.agressivoTimer = 999
NPCS[#NPCS+1] = ninho
  elseif ev.id == "tempestade" then
    ativo.raioTimer = 0
  end
  return ativo
end

function updateEventos(dt)
  for i = #EVENTOS_ATIVOS, 1, -1 do
    local ev = EVENTOS_ATIVOS[i]
    ev.t = ev.t + dt

    -- efeitos contínuos
    if ev.def.id == "tempestade" then
      ev.raioTimer = (ev.raioTimer or 0) - dt
      if ev.raioTimer <= 0 then
        ev.raioTimer = 0.35
        local rx = math.random(0, FASES.atual.w)
        local ry = math.random(0, FASES.atual.h)
        -- dano se perto
        if player then
          if dist(player.x, player.y, rx, ry) < 60 then
            player:takeDamage(8, rx, ry)
          end
        end
        burst(rx, ry, 12, {0.9, 0.9, 1}, 200, 0.5, 4)
        camShake(3, 0.15)
      end
    end

    -- duração
    if ev.dur > 0 and ev.t >= ev.dur then
      table.remove(EVENTOS_ATIVOS, i)
    end
  end
end

-- ── 7.7 DROPS (XP / DNA) ─────────────────────────────────

function spawnDropXP(x, y, valor)
  DROPS[#DROPS+1] = {
    x=x, y=y, tipo="xp", valor=valor,
    vx=(math.random()-0.5)*80, vy=(math.random()-0.5)*80,
    t=0, pulso=math.random()*6.28,
  }
end

function spawnDropDNA(x, y)
  DROPS[#DROPS+1] = {
    x=x, y=y, tipo="dna", valor=1,
    vx=(math.random()-0.5)*80, vy=(math.random()-0.5)*80,
    t=0, pulso=math.random()*6.28,
  }
end

function updateDrops(dt)
  if not player then return end
  for i = #DROPS, 1, -1 do
    local d = DROPS[i]
    d.t = d.t + dt
    d.pulso = d.pulso + dt * 3
    d.x = d.x + d.vx * dt
    d.y = d.y + d.vy * dt
    d.vx = d.vx * (1 - 3*dt)
    d.vy = d.vy * (1 - 3*dt)

    -- coleta
    local range = player.pickRange or 60
    if dist2(player.x, player.y, d.x, d.y) < range*range then
      -- atrai pra player
      local a = angleTo(d.x, d.y, player.x, player.y)
      d.x = d.x + math.cos(a) * 220 * dt
      d.y = d.y + math.sin(a) * 220 * dt
      if dist2(player.x, player.y, d.x, d.y) < 18*18 then
        if d.tipo == "xp" then
          player:addXP(d.valor)
          spawnTexto(player.x, player.y - 22, "+"..math.floor(d.valor),
            {0.7, 1, 0.7}, 13)
        elseif d.tipo == "dna" then
  player.dnaRaro = player.dnaRaro + 1
  SAVE.moedaDNA = (SAVE.moedaDNA or 0) + 1
  SAVE.stats.dnaTotal = SAVE.stats.dnaTotal + 1
  progredirMissao("dna", 1)
          spawnTexto(player.x, player.y - 22, "+1 DNA",
            {0.7, 0.6, 1}, 14)
          if player.dnaRaro >= 10 then unlockAchievement("dna_max") end
        end
        table.remove(DROPS, i)
      end
    end
  end
end

-- ── 8.1 COLISÕES ─────────────────────────────────────────
-- Detecção simples por distância (tudo é círculo).
-- Ordem: comida → baú → drops já tratados no updateDrops.
--        player vs NPC → dano de contato.
--        bala vs player → dano.
--        bala vs NPC/boss → dano.

-- Coleta de comida
function checarComida()
  if not player then return end
  local range = player.pickRange or 60
  local rr = range * range
  for i = #FOODS, 1, -1 do
    local f = FOODS[i]
    if dist2(player.x, player.y, f.x, f.y) < rr then
      -- atrai
      local a = angleTo(f.x, f.y, player.x, player.y)
      f.x = f.x + math.cos(a) * 200 * 0.016
      f.y = f.y + math.sin(a) * 200 * 0.016
      if dist2(player.x, player.y, f.x, f.y) < 20*20 then
        player:addXP(f.valor)
        spawnTexto(f.x, f.y - 8, "+" .. f.valor, {0.7, 1, 0.7}, 12)
        burst(f.x, f.y, 4, {0.6, 1, 0.6}, 60, 0.4, 2)
        table.remove(FOODS, i)
      end
    end
  end
end

-- Colisão player vs NPC (dano de contato)
function checarColisaoPlayerNPC(dt)
  if not player or not player.alive then return end

  for _, npc in ipairs(NPCS) do
    if npc.alive and not npc.passivo then
      local r = (player.size + npc.size) * 0.9
      if dist2(player.x, player.y, npc.x, npc.y) < r*r then
        if npc.estado == ESTADO.AGRESSIVO then
          local ok = player:takeDamage(npc.dmg, npc.x, npc.y)
          -- Acertou o player: reseta a frustração
          npc._frustracao = 0
          if ok == true then
            spawnTexto(player.x, player.y - 24,
              "-" .. math.floor(npc.dmg), {1, 0.5, 0.5}, 14)
            camShake(4, 0.15)
          end
        end
        local ang = angleTo(player.x, player.y, npc.x, npc.y)
        npc.vx = npc.vx + math.cos(ang) * 320
        npc.vy = npc.vy + math.sin(ang) * 320
      end
    end
  end

  for _, boss in ipairs(BOSSES_ATIVOS) do
  if boss.alive then
    local r = (player.size + boss.size) * 0.95
    if dist2(player.x, player.y, boss.x, boss.y) < r*r then
      local ok = player:takeDamage(boss.dmg, boss.x, boss.y)
      if ok == true then
        spawnTexto(player.x, player.y - 24,
          "-" .. math.floor(boss.dmg), {1, 0.4, 0.4}, 16)
        camShake(7, 0.2)
      end
    end
  end
end
end
-- Baús
function checarBauis()
  if not player then return end
  for _, b in ipairs(BAUIS) do
    if not b.aberto then
      local r = player.size + 20
      if dist2(player.x, player.y, b.x, b.y) < r*r then
        abrirBau(b)
      end
    end
  end
end

-- Balas
function checarBalas(dt)
  for i = #BALAS, 1, -1 do
    local b = BALAS[i]
    b.t = b.t + dt
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt

    -- sai do mapa
    if FASES.atual and
       (b.x < 0 or b.x > FASES.atual.w or
        b.y < 0 or b.y > FASES.atual.h) then
      table.remove(BALAS, i)
    else
      local removida = false

      if b.dono == "player" then
        -- bala do player acerta NPCs e bosses
        for _, npc in ipairs(NPCS) do
          if npc.alive and not npc.invuln then
            local r = npc.size + b.size
            if dist2(b.x, b.y, npc.x, npc.y) < r*r then
              aplicarDanoEmNPC(npc, b.dmg, b.x, b.y)
              burst(b.x, b.y, 6, b.cor, 120, 0.4, 3)
              removida = true
              break
            end
          end
        end
        if not removida then
          for _, boss in ipairs(BOSSES_ATIVOS) do
            if boss.alive and boss.bossInvuln <= 0 then
              local r = boss.size + b.size
              if dist2(b.x, b.y, boss.x, boss.y) < r*r then
                aplicarDanoEmBoss(boss, b.dmg, b.x, b.y)
                burst(b.x, b.y, 6, b.cor, 120, 0.4, 3)
                removida = true
                break
              end
            end
          end
        end
      else
        -- bala de inimigo acerta o player
        if player and player.alive then
          local r = player.size + b.size
          if dist2(b.x, b.y, player.x, player.y) < r*r then
            local ok = player:takeDamage(b.dmg, b.x, b.y)
            if ok == true then
              spawnTexto(player.x, player.y - 24,
                "-" .. math.floor(b.dmg), {1, 0.5, 0.5}, 14)
              camShake(3, 0.12)
            end
            removida = true
          end
        end
      end

      if removida then table.remove(BALAS, i) end
    end
  end
end

-- ── 8.2 ENTER / MORTE DE NPC ─────────────────────────────

function aplicarDanoEmNPC(npc, dmg, fromX, fromY)
  if not npc or not npc.alive then return end

 -- Sempre reseta o timer do player quando ele ataca (V6)
npc.agressivoTimer = BAL.comportamento.tempoAgressivo
npc.hostil         = true
npc._cacando       = false
npc._alvoNPC       = nil

-- Avisa só na primeira vez da run
if player and not player._avisouAgressao then
  player._avisouAgressao = true
  table.insert(TOASTS, {
    txt = "Os protozoarios estao furiosos!",
    t = 0, dur = 3, color = {1, 0.6, 0.4},
  })
end

  local mult = 1.0
  if player then
    mult = mult * (player.dmgMul or 1.0)
    if npc.marcado and npc.marcadoT > 0 then mult = mult * 1.5 end
  end
  local final = dmg * mult

  local ok = npc:takeDamage(final, fromX, fromY)
  if ok == true then
    spawnTexto(npc.x, npc.y - 14, "-" .. math.floor(final),
      {1, 0.85, 0.5}, 12)
    if player and player.ability and
       player.ability.ativa and player.ability.id == "linkvital" then
      local cura = final * 0.30
      player:heal(cura)
      spawnTexto(player.x, player.y - 26, "+" .. math.floor(cura),
        {0.4, 1, 0.4}, 13)
    end
  end
end

function aplicarDanoEmBoss(boss, dmg, fromX, fromY)
  local mult = 1.0
  if player then mult = mult * (player.dmgMul or 1.0) end
  local final = dmg * mult

  local ok = boss:takeDamage(final, fromX, fromY)
  if ok == true then
    spawnTexto(boss.x, boss.y - boss.size - 6, "-" .. math.floor(final),
      {1, 0.6, 0.5}, 15)
    if player and player.ability and
       player.ability.ativa and player.ability.id == "linkvital" then
      player:heal(final * 0.30)
    end
    -- fase do boss
    local pct = boss.hp / boss.hpMax
    local f = 1
    if pct <= BAL.boss.phaseThresholds[2] then f = 3
    elseif pct <= BAL.boss.phaseThresholds[1] then f = 2 end
    if f > boss.bossFase then
      boss.bossFase = f
      boss.bossInvuln = BAL.boss.invulnOnPhase
      camShake(10, 0.4)
      burst(boss.x, boss.y, 30, boss.cor, 220, 0.8, 5)
      table.insert(TOASTS, {
        txt = "FASE " .. f .. " - " .. boss.bossDef.name,
        t = 0, dur = 2.5, color = {1, 0.6, 0.4},
      })
      if f == 3 then
  boss.dmg = (boss.dmgBase or boss.dmg) * BAL.boss.enrageMult
end
    end
  end
end

function onNPCKilled(npc)
  npc.alive = false
  
  -- decrementa contador do ninho se era filhote
  if npc._doNinho then
    for _, n in ipairs(NPCS) do
      if n.isNinho and n.alive then
        n.filhotesVivos = math.max(0, n.filhotesVivos - 1)
        break
      end
    end
  end

  -- DNA comum por kill (persistente)
  SAVE.moedaDNA = (SAVE.moedaDNA or 0) + 1
  if npc.isElite then
    SAVE.moedaDNA = SAVE.moedaDNA + 4   -- elite dá 5 no total
  end

  registerKill()
  progredirMissao("kill", 1)
  registerKill()
  if player then player:onKillStreak() end

  -- XP por drop
  local valor = npc.xpDrop or XP_SOURCES.npc
  -- Chuva de DNA: 3x
  if temEvento("chuvadna") then valor = valor * 3 end
  spawnDropXP(npc.x, npc.y, valor)

  -- DNA raro de elite
  if npc.isElite then
    spawnDropDNA(npc.x, npc.y)
  end

  -- trait explosivo
  for _, t in ipairs(npc.traits) do
    if t.id == "explosivo" then
      local exp = t.def.explodeOnDeath
      burst(npc.x, npc.y, 18, {1, 0.5, 0.3}, 200, 0.6, 5)
      camShake(5, 0.2)
      if player and player.alive then
        if dist2(player.x, player.y, npc.x, npc.y) < exp.radius * exp.radius then
          local ok = player:takeDamage(exp.dmg, npc.x, npc.y)
          if ok == true then
            spawnTexto(player.x, player.y - 26,
              "-" .. exp.dmg, {1, 0.5, 0.3}, 15)
          end
        end
      end
    end
  end

  -- Regeneração (mutação): cura ao matar
  if player and player.mutacoes and player.mutacoes["regenmorte"] then
    player:heal(player.hpMax * 0.05)
  end
end

function atualizarInimigosVivos(dt)
  -- remove NPCs mortos da lista, mas garante que onNPCKilled foi chamado
  for i = #NPCS, 1, -1 do
    local npc = NPCS[i]
    if not npc.alive then
      if not npc.naoContaKill then
        onNPCKilled(npc)
      end
      table.remove(NPCS, i)
    end
  end
  for i = #BOSSES_ATIVOS, 1, -1 do
    local boss = BOSSES_ATIVOS[i]
    if not boss.alive then
      onBossDefeated(boss)
      table.remove(BOSSES_ATIVOS, i)
    end
  end
end

-- ── 8.3 EVENTO HELPERS ───────────────────────────────────

function temEvento(id)
  for _, e in ipairs(EVENTOS_ATIVOS) do
    if e.def.id == id then return true end
  end
  return false
end

-- ── REMOVE UM EVENTO ATIVO PELO ID ──────────────────────
function removerEvento(id)
  for i = #EVENTOS_ATIVOS, 1, -1 do
    if EVENTOS_ATIVOS[i].def.id == id then
      table.remove(EVENTOS_ATIVOS, i)
    end
  end
end

function eventoAtivo(id)
  for _, e in ipairs(EVENTOS_ATIVOS) do
    if e.def.id == id then return e end
  end
  return nil
end

-- ── 9.1 UPDATE JOGO (loop principal) ─────────────────────
-- ── UPDATE DO AVISO DE BOSS ─────────────────────────────
function updateAvisoBoss(dt)
  if not BOSS_WARN.ativo then return end

  BOSS_WARN.t = BOSS_WARN.t + dt

  -- efeito contínuo: shake leve
  if math.random() < dt * 3 then
    camShake(2, 0.08)
  end

  -- acabou o aviso → spawna o boss
  if BOSS_WARN.t >= BOSS_WARN.dur then
    BOSS_WARN.ativo = false
    spawnBoss(BOSS_WARN.fase, BOSS_WARN.bossId)
    FASES.atual._bossJaAvisou = nil
  end
end

-- ── UPDATE DA TRANSIÇÃO ─────────────────────────────────
function updateTransicao(dt)
  TRANSICAO.t = TRANSICAO.t + dt

  if TRANSICAO.t >= TRANSICAO.dur or TRANSICAO.pular then
    -- volta ao jogo com a nova fase
    TRANSICAO.ativo = false
    setupFase(TRANSICAO.proxFase)
    gameState = "jogando"

    -- cura o player em 30%
    if player then
      player:heal(player.hpMax * 0.3)
    end

    table.insert(TOASTS, {
      txt = "FASE: " .. TRANSICAO.subFase,
      t = 0, dur = 3, color = {0.5, 0.9, 1},
    })
  end
end

function updateJogo(dt)
  -- timers globais
  autosaveTimer = autosaveTimer + dt
  if autosaveTimer >= AUTOSAVE_INTERVAL then
    autosaveTimer = 0
    saveWrite()
  end
  if runTempoInicio then
    SAVE.stats.tempoTotal = SAVE.stats.tempoTotal + dt
  end

  camUpdate(dt)
  updateToasts(dt)
  updatePlayer(dt)
  if dashCd > 0 then dashCd = dashCd - dt end
  atualizarAtaqueContato(dt)
  updateNPCs(dt)
  updateBosses(dt)
  updateBalas(dt)
  updateHabilidadesAtivas(dt)
  updateSpawns(dt)
  updateAvisoBoss(dt)
  updateEventos(dt)
  updateDrops(dt)
  updateParticulas(dt)
  updateTextoFlut(dt)
  checarComida()
  checarBauis()
  checarColisaoPlayerNPC(dt)
  checarBalas(dt)
  atualizarInimigosVivos(dt)
  checarMortePlayer()
  Music:update(dt)
end

-- ── 9.2 UPDATE PLAYER ────────────────────────────────────

-- ── ATAQUE POR CONTATO (melee automático) ────────────────
-- Dá um "soco" a qcada 0.35s em quem estiver encostando.

function atualizarAtaqueContato(dt)
  if not player or not player.alive then return end
  if not autoAtaque then return end   -- ← ADICIONA ESSA LINHA

  player.atkContatoTimer = (player.atkContatoTimer or 0) + dt
  if player.atkContatoTimer < 0.35 then return end

  -- acha o NPC/boss mais perto em contato
  local alvo, melhorD = nil, math.huge

  for _, npc in ipairs(NPCS) do
    if npc.alive and not npc.invuln then
      local r = player.size + npc.size
      local d = dist2(player.x, player.y, npc.x, npc.y)
      if d < r*r and d < melhorD then melhorD = d; alvo = npc end
    end
  end
  for _, boss in ipairs(BOSSES_ATIVOS) do
    if boss.alive and boss.bossInvuln <= 0 then
      local r = player.size + boss.size
      local d = dist2(player.x, player.y, boss.x, boss.y)
      if d < r*r and d < melhorD then melhorD = d; alvo = boss end
    end
  end

  if not alvo then return end
  player.atkContatoTimer = 0

  -- dano por soco (não mais dps × dt)
  local dmg = player.dmg * 2.5

  -- zera o iframes do alvo antes de bater (senão bloqueia)
  alvo.iframes = 0

  if alvo.isBoss then
    aplicarDanoEmBoss(alvo, dmg, player.x, player.y)
  else
    aplicarDanoEmNPC(alvo, dmg, player.x, player.y)
    -- empurra o NPC pra longe
    local ang = angleTo(player.x, player.y, alvo.x, alvo.y)
    alvo.vx = alvo.vx + math.cos(ang) * 120
    alvo.vy = alvo.vy + math.sin(ang) * 120
  end

  -- efeito visual do soco
  local ang = angleTo(player.x, player.y, alvo.x, alvo.y)
  burst(alvo.x, alvo.y, 5, player.birth.color, 100, 0.3, 3)
end

function updatePlayer(dt)
  if not player or not player.alive then return end
  player:updateTimers(dt)

  -- ── DASH (prioridade) ──
  if player.dashTimer and player.dashTimer > 0 then
    player.dashTimer = player.dashTimer - dt
    player.x = player.x + player.dashVX * dt
    player.y = player.y + player.dashVY * dt

    -- clamp no mapa mesmo durante o dash
    if FASES.atual then
      player.x = clamp(player.x, player.size, FASES.atual.w - player.size)
      player.y = clamp(player.y, player.size, FASES.atual.h - player.size)
    end
    return   -- pula o resto do updatePlayer (movimento normal, atrito, clamp)
  end

  -- (resto da função continua normal)
  local regen = (player.hpRegenBonus or BAL.player.hpRegen)
  
  -- regeneração passiva
  local regen = (player.hpRegenBonus or BAL.player.hpRegen)
  if regen > 0 then player:heal(regen * dt) end

  -- input direcional (atualizado em updateInput)
  local ax, ay = 0, 0
  if INPUT and INPUT.dir then
    ax, ay = INPUT.dir.x, INPUT.dir.y
  end
  
  if ax ~= 0 or ay ~= 0 then
  player.ultimaDirX, player.ultimaDirY = ax, ay
end

  -- velocidade final
  local spd = player.speed * (player.speedMul or 1.0)

  -- Dash turbo
  if player.ability.ativa and player.ability.id == "dashturbo" then
    spd = spd * 1.8
  end

  player.vx = player.vx + ax * spd * 10 * dt
  player.vy = player.vy + ay * spd * 10 * dt

  -- atrito
  local fric = 1 - 8 * dt
  if fric < 0 then fric = 0 end
  player.vx = player.vx * fric
  player.vy = player.vy * fric

  -- clamp de velocidade
  local vel = math.sqrt(player.vx^2 + player.vy^2)
  if vel > spd then
    player.vx = (player.vx / vel) * spd
    player.vy = (player.vy / vel) * spd
  end

  -- aplica
  player.x = player.x + player.vx * dt
  player.y = player.y + player.vy * dt

  -- distância percorrida (aproximação)
  SAVE.stats.distancia = SAVE.stats.distancia + vel * dt

  -- clamp no mapa
  if FASES.atual then
    player.x = clamp(player.x, player.size, FASES.atual.w - player.size)
    player.y = clamp(player.y, player.size, FASES.atual.h - player.size)
  end

  -- animação / visual (leve pulsar)
  player.tPulso = (player.tPulso or 0) + dt

  -- se morreu (via takeDamage em outra parte), checa
  if player.hp <= 0 then player.alive = false end
end

-- ── 9.3 UPDATE NPCs (IA com traits) ──────────────────────

local function traitOf(npc, id)
  for _, t in ipairs(npc.traits) do
    if t.id == id then return t.def end
  end
  return nil
end

function avaliarComportamentoNPC(npc, player)
  if not player or not player.alive then return ESTADO.PASSIVO end
  local cfg = BAL.comportamento
  local razao = npc.size / math.max(player.size, 1)

  if npc.agressivoTimer and npc.agressivoTimer > 0 then return ESTADO.AGRESSIVO end
  if npc.alertaTimer and npc.alertaTimer > 0 then return ESTADO.ALERTA end

  local temAgressivo = false
  local temCauteloso = false
  for _, t in ipairs(npc.traits or {}) do
    if t.id == "agressivo" then temAgressivo = true end
    if t.id == "cauteloso" then temCauteloso = true end
  end

  if temCauteloso and (npc.hp / npc.hpMax) < 0.40 then return ESTADO.FUGINDO end

  if razao < cfg.limiarFuga then
    local d = dist2(npc.x, npc.y, player.x, player.y)
    if d < cfg.raioFuga * cfg.raioFuga then return ESTADO.FUGINDO end
    return ESTADO.PASSIVO
  end

  if razao <= cfg.limiarPerigo then
    if temAgressivo then
      if NPCsPerseguindo < cfg.maxAgressivosTrait then return ESTADO.AGRESSIVO end
      return ESTADO.ALERTA
    end
    return ESTADO.PASSIVO
  end

  if temAgressivo then return ESTADO.AGRESSIVO end
  local d = dist2(npc.x, npc.y, player.x, player.y)
  if d < 300 * 300 then return ESTADO.ALERTA end
  return ESTADO.PASSIVO
end

function provocarNPC(npc, origem)
  if not npc or not npc.alive then return end
  local cfg = BAL.comportamento
  npc.agressivoTimer = cfg.tempoAgressivo
  npc.estado         = ESTADO.AGRESSIVO
  npc.hostil         = true

  local raio2 = cfg.raioAlerta * cfg.raioAlerta
  local candidatos = {}
  for _, outro in ipairs(NPCS) do
    if outro ~= npc and outro.alive then
      if not outro.agressivoTimer or outro.agressivoTimer <= 0 then
        local d = dist2(npc.x, npc.y, outro.x, outro.y)
        if d < raio2 then
          local razao = outro.size / math.max(origem.size, 1)
          if razao >= cfg.limiarFuga then
            candidatos[#candidatos+1] = {npc=outro, d=d}
          end
        end
      end
    end
  end
  table.sort(candidatos, function(a,b) return a.d < b.d end)
  for i = 1, math.min(#candidatos, cfg.maxAlertados) do
    local o = candidatos[i].npc
    o.alertaTimer = cfg.tempoAlerta
    o.estado      = ESTADO.ALERTA
  end
end

function atualizarComportamentoNPC(npc, dt, player)
  -- ═══ FRUSTRAÇÃO: se não acertar o player, desiste ═══
if (npc.estado == ESTADO.AGRESSIVO or npc.hostil) and not npc._cacando then
  npc._frustracao = (npc._frustracao or 0) + dt
  if npc._frustracao >= (BAL.comportamento.tempoFrustracao or 8.0) then
    -- Desiste do player → vai caçar NPCs
    npc._frustracao = 0
    npc.hostil         = false
    npc.agressivoTimer = 0
    npc.marcado        = false
    npc._cacando       = true
    npc._cacaTimer     = 0
  end
else
  npc._frustracao = 0
end
  -- decrementa timer do player
  if npc.agressivoTimer and npc.agressivoTimer > 0 then
    npc.agressivoTimer = npc.agressivoTimer - dt
    if npc.agressivoTimer <= 0 then
      npc.hostil = false
      npc.marcado = false
      npc._cacando = true      -- ← entrou em modo caça
      npc._cacaTimer = 0
    end
  end

  -- ═══ MODO CAÇA (NPC vs NPC) ═══
  if npc._cacando and not npc.hostil then
    npc._cacaTimer = (npc._cacaTimer or 0) + dt

    -- alvo morreu ou não existe → procura outro
    if not npc._alvoNPC or not npc._alvoNPC.alive then
      npc._alvoNPC = procurarAlvoNPC(npc)
    end

    -- tem alvo → caça
    if npc._alvoNPC and npc._alvoNPC.alive then
      npc.estado = ESTADO.CACANDO
      -- se demorou muito sem pegar, desiste
      if npc._cacaTimer >= BAL.comportamento.tempoCacaMax then
        npc._cacando = false
        npc._alvoNPC = nil
      end
    else
      -- sem alvo → volta passivo
      npc._cacando = false
      npc._alvoNPC = nil
      npc.estado = ESTADO.PASSIVO
    end
    return
  end

  -- ═══ COMPORTAMENTO NORMAL ═══
  if npc.alertaTimer and npc.alertaTimer > 0 then
    npc.alertaTimer = npc.alertaTimer - dt
  end

  local estadoBase = avaliarComportamentoNPC(npc, player)

  if estadoBase == ESTADO.AGRESSIVO then
    if npc.estado ~= ESTADO.AGRESSIVO then
      local cfg = BAL.comportamento
      if NPCsPerseguindo < cfg.maxPerseguindo then
        npc.estado = ESTADO.AGRESSIVO
      else
        npc.estado = ESTADO.ALERTA
      end
    end
  elseif npc.estado ~= ESTADO.AGRESSIVO or
         (npc.agressivoTimer and npc.agressivoTimer > 0) then
    npc.estado = estadoBase
  else
    npc.estado = npc.estado or estadoBase
  end
end

function decidirMovimentoNPC(npc, player, dt)
  local cfg = BAL.comportamento
  local estado = npc.estado or ESTADO.PASSIVO
  local dx, dy, spd = 0, 0, cfg.velocidadePassiva

  if estado == ESTADO.FUGINDO and player then
    local a = angleTo(player.x, player.y, npc.x, npc.y)
    dx, dy = math.cos(a), math.sin(a)
    spd = cfg.velocidadeFuga
    for _, t in ipairs(npc.traits or {}) do
      if t.id == "cauteloso" then spd = spd * 1.15 end
    end

  elseif estado == ESTADO.CACANDO and npc._alvoNPC then
    local alvo = npc._alvoNPC
    if alvo.alive then
        local a = angleTo(npc.x, npc.y, alvo.x, alvo.y)
        dx, dy = math.cos(a), math.sin(a)
        spd = npc.speed * 0.95
     end   
    
  elseif estado == ESTADO.AGRESSIVO and player then
    local a = angleTo(npc.x, npc.y, player.x, player.y)
    dx, dy = math.cos(a), math.sin(a)
    spd = npc.speed

  elseif estado == ESTADO.ALERTA and player then
    npc.oscTimer = (npc.oscTimer or 0) + dt
    local a = math.sin(npc.oscTimer * 1.5) * 0.6
    dx = math.cos(a) * 0.3
    dy = math.sin(a) * 0.3
    spd = cfg.velocidadePassiva * 0.7

  else
    npc.wanderTimer = (npc.wanderTimer or 0) - dt
    if npc.wanderTimer <= 0 then
      npc.wanderTimer = 2 + math.random() * 3
      npc.wanderAng   = math.random() * math.pi * 2
    end
    npc.wanderAng = npc.wanderAng or 0
    dx = math.cos(npc.wanderAng)
    dy = math.sin(npc.wanderAng)
    spd = cfg.velocidadePassiva
    for _, t in ipairs(npc.traits or {}) do
      if t.id == "gregario" then
        local melhor, melhorD = nil, (t.def.groupRadius or 140)^2
        for _, o in ipairs(NPCS) do
          if o ~= npc and o.alive then
            local d = dist2(npc.x, npc.y, o.x, o.y)
            if d < melhorD and d > 50*50 then melhorD = d; melhor = o end
          end
        end
        if melhor then
          local a = angleTo(npc.x, npc.y, melhor.x, melhor.y)
          dx, dy = math.cos(a), math.sin(a)
        end
        break
      end
    end
  end

  return dx, dy, spd
end

-- ── PROCURA UM ALVO NPC PRA CAÇAR ───────────────────────
function procurarAlvoNPC(npc)
  local cfg = BAL.comportamento
  local melhor, melhorD = nil, cfg.raioCaca * cfg.raioCaca

  for _, outro in ipairs(NPCS) do
    if outro ~= npc and outro.alive
       and not outro.isNinho and not outro.passivo
       and not outro.invuln then
      -- só caça quem não é muito maior (senão vira jantar)
      if outro.size <= npc.size * 1.15 then
        local d = dist2(npc.x, npc.y, outro.x, outro.y)
        if d < melhorD then
          melhorD = d
          melhor  = outro
        end
      end
    end
  end
  return melhor
end

-- ── DANO DE NPC EM NPC ──────────────────────────────────  ← AQUI
function aplicarDanoNpcNpc(atacante, alvo, dt)
  if not atacante.alive or not alvo.alive then return end

  atacante._atkTimer = (atacante._atkTimer or 0) + dt
  if atacante._atkTimer < BAL.comportamento.cdCaca then return end
  atacante._atkTimer = 0

  local dmg = atacante.dmg * BAL.comportamento.danoNpcNpc
  local ok = alvo:takeDamage(dmg, atacante.x, atacante.y)

  if ok then
    spawnTexto(alvo.x, alvo.y - 14, "-" .. math.floor(dmg),
      {1, 0.7, 0.4}, 11)
    burst(alvo.x, alvo.y, 3, {1, 0.7, 0.4}, 60, 0.3, 2)

    alvo._alvoNPC = atacante
    alvo._cacando  = true
    alvo._cacaTimer = 0
    alvo.hostil = false
    alvo.agressivoTimer = 0
    alvo.estado = ESTADO.CACANDO
  end
end

-- (aqui continua o updateNPCs, ou outra função)

function updateNPCs(dt)
  if not player then return end

  NPCsPerseguindo = 0
  for _, npc in ipairs(NPCS) do
    if npc.alive and npc.estado == ESTADO.AGRESSIVO then
      NPCsPerseguindo = NPCsPerseguindo + 1
    end
  end

  for _, npc in ipairs(NPCS) do
    if npc.alive then
      npc:updateTimers(dt)

      if npc.isNinho then
  -- ═══ VIDA LIMITADA ═══
  npc.vidaTimer = (npc.vidaTimer or 30) - dt
  if npc.vidaTimer <= 0 then
    npc.alive = false
    burst(npc.x, npc.y, 40, {0.9, 0.5, 0.4}, 260, 1.2, 6)
    camShake(12, 0.5)
    table.insert(TOASTS, {
      txt = "O ninho se desfez.",
      t = 0, dur = 2, color = {0.9, 0.8, 0.5},
    })
    removerEvento("ninho")
  end

  -- ═══ SPAWN DE FILHOTES (com limites) ═══
  npc.spawnTimer = npc.spawnTimer + dt
  if npc.spawnTimer >= 2.5
     and npc.filhotesVivos < npc.maxFilhotes
     and #NPCS < BAL.npcMass.cap then    -- respeita cap global
    npc.spawnTimer = 0
    local a = math.random() * math.pi * 2
    local filhote = spawnNPC(FASES.atual, { elite=false })
    filhote.x = npc.x + math.cos(a) * 30
    filhote.y = npc.y + math.sin(a) * 30
    filhote._doNinho = true               -- marca origem
    npc.filhotesVivos = npc.filhotesVivos + 1
  end

  -- ═══ MORTE POR HP ═══
if npc.hp <= 0 and npc.alive then
  npc.alive = false
  burst(npc.x, npc.y, 40, {0.9, 0.5, 0.4}, 260, 1.2, 6)
  camShake(12, 0.5)
  table.insert(TOASTS, {
    txt = "NINHO DERROTADO!",
    t = 0, dur = 2.5, color = {0.5, 1, 0.6},
  })
  removerEvento("ninho")   -- ← NOVA
end

  npc.vx, npc.vy = 0, 0

      elseif npc.passivo then
        npc.x = npc.x + npc.vx * dt
        npc.y = npc.y + npc.vy * dt
        if npc.x < -200 or npc.x > FASES.atual.w + 200
           or npc.y < -200 or npc.y > FASES.atual.h + 200 then
          npc.alive = false
          npc.naoContaKill = true
        end

      else
        for _, t in ipairs(npc.traits) do
          if t.id == "curandeiro" then
            npc.healTimer = (npc.healTimer or 0) + dt
            if npc.healTimer >= 0.5 then
              npc.healTimer = 0
              for _, o in ipairs(NPCS) do
                if o ~= npc and o.alive and
                   dist2(npc.x, npc.y, o.x, o.y) < (t.def.healAura.radius)^2 then
                  o:heal(t.def.healAura.hps * 0.5)
                end
              end
            end
          end
        end

        atualizarComportamentoNPC(npc, dt, player)
        local dx, dy, spd = decidirMovimentoNPC(npc, player, dt)

        npc.vx = npc.vx * (1 - 5*dt) + dx * spd * 5 * dt
        npc.vy = npc.vy * (1 - 5*dt) + dy * spd * 5 * dt
        npc.x = npc.x + npc.vx * dt
        npc.y = npc.y + npc.vy * dt

        -- ═══ COLISÃO NPC vs NPC ═══
if npc.estado == ESTADO.CACANDO and npc._alvoNPC then
  local alvo = npc._alvoNPC
  if alvo.alive then
    local r = (npc.size + alvo.size) * 0.9
    if dist2(npc.x, npc.y, alvo.x, alvo.y) < r*r then
      aplicarDanoNpcNpc(npc, alvo, dt)
    end
  else
    npc._alvoNPC = nil
  end
end
        
        npc.x = clamp(npc.x, npc.size, FASES.atual.w - npc.size)
        npc.y = clamp(npc.y, npc.size, FASES.atual.h - npc.size)
      end
    end
  end
end

-- ── 9.4 UPDATE BOSSES ────────────────────────────────────
-- Padrões por boss. Cada boss ataca periodicamente com base no pattern.

function updateBosses(dt)
  if not player then return end
  for _, boss in ipairs(BOSSES_ATIVOS) do
    if boss.alive then
      boss:updateTimers(dt)
      if boss.bossInvuln > 0 then boss.bossInvuln = boss.bossInvuln - dt end
      boss.bossPatternTimer = boss.bossPatternTimer + dt

      -- aproximação básica do player
      local spd = boss.speed
      if boss.bossFase == 3 then spd = spd * 1.15 end
      local a = angleTo(boss.x, boss.y, player.x, player.y)
      local distP = dist(boss.x, boss.y, player.x, player.y)

      -- mantém distância conforme pattern
      local idealDist = boss.size + player.size + 80
      if boss.bossDef.pattern == "pull" or boss.bossDef.pattern == "song_pull" then
        idealDist = 40
      elseif boss.bossDef.pattern == "tentacles" or
             boss.bossDef.pattern == "spike" or
             boss.bossDef.pattern == "burst_dash" then
        idealDist = 220
      end

      local dir = 1
      if distP < idealDist - 20 then dir = -1 end
      boss.vx = boss.vx * (1 - 4*dt) + math.cos(a) * spd * dir * 4 * dt
      boss.vy = boss.vy * (1 - 4*dt) + math.sin(a) * spd * dir * 4 * dt

      -- burst dash override
      if boss.dashing and boss.dashing.t > 0 then
        boss.dashing.t = boss.dashing.t - dt
        boss.vx = boss.dashing.vx
        boss.vy = boss.dashing.vy
      end

      boss.x = boss.x + boss.vx * dt
      boss.y = boss.y + boss.vy * dt
      boss.x = clamp(boss.x, boss.size, FASES.atual.w - boss.size)
      boss.y = clamp(boss.y, boss.size, FASES.atual.h - boss.size)

      -- ataques por pattern
      aplicarPatternBoss(boss, dt)
    end
  end
end

-- ── Padrões de boss ──────────────────────────────────────
-- ═══════════════════════════════════════════════════════
-- SISTEMA ADAPTATIVO DE TELEGRAPH (V6)
-- ═══════════════════════════════════════════════════════

-- Registra pra que lado o player desviou e ajusta o viés
function registrarDesvio(boss, angTele)
  if not player or not boss then return end

  -- ângulo atual do boss pro player
  local angPlayer = angleTo(boss.x, boss.y, player.x, player.y)

  -- diferença entre onde o ataque ia e onde o player está
  local diff = angPlayer - angTele
  while diff > math.pi  do diff = diff - math.pi * 2 end
  while diff < -math.pi do diff = diff + math.pi * 2 end

  -- diff > 0 = player à direita, < 0 = à esquerda
  if diff > 0.2 then
    desvioBias = math.min(1, desvioBias + 0.15)
  elseif diff < -0.2 then
    desvioBias = math.max(-1, desvioBias - 0.15)
  end

  -- decai lentamente (player pode mudar de padrão)
  desvioBias = desvioBias * 0.98
end

-- Aplica o viés no ângulo do ataque
function aplicarBias(ang)
  return ang + (desvioBias or 0) * 0.4   -- 0.4 rad ≈ 23 graus
end

function aplicarPatternBoss(boss, dt)
  -- ═══ SLASH PENDENTE DO PREDADOR (prioridade) ═══
  if boss.slashTelegraph then
    boss.slashTelegraph.t = boss.slashTelegraph.t - dt
    if boss.slashTelegraph.t <= 0 then
      local tg = boss.slashTelegraph
      local distP = dist(boss.x, boss.y, player.x, player.y)
      if distP < tg.range then
        local angP = angleTo(boss.x, boss.y, player.x, player.y)
        local diff = math.abs(angP - tg.ang)
        if diff > math.pi then diff = math.pi * 2 - diff end
        if diff < 0.6 then
          local ok = player:takeDamage(boss.dmg * 1.5, boss.x, boss.y)
          if ok == true then
            spawnTexto(player.x, player.y - 26,
              "SLASH!", {1, 0.3, 0.3}, 18)
            camShake(9, 0.3)
          end
        end
      end
      burst(boss.x, boss.y, 20, {1, 0.3, 0.3}, 200, 0.5, 5)
      boss.slashTelegraph = nil
      boss.bossPatternTimer = 0
    end
    return
  end

  -- ═══ TELEGRAPH DE BOSS (V6) ═══
if boss.telegraph then
  boss.telegraph.t = boss.telegraph.t - dt
  if boss.telegraph.t > 0 then
    return   -- ainda avisando
  else
    -- acabou: guarda o ângulo real pra usar no ataque
    boss._ultimoAngReal = boss.telegraph.angReal
    -- registra o desvio do player (se escapou)
    if boss.telegraph.tipo == "spike" or
       boss.telegraph.tipo == "burst_dash" or
       boss.telegraph.tipo == "charge_summon" then
      registrarDesvio(boss, boss.telegraph.ang or boss.telegraph.angReal)
    end
    boss.telegraph = nil
    -- continua o fluxo pra executar o ataque
  end
end
  
  -- ═══ LÓGICA NORMAL DOS BOSSES ═══
  local pat = boss.bossDef.pattern    
  local pat = boss.bossDef.pattern
  local cd = 2.2
  if boss.bossFase == 2 then cd = 1.8 end
  if boss.bossFase == 3 then cd = 1.4 end
  if pat == "segments" then cd = cd * 0.8 end

  if boss.bossPatternTimer < cd then return end
boss.bossPatternTimer = 0

-- ═══ AGENDA O TELEGRAPH (se ainda não mostrou) ═══
if not boss.telegraph and boss._tgJaMostrou ~= pat then
  -- tempo base por tipo
  local tBase = 0.5
  if pat == "spike" then tBase = 0.45
  elseif pat == "burst_dash" then tBase = 0.4
  elseif pat == "charge_summon" then tBase = 0.5
  elseif pat == "tentacles" then tBase = 0.6
  elseif pat == "predador_slash" then tBase = 0.9
  end

  -- encurta conforme a fase
  local mult = 1.0
  if boss.bossFase == 2 then mult = 0.85
  elseif boss.bossFase == 3 then mult = 0.7 end

  -- variação aleatória ±15%
  tBase = tBase * (0.85 + math.random() * 0.30)

  local tg = { t = tBase * mult, tMax = tBase * mult, tipo = pat }

  -- calcula ângulo-alvo (com bias adaptativo)
  if pat == "spike" or pat == "burst_dash" or pat == "charge_summon" then
    local angReal = angleTo(boss.x, boss.y, player.x, player.y)
    tg.ang = angReal
    tg.angReal = aplicarBias(angReal)

    -- FEINT: pode mostrar ângulo falso
    local chanceFeint = 0
    if boss.bossFase == 2 then chanceFeint = TELEGRAPH.feintChanceF2
    elseif boss.bossFase == 3 then chanceFeint = TELEGRAPH.feintChanceF3 end
    if math.random() < chanceFeint then
      local off = (math.random() < 0.5 and 1 or -1) * (0.6 + math.random() * 0.4)
      tg.angFalso = angReal + off
      tg.feint = true
    end
  elseif pat == "tentacles" then
    tg.raio = 140
  end

  boss.telegraph = tg
  boss._tgJaMostrou = pat
  return   -- não executa agora, só agenda
end
boss._tgJaMostrou = nil

  if pat == "spike" then
  local base = boss._ultimoAngReal
               or angleTo(boss.x, boss.y, player.x, player.y)
    local n = 5 + boss.bossFase
    for i = 1, n do
      local off = (i - (n+1)/2) * 0.18
      disparaBalaBoss(boss, base + off, 220 + boss.bossFase*40)
    end

  elseif pat == "split" then
    -- se ainda não dividiu e chegou a 50% HP, spawna 2 clones
    if not boss.jaSplittou and boss.hp / boss.hpMax <= 0.5 then
      boss.jaSplittou = true
      for i = 1, 2 do
        local a = math.random() * math.pi * 2
        local clone = Cell.new(boss.x + math.cos(a)*40, boss.y + math.sin(a)*40,
          "natural", false, {"agressivo"})
        clone.isBoss   = true
        clone.bossDef  = boss.bossDef
        clone.hpMax    = boss.hpMax * 0.35
        clone.hp       = clone.hpMax
        clone.dmg      = boss.dmg * 0.6
        clone.size     = boss.size * 0.7
        clone.speed    = boss.speed * 1.1
        clone.xpDrop   = 30
        clone.cor      = boss.cor
        BOSSES_ATIVOS[#BOSSES_ATIVOS+1] = clone
      end
      burst(boss.x, boss.y, 26, boss.cor, 200, 0.9, 5)
    end
    -- também atira
    local base = angleTo(boss.x, boss.y, player.x, player.y)
    disparaBalaBoss(boss, base, 240)

  elseif pat == "pull" then
    -- puxa player numa direção
    local a = angleTo(boss.x, boss.y, player.x, player.y)
    player.vx = player.vx + math.cos(a) * 220
    player.vy = player.vy + math.sin(a) * 220
    burst(boss.x, boss.y, 8, boss.cor, 80, 0.4, 3)

  elseif pat == "multiply" then
    -- spawna 3 mini clones se tiver menos de 4 clones vivos
    local clonesVivos = 0
    for _, b in ipairs(BOSSES_ATIVOS) do
      if b ~= boss and b.bossDef == boss.bossDef and b.alive then
        clonesVivos = clonesVivos + 1
      end
    end
    if clonesVivos < 4 then
      for i = 1, 2 do
        local a = math.random() * math.pi * 2
        local clone = Cell.new(boss.x + math.cos(a)*30, boss.y + math.sin(a)*30,
          "natural", false, {"agressivo"})
        clone.isBoss   = true
        clone.bossDef  = boss.bossDef
        clone.hpMax    = boss.hpMax * 0.20
        clone.hp       = clone.hpMax
        clone.dmg      = boss.dmg * 0.5
        clone.size     = boss.size * 0.5
        clone.speed    = boss.speed * 1.2
        clone.xpDrop   = 20
        clone.cor      = boss.cor
        BOSSES_ATIVOS[#BOSSES_ATIVOS+1] = clone
      end
    end

  elseif pat == "charge_summon" then
  local a = boss._ultimoAngReal
             or angleTo(boss.x, boss.y, player.x, player.y)
    boss.dashing = { t = 0.55, vx = math.cos(a)*420, vy = math.sin(a)*420 }
    for i = 1, 2 do
      spawnNPC(FASES.atual, {elite=false})
    end
    camShake(6, 0.3)

  elseif pat == "tentacles" then
    -- 8 projéteis em volta
    for i = 1, 8 do
      local a = (i-1) * (math.pi*2/8)
      disparaBalaBoss(boss, a, 200)
    end

  elseif pat == "song_pull" then
    -- atrai + investida
    local a = angleTo(boss.x, boss.y, player.x, player.y)
    player.vx = player.vx + math.cos(a) * 120
    player.vy = player.vy + math.sin(a) * 120
    boss.dashing = { t = 0.45, vx = math.cos(a)*380, vy = math.sin(a)*380 }

  elseif pat == "burst_dash" then
  local a1 = boss._ultimoAngReal
              or angleTo(boss.x, boss.y, player.x, player.y)
    boss.burstDashes = 3
    boss.burstAngle  = a1
    boss.dashing = { t = 0.35, vx = math.cos(a1)*480, vy = math.sin(a1)*480 }

  elseif pat == "segments" then
    -- espiral: projéteis em espiral
    boss.espiralAngle = (boss.espiralAngle or 0) + 0.6
    for i = 1, 3 do
      local a = boss.espiralAngle + i * 0.4
      disparaBalaBoss(boss, a, 220)
    end
    
  elseif pat == "predador_slash" then
  boss.slashTelegraph = {
    ang   = angleTo(boss.x, boss.y, player.x, player.y),
    t     = BAL.predator.slashTelegraph,
    range = BAL.predator.slashRange,
  }  
    
  elseif pat == "all" then
    -- combina: spike + dash + invoke
    local base = angleTo(boss.x, boss.y, player.x, player.y)
    for i = 1, 7 do
      local off = (i-4) * 0.16
      disparaBalaBoss(boss, base + off, 260)
    end
    boss.dashing = { t = 0.4, vx = math.cos(base)*380, vy = math.sin(base)*380 }
    if math.random() < 0.5 then spawnNPC(FASES.atual, {elite=false}) end
  end

  -- burst dashes contínuo
  if boss.burstDashes and boss.burstDashes > 0 and not boss.dashing then
    boss.burstDashes = boss.burstDashes - 1
    local a = angleTo(boss.x, boss.y, player.x, player.y)
    boss.dashing = { t = 0.35, vx = math.cos(a)*480, vy = math.sin(a)*480 }
  end
-- ═══ COMBO SEQUENCIAL (fase 3) ═══
if boss.bossFase == 3 and math.random() < TELEGRAPH.comboChanceF3 then
  boss.comboPendente = 1
end

-- Se tem combo pendente e ninguém tá executando, força próximo ataque
if boss.comboPendente and boss.comboPendente > 0 then
  if not boss.telegraph then
    boss.comboPendente = boss.comboPendente - 1
    boss.bossPatternTimer = 999   -- força ataque imediato no próximo frame
    boss._tgJaMostrou = nil       -- reseta pra permitir novo telegraph
  end
end
end

function disparaBalaBoss(boss, ang, speed)
  local dmg = boss.dmg * 0.6
  BALAS[#BALAS+1] = {
    x = boss.x + math.cos(ang) * (boss.size + 4),
    y = boss.y + math.sin(ang) * (boss.size + 4),
    vx = math.cos(ang) * speed,
    vy = math.sin(ang) * speed,
    dmg = dmg, size = 6, cor = boss.cor or {1, 0.5, 0.5},
    dono = "boss", t = 0,
  }
end

-- ── 9.5 UPDATE BALAS ─────────────────────────────────────

function updateBalas(dt)
  -- já atualizado em checarBalas (chamada depois)
end

-- ── 9.6 HABILIDADES ATIVAS (efeitos contínuos) ───────────

function updateHabilidadesAtivas(dt)
  if not player then return end
  local a = player.ability
  if not a or not a.ativa then return end

  if a.id == "analise" then
    -- marca NPCs e bosses próximos
    for _, npc in ipairs(NPCS) do
      if npc.alive then
        npc.marcado = true
        npc.marcadoT = a.tAtiva
      end
    end

  elseif a.id == "linkvital" then
    -- efeito contínuo tratado no dano (aplicarDanoEmNPC/Boss)

  elseif a.id == "rugido" then
    -- empurra NPCs pra longe
    for _, npc in ipairs(NPCS) do
      if npc.alive then
        local ang = angleTo(player.x, player.y, npc.x, npc.y)
        npc.vx = npc.vx + math.cos(ang) * 200 * dt * 8
        npc.vy = npc.vy + math.sin(ang) * 200 * dt * 8
        if npc.dmgMulRugido == nil then
          npc.dmg = npc.dmg * 0.85
          npc.dmgMulRugido = true
        end
      end
    end

  elseif a.id == "overclock" then
    for _, npc in ipairs(NPCS) do npc.speedMul = 0.5 end
    for _, boss in ipairs(BOSSES_ATIVOS) do boss.speedMul = 0.5 end

  elseif a.id == "barreira" then
    -- apenas bloqueia dano (tratado em Cell:takeDamage)

  elseif a.id == "frenesi" then
    player.dmgMul = 1.8
    player.defMul = 1.6  -- -40% defesa = 1.6x dano recebido

  elseif a.id == "adaptacao" then
    -- acha o inimigo mais forte e copia seu dano
    local maxDmg = 0
    for _, npc in ipairs(NPCS) do
      if npc.alive and npc.dmg > maxDmg then maxDmg = npc.dmg end
    end
    for _, boss in ipairs(BOSSES_ATIVOS) do
      if boss.alive and boss.dmg > maxDmg then maxDmg = boss.dmg end
    end
    if maxDmg > 0 then
      player.dmg = maxDmg
    end
  end
end

-- limpa efeitos quando habilidade acaba (chamado no updatePlayer)
-- adiciona na Cell:updateTimers implicitamente: quando ability.ativa vira false,
-- resetamos efeitos
local function resetEfeitosHabilidade()
  if not player then return end
  player.speedMul = 1.0
  player.dmgMul   = 1.0
  player.defMul   = 1.0
  
  -- restaura o dano base (Adaptação)
if player.dmgBase then
  player.dmg = player.dmgBase
end
  
  for _, npc in ipairs(NPCS) do
    npc.speedMul = 1.0
    if npc.dmgMulRugido then
      npc.dmg = npc.dmg / 0.85
      npc.dmgMulRugido = nil
    end
  end
  for _, boss in ipairs(BOSSES_ATIVOS) do boss.speedMul = 1.0 end
end

-- ── 9.7 TRIGGERS DE HABILIDADE ───────────────────────────

function triggerBoom(cel)
  local raio = 100
  local dmg  = cel.dmg * 2.5
  burst(cel.x, cel.y, 30, {1, 0.7, 0.3}, 260, 0.7, 6)
  camShake(7, 0.3)
  for _, npc in ipairs(NPCS) do
    if npc.alive and dist2(cel.x, cel.y, npc.x, npc.y) < raio*raio then
      aplicarDanoEmNPC(npc, dmg, cel.x, cel.y)
    end
  end
  for _, boss in ipairs(BOSSES_ATIVOS) do
    if boss.alive and dist2(cel.x, cel.y, boss.x, boss.y) < raio*raio then
      aplicarDanoEmBoss(boss, dmg, cel.x, cel.y)
    end
  end
end

function triggerMeteoro(cel)
  -- cai no ponto do mouse (ou na frente do player)
  local tx, ty = cel.x, cel.y
  if INPUT and INPUT.mouseMundo then
    tx, ty = INPUT.mouseMundo.x, INPUT.mouseMundo.y
  else
    tx = cel.x + math.cos(cel.rot or 0) * 200
    ty = cel.y + math.sin(cel.rot or 0) * 200
  end
  -- aviso visual
  burst(tx, ty, 20, {1, 0.5, 0.3}, 100, 0.5, 4)
  -- aplica dano
  local raio = 120
  local dmg  = cel.dmg * 5
  camShake(12, 0.5)
  for _, npc in ipairs(NPCS) do
    if npc.alive and dist2(tx, ty, npc.x, npc.y) < raio*raio then
      aplicarDanoEmNPC(npc, dmg, tx, ty)
    end
  end
  for _, boss in ipairs(BOSSES_ATIVOS) do
    if boss.alive and dist2(tx, ty, boss.x, boss.y) < raio*raio then
      aplicarDanoEmBoss(boss, dmg, tx, ty)
    end
  end
  burst(tx, ty, 40, {1, 0.4, 0.2}, 320, 1.0, 7)
end

function triggerCadeia(cel)
  -- acha o mais próximo
  local alvoMaisPerto, melhorD = nil, math.huge
  for _, npc in ipairs(NPCS) do
    if npc.alive then
      local d = dist2(cel.x, cel.y, npc.x, npc.y)
      if d < melhorD then melhorD = d; alvoMaisPerto = npc end
    end
  end
  if not alvoMaisPerto then
    for _, boss in ipairs(BOSSES_ATIVOS) do
      if boss.alive then
        local d = dist2(cel.x, cel.y, boss.x, boss.y)
        if d < melhorD then melhorD = d; alvoMaisPerto = boss end
      end
    end
  end
  if not alvoMaisPerto then return end

  -- cadeia: alvo atual → próximo até 5
  local visitados = { [alvoMaisPerto] = true }
  local atual = alvoMaisPerto
  local dmg = cel.dmg * 1.5
  for i = 1, 5 do
    -- dano
    if atual.isBoss then aplicarDanoEmBoss(atual, dmg, cel.x, cel.y)
    else aplicarDanoEmNPC(atual, dmg, cel.x, cel.y) end
    dmg = dmg * 0.75
    -- busca próximo
    local prox, melhorD2 = nil, 200*200
    for _, npc in ipairs(NPCS) do
      if npc.alive and not visitados[npc] then
        local d = dist2(atual.x, atual.y, npc.x, npc.y)
        if d < melhorD2 then melhorD2 = d; prox = npc end
      end
    end
    if not prox then break end
    -- traço visual
    burst((atual.x+prox.x)/2, (atual.y+prox.y)/2, 5, {1, 1, 0.4}, 60, 0.3, 3)
    visitados[prox] = true
    atual = prox
  end
  camShake(5, 0.2)
end

function triggerColheita(cel)
  -- rouba 25% do HP do mais próximo
  local alvo, melhorD = nil, math.huge
  for _, npc in ipairs(NPCS) do
    if npc.alive then
      local d = dist2(cel.x, cel.y, npc.x, npc.y)
      if d < melhorD then melhorD = d; alvo = npc end
    end
  end
  if alvo then
    local roubo = alvo.hp * 0.25
    alvo.hp = alvo.hp - roubo
    cel:heal(roubo)
    spawnTexto(alvo.x, alvo.y - 16, "-" .. math.floor(roubo),
      {1, 0.5, 0.7}, 14)
    spawnTexto(cel.x, cel.y - 26, "+" .. math.floor(roubo),
      {0.4, 1, 0.4}, 14)
    burst(alvo.x, alvo.y, 14, {0.8, 0.4, 0.8}, 140, 0.5, 4)
  end
end

-- ── DISPARA O AVISO DE BOSS ─────────────────────────────
function avisarBossProximo(fase, bossId)
  if BOSS_WARN.ativo then return end   -- já tem um aviso rolando

  local bdef = BOSS_BY_ID[bossId]
  if not bdef then return end

  BOSS_WARN.ativo  = true
  BOSS_WARN.t      = 0
  BOSS_WARN.nome   = bdef.name
  BOSS_WARN.bossId = bossId
  BOSS_WARN.fase   = fase

  -- música de perigo
  Music:setTema("perigo")
  camShake(4, 0.5)
end

-- ── 9.8 SPAWN AUTOMÁTICO (waves + bosses) ────────────────
function updateSpawns(dt)
  if not FASES.atual or not player then return end
  -- ═══ DEBUG TEMPORÁRIO ═══
if math.floor(FASES.atual.tempoDecorrido) % 10 == 0
   and math.floor(FASES.atual.tempoDecorrido) ~= (FASES.atual._ultimoDebug or 0) then
  FASES.atual._ultimoDebug = math.floor(FASES.atual.tempoDecorrido)
  print(string.format(
    "[DEBUG] tempo=%d bossIdx=%d bossesVivos=%d warnAtivo=%s jaAvisou=%s",
    math.floor(FASES.atual.tempoDecorrido),
    FASES.atual.bossIdx,
    #BOSSES_ATIVOS,
    tostring(BOSS_WARN.ativo),
    tostring(FASES.atual._bossJaAvisou)))
end
  
  FASES.atual.tempoDecorrido = FASES.atual.tempoDecorrido + dt
  spawnTimer = spawnTimer + dt

  -- ── PREDADOR: a cada 8 min ──
  if not FASES.atual.predadorAtivo and
   (not FASES.atual.proximoPredador or
    FASES.atual.tempoDecorrido >= FASES.atual.proximoPredador) then
  spawnPredador()
end
  -- spawn de NPCs
  local intervalo = SPAWN_INTERVALO_BASE
  if FASES.atual.key == "aquatic" then intervalo = intervalo * 0.85 end

  -- dificuldade escala com o nível do player
  local dif = 1 + (player.level - 1) * 0.08
  intervalo = intervalo / dif
  intervalo = math.max(0.8, intervalo)

  if spawnTimer >= intervalo then
    spawnTimer = 0
    local qtd = 1 + math.floor(player.level / 6)
    qtd = math.min(qtd, 4)
    for i = 1, qtd do spawnNPC(FASES.atual) end
  end

  -- spawn de baús ocasionais
  if math.random() < dt * 0.05 then
    spawnBau(FASES.atual)
  end

  -- spawn de comida de reposição
  if #FOODS < 40 and math.random() < dt * 2 then
    spawnComidaAleatoria(FASES.atual, 3)
  end
  if #FOODS < 5 and math.random() < dt * 0.5 then
    spawnComidaRara(FASES.atual, 1)
  end

  -- eventos
  eventoTimer = eventoTimer + dt
  if eventoTimer >= EVENTO_INTERVALO and #EVENTOS_ATIVOS == 0 then
    eventoTimer = 0
    sortearEvento()
  end

  -- boss: aviso 3s antes de spawnar
local proxBossEm = 60 + (FASES.atual.bossIdx - 1) * 90
if FASES.atual.tempoDecorrido >= proxBossEm and
   #BOSSES_ATIVOS == 0 and FASES.atual.bossIdx <= 5
   and not BOSS_WARN.ativo and not FASES.atual._bossJaAvisou then

  local lista = BOSSES[FASES.atual.bossList]
  local b = lista[FASES.atual.bossIdx]
  if b then
    avisarBossProximo(FASES.atual, b.id)
    FASES.atual._bossJaAvisou = true
  end
end
end

-- ── 9.9 MORTE DO PLAYER ──────────────────────────────────

function checarMortePlayer()
  if player and not player.alive and gameState == "jogando" then
    registerDeath()
    gameState = "gameover"
    gameOverTimer = 0
    Music:setTema("menu")
    SAVE.runAtiva = nil
    saveWrite()
  end
end

-- ── 9.10 RESET DE EFEITOS QUANDO HABILIDADE ACABA ────────
-- Chamado no final do updatePlayer indiretamente:
-- detecta a transição ativa=true → false
playerHabEstadoAnterior = false

local function checarFimHabilidade()
  if not player or not player.ability then return end
  local agora = player.ability.ativa
  if playerHabEstadoAnterior and not agora then
    resetEfeitosHabilidade()
  end
  playerHabEstadoAnterior = agora
end

-- hook no updateHabilidadesAtivas (chamada depois)
local _updateHab = updateHabilidadesAtivas
function updateHabilidadesAtivas(dt)
  _updateHab(dt)
  checarFimHabilidade()
end

-- ── 10.1 ESTADO DE INPUT ─────────────────────────────────

INPUT = {
  dir       = {x=0, y=0},     -- direção normalizada
  teclas    = {},             -- teclas pressionadas
  touch     = {
    ativo     = false,
    id        = nil,
    origem    = {x=0, y=0},
    atual     = {x=0, y=0},
    joystick  = {ativo=false, id=nil, ox=0, oy=0, dx=0, dy=0},
  },
  mouseMundo = {x=0, y=0},    -- posição do mouse em coordenadas do mundo
  joystickArea = {x=90, y=VH-100, r=70},   -- zona fixa do analógico (mobile)
  botaoHab     = {x=VW-90, y=VH-100, r=48},-- botão de habilidade (mobile)
  botaoPausa   = {x=VW-40, y=40, r=22},
  botaoHabPressionado = false,
}

-- Converte coordenadas de tela (window) → virtuais (VW x VH)
function screenToVirtual(mx, my)
  local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
  local sx, sy = ww / VW, wh / VH
  local s = math.min(sx, sy)
  local ox = (ww - VW*s) / 2
  local oy = (wh - VH*s) / 2
  return (mx - ox) / s, (my - oy) / s
end

-- Atualiza INPUT.dir baseado em teclas + joystick touch
function atualizarInputDir()
  local x, y = 0, 0
  if INPUT.teclas["a"] or INPUT.teclas["left"]  then x = x - 1 end
  if INPUT.teclas["d"] or INPUT.teclas["right"] then x = x + 1 end
  if INPUT.teclas["w"] or INPUT.teclas["up"]    then y = y - 1 end
  if INPUT.teclas["s"] or INPUT.teclas["down"]  then y = y + 1 end
  if x ~= 0 or y ~= 0 then
    local m = math.sqrt(x*x + y*y)
    INPUT.dir.x, INPUT.dir.y = x/m, y/m
    return
  end
  -- joystick touch
  local j = INPUT.touch.joystick
  if j.ativo then
    local m = math.sqrt(j.dx*j.dx + j.dy*j.dy)
    if m > 6 then
      INPUT.dir.x = j.dx / m
      INPUT.dir.y = j.dy / m
      return
    end
  end
  INPUT.dir.x, INPUT.dir.y = 0, 0
end

-- ── 10.2 TECLADO ─────────────────────────────────────────

function love.keypressed(key)
  if gameState == "menu" then
    if menuKeyPressed(key) then return end
  end

  INPUT.teclas[key] = true
  atualizarInputDir()

  -- ESC pausa no jogo
  if key == "escape" and gameState == "jogando" then
    gameState = "pausa"
    PAUSA.aba = "principal"
  elseif key == "escape" and gameState == "pausa" then
    gameState = "jogando"
  end

  -- Espaço = habilidade
  if key == "space" and gameState == "jogando" then
    if player and player.alive then player:usarHabilidade() end
  end

  -- P = pause rápido (útil pra teste)
  if key == "p" and gameState == "jogando" then
    gameState = "pausa"
  end
end

function love.keyreleased(key)
  INPUT.teclas[key] = false
  atualizarInputDir()
end

-- ── 10.3 MOUSE ───────────────────────────────────────────

function love.mousemoved(mx, my)
  local vx, vy = screenToVirtual(mx, my)
  if gameState == "menu" then
    menuMouseMove(vx, vy)
  elseif gameState == "jogando" then
    INPUT.mouseMundo.x = vx - camOffsetX()
    INPUT.mouseMundo.y = vy - camOffsetY()
  end
end

-- ── DASH ────────────────────────────────────────────────
function usarDash()
  if not player or not player.alive then return end
  if dashCd > 0 then return end
  dashCd = DASH_CD_MAX

  local dx, dy = INPUT.dir.x, INPUT.dir.y
  if dx == 0 and dy == 0 then
    dx = player.ultimaDirX or 1
    dy = player.ultimaDirY or 0
  end
  player.ultimaDirX, player.ultimaDirY = dx, dy

  -- ativa o dash por DASH_DUR segundos
  player.dashTimer  = DASH_DUR
  player.dashVX     = dx * DASH_FORCE
  player.dashVY     = dy * DASH_FORCE
  player.vx = player.dashVX
  player.vy = player.dashVY
  player.iframes = math.max(player.iframes or 0, DASH_DUR)

  burst(player.x, player.y, 12, player.birth.color, 200, 0.5, 4)
  camShake(3, 0.15)
end

-- ── COMPRAS (menu EVO) ──────────────────────────────────
function comprarPart(id)
  if not player then return end
  local p = PART_BY_ID[id]
  if not p then return end
  local lv = player.parts[id] or 0
  if lv >= p.maxLv then return end
  local custo = p.cost * (lv + 1)

  if (SAVE.moedaDNA or 0) < custo then
    table.insert(TOASTS, {
      txt = "DNA insuficiente", t=0, dur=1.5, color={1,0.5,0.5},
    })
    return
  end

  SAVE.moedaDNA = SAVE.moedaDNA - custo
  player.parts[id] = lv + 1
  player:recalcularStats()
  burst(player.x, player.y, 20, player.birth.color, 180, 0.8, 5)
  table.insert(TOASTS, {
    txt = p.name .. " Nv" .. (lv+1), t=0, dur=2, color={0.5,1,0.6},
  })
end

function comprarMutacao(id)
  if not player then return end
  local m = MUT_BY_ID[id]
  if not m then return end
  if player.mutacoes[id] then return end

  if (player.dnaRaro or 0) < m.cost then
    table.insert(TOASTS, {
      txt = "DNA raro insuficiente", t=0, dur=1.5, color={1,0.5,0.5},
    })
    return
  end

  player.dnaRaro = player.dnaRaro - m.cost
  player.mutacoes[id] = true
  player:recalcularStats()
  burst(player.x, player.y, 30, {0.8, 0.5, 1}, 220, 1.0, 6)
  table.insert(TOASTS, {
    txt = m.name .. " adquirida!", t=0, dur=2.5, color={0.8,0.5,1},
  })
end

function checarCliqueEVO(mx, my)
  local bw, bh = 200, 40
  local y0 = 80
  local cx = VW/2

  if pontoEmRetangulo(mx, my, VW - 120, 20, 90, 34) then
    MENU_EVO.ativo = false; return
  end
  if pontoEmRetangulo(mx, my, cx - bw - 8, y0, bw, bh) then
    MENU_EVO.aba = "upgrades"; MENU_EVO.pagina = 1; return
  end
  if pontoEmRetangulo(mx, my, cx + 8, y0, bw, bh) then
    MENU_EVO.aba = "mutacoes"; MENU_EVO.pagina = 1; return
  end

  local cols = 2
  local cw, ch = 320, 72
  local gapx, gapy = 16, 10
  local totalW = cols*cw + gapx
  local gx0 = VW/2 - totalW/2
  local gy0 = y0 + bh + 36

  local up = MENU_EVO.aba == "upgrades"
  local lista = up and PARTS or MUTATIONS
  local start = (MENU_EVO.pagina - 1) * MENU_EVO.itensPorPagina

  for i = 1, MENU_EVO.itensPorPagina do
    local idx = start + i
    local item = lista[idx]
    if item then
      local col = (i-1) % cols
      local row = math.floor((i-1) / cols)
      local x = gx0 + col*(cw+gapx)
      local y = gy0 + row*(ch+gapy)
      if pontoEmRetangulo(mx, my, x, y, cw, ch) then
        if up then comprarPart(item.id) else comprarMutacao(item.id) end
        return
      end
    end
  end

  local yp = VH - 46
  if pontoEmRetangulo(mx, my, cx - 180, yp, 90, 34) then
    MENU_EVO.pagina = math.max(1, MENU_EVO.pagina - 1); return
  end
  if pontoEmRetangulo(mx, my, cx + 90, yp, 90, 34) then
    local listaAtual = up and PARTS or MUTATIONS
    local total = totalPaginas2(#listaAtual, MENU_EVO.itensPorPagina)
    MENU_EVO.pagina = math.min(total, MENU_EVO.pagina + 1); return
  end
end

function checarBotoesHUD(vx, vy)
  local B = BOTOES_HUD

  -- se o menu EVO tá aberto, prioridade total
  if MENU_EVO.ativo then
    checarCliqueEVO(vx, vy)
    return true
  end

  -- PAUSE
  if dist2(vx, vy, B.pause.x, B.pause.y) < B.pause.r^2 then
    gameState = "pausa"; PAUSA.aba = "principal"; return true
  end

  -- AUTO toggle
  if dist2(vx, vy, B.auto.x, B.auto.y) < B.auto.r^2 then
    autoAtaque = not autoAtaque
    table.insert(TOASTS, {
      txt = "Ataque auto: " .. (autoAtaque and "ON" or "OFF"),
      t = 0, dur = 1.5, color = {0.7, 1, 0.7},
    })
    return true
  end

  -- EVO
  if dist2(vx, vy, B.evo.x, B.evo.y) < B.evo.r^2 then
    MENU_EVO.ativo = true
    MENU_EVO.aba = "upgrades"
    MENU_EVO.pagina = 1
    return true
  end

  -- DASH
  if dist2(vx, vy, B.dash.x, B.dash.y) < B.dash.r^2 then
    usarDash()
    return true
  end

  -- HABILIDADE única
  if dist2(vx, vy, B.hab.x, B.hab.y) < B.hab.r^2 then
    if player and player.alive then player:usarHabilidade() end
    return true
  end

  return false
end

function love.mousepressed(mx, my, button)
  if button ~= 1 then return end
  local vx, vy = screenToVirtual(mx, my)
  if gameState == "menu" then
    menuMouseClick(vx, vy)
  elseif gameState == "jogando" then
    if checarBotoesHUD(vx, vy) then return end
  elseif gameState == "pausa" then
    pausaClick(vx, vy)
  elseif gameState == "gameover" then
    gameOverClick(vx, vy)
  elseif gameState == "cutscene" then
    cutsceneClick(vx, vy)
  elseif gameState == "transicao" then
  TRANSICAO.pular = true
  end
end

-- ── 10.4 TOQUE (mobile) ─────────────────────────────────

function love.touchpressed(id, x, y, dx, dy)
  local vx, vy = screenToVirtual(x, y)

  if gameState == "menu" then
    menuMouseClick(vx, vy); return
  elseif gameState == "jogando" then
    if checarBotoesHUD(vx, vy) then return end
    -- joystick virtual
    if not INPUT.touch.joystick.ativo and vx < VW * 0.55 then
      INPUT.touch.joystick = {
        ativo = true, id = id,
        ox = vx, oy = vy, dx = 0, dy = 0,
      }
    end
  elseif gameState == "pausa" then
    pausaClick(vx, vy)
  elseif gameState == "gameover" then
    gameOverClick(vx, vy)
  elseif gameState == "cutscene" then
    cutsceneClick(vx, vy)
  elseif gameState == "transicao" then
  TRANSICAO.pular = true      
  end
end

function love.touchmoved(id, x, y, dx, dy)
  local vx, vy = screenToVirtual(x, y)
  local j = INPUT.touch.joystick
  if j.ativo and j.id == id then
    j.dx = clamp(vx - j.ox, -60, 60)
    j.dy = clamp(vy - j.oy, -60, 60)
    -- joystick solto volta? não; atualiza dir
    atualizarInputDir()
  end
end

function love.touchreleased(id, x, y, dx, dy)
  local j = INPUT.touch.joystick
  if j.ativo and j.id == id then
    j.ativo = false
    j.dx, j.dy = 0, 0
    atualizarInputDir()
  end
end

-- ── 10.5 HABILIDADE: acionamento e HUD de cooldown ───────
-- A lógica de efeito em si já está em Cell:usarHabilidade e nos triggers.
-- Aqui só desenhamos o cooldown no HUD.

function desenharBotaoHabilidade()
  if not player or not player.ability then return end
  local bh = INPUT.botaoHab
  local a  = player.ability

  -- base
  love.graphics.setColor(0.10, 0.14, 0.20, 0.85)
  love.graphics.circle("fill", bh.x, bh.y, bh.r)
  love.graphics.setColor(a.color[1], a.color[2], a.color[3], 0.9)
  love.graphics.setLineWidth(4)
  love.graphics.circle("line", bh.x, bh.y, bh.r)

  -- label
  setFonte("pequena")
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(a.name:upper(), bh.x - bh.r, bh.y - 6, bh.r*2, "center")

  -- cooldown overlay (arco de pizza)
  if a.cd > 0 then
    local pct = 1 - (a.cd / a.cdMax)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.arc("fill", bh.x, bh.y, bh.r - 2, -math.pi/2,
      -math.pi/2 + (1-pct) * math.pi * 2)
    setFonte("media")
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(string.format("%.0f", math.ceil(a.cd)),
      bh.x - bh.r, bh.y - 10, bh.r*2, "center")
  end

  -- se ativa, brilha
  if a.ativa then
    love.graphics.setColor(a.color[1], a.color[2], a.color[3], 0.35)
    love.graphics.circle("fill", bh.x, bh.y, bh.r + 6)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.setLineWidth(1)
end

function desenharJoystickTouch()
  local j = INPUT.touch.joystick
  if not j.ativo then return end
  -- base
  love.graphics.setColor(1, 1, 1, 0.10)
  love.graphics.circle("fill", j.ox, j.oy, 60)
  love.graphics.setColor(1, 1, 1, 0.20)
  love.graphics.circle("line", j.ox, j.oy, 60)
  -- pino
  love.graphics.setColor(0.7, 0.9, 1.0, 0.6)
  love.graphics.circle("fill", j.ox + j.dx, j.oy + j.dy, 26)
  love.graphics.setColor(1, 1, 1)
end

-- ── 11.1 TRANSFORMAÇÃO VIRTUAL ───────────────────────────
-- Desenha tudo numa viewport VW x VH, mantendo aspecto em qualquer tela.

function pushVirtual()
  local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
  local s = math.min(ww / VW, wh / VH)
  local ox = (ww - VW * s) / 2
  local oy = (wh - VH * s) / 2
  love.graphics.push()
  love.graphics.translate(ox, oy)
  love.graphics.scale(s, s)
end

function popVirtual()
  love.graphics.pop()
end

-- ── 11.2 DRAW DO JOGO ────────────────────────────────────

-- ── MISSOES ─────────────────────────────────────────────
function inicializarMissoes()
  MISSOES_ATIVAS = {}
  local pool = {}
  for _, m in ipairs(MISSOES_POOL) do pool[#pool+1] = m end
  for i = 1, 3 do
    if #pool == 0 then break end
    local idx = math.random(#pool)
    local m = pool[idx]
    table.remove(pool, idx)
    MISSOES_ATIVAS[#MISSOES_ATIVAS+1] = {
      def = m, progresso = 0, completa = false,
    }
  end
end

function progredirMissao(tipo, qtd)
  qtd = qtd or 1
  for _, m in ipairs(MISSOES_ATIVAS) do
    if not m.completa and m.def.tipo == tipo then
      m.progresso = m.progresso + qtd
      if m.progresso >= m.def.alvo then
        m.completa = true
        local r = m.def.recompensa
        if r.xp  and player then player:addXP(r.xp) end
        if r.dna then SAVE.moedaDNA = (SAVE.moedaDNA or 0) + r.dna end
        table.insert(TOASTS, {
          txt = "MISSAO: " .. m.def.txt,
          t = 0, dur = 3.5, color = {1, 0.9, 0.4},
        })
      end
    end
  end
end

function drawMissoes()
  local x, y = 20, 110
  local w, h = 260, 100
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  love.graphics.setColor(1, 1, 1, 0.10)
  love.graphics.rectangle("line", x, y, w, h, 6, 6)
  setFonte("pequena")
  love.graphics.setColor(1, 0.9, 0.5)
  love.graphics.print("MISSOES", x + 10, y + 6)
  for i, m in ipairs(MISSOES_ATIVAS) do
    local ly = y + 24 + (i-1) * 22
    if m.completa then love.graphics.setColor(0.5, 1, 0.5)
    else love.graphics.setColor(0.85, 0.9, 0.95) end
    local txt = m.def.txt .. " (" .. math.min(m.progresso, m.def.alvo)
              .. "/" .. m.def.alvo .. ")"
    love.graphics.print(txt, x + 10, ly)
  end
  love.graphics.setColor(1, 1, 1)
end

function desenharBotoesHUD()
  local B = BOTOES_HUD
  -- PAUSE
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.circle("fill", B.pause.x, B.pause.y, B.pause.r)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.circle("line", B.pause.x, B.pause.y, B.pause.r)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", B.pause.x - 6, B.pause.y - 8, 4, 16)
  love.graphics.rectangle("fill", B.pause.x + 2, B.pause.y - 8, 4, 16)

  -- AUTO
  local corAuto = autoAtaque and {0.25,0.55,0.30} or {0.35,0.35,0.40}
  love.graphics.setColor(corAuto)
  love.graphics.circle("fill", B.auto.x, B.auto.y, B.auto.r)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.circle("line", B.auto.x, B.auto.y, B.auto.r)
  setFonte("pequena")
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("AUTO", B.auto.x - B.auto.r, B.auto.y - 6, B.auto.r*2, "center")

  -- EVO
  love.graphics.setColor(0.20, 0.45, 0.70)
  love.graphics.circle("fill", B.evo.x, B.evo.y, B.evo.r)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.circle("line", B.evo.x, B.evo.y, B.evo.r)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("EVO", B.evo.x - B.evo.r, B.evo.y - 6, B.evo.r*2, "center")

  -- DASH
  local corDash = dashCd > 0 and {0.30,0.30,0.35} or {0.25,0.55,0.85}
  love.graphics.setColor(corDash)
  love.graphics.circle("fill", B.dash.x, B.dash.y, B.dash.r)
  love.graphics.setColor(1, 1, 1, 0.6)
  love.graphics.circle("line", B.dash.x, B.dash.y, B.dash.r)
  love.graphics.setColor(1, 1, 1)
  setFonte("normal")
  if dashCd > 0 then
    love.graphics.printf(string.format("%.1f", dashCd),
      B.dash.x - B.dash.r, B.dash.y - 8, B.dash.r*2, "center")
  else
    love.graphics.printf("DASH", B.dash.x - B.dash.r, B.dash.y - 8, B.dash.r*2, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

-- ── MENU EVO (draw) ─────────────────────────────────────
function totalPaginas2(total, porPag)
  return math.max(1, math.ceil(total / porPag))
end

function desenharPaginacao2(pagina, total, prefix)
  local bw, bh = 90, 34
  local y = VH - 46
  local cx = VW/2
  desenharBotao(cx - 180, y, bw, bh, "<<", MENU_EVO.hover == prefix.."prev")
  setFonte("normal")
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(pagina .. " / " .. total, cx - 70, y + 8, 140, "center")
  desenharBotao(cx + 90, y, bw, bh, ">>", MENU_EVO.hover == prefix.."next")
end

function drawMenuEVO()
  love.graphics.setColor(0, 0, 0, 0.80)
  love.graphics.rectangle("fill", 0, 0, VW, VH)

  setFonte("grande")
  love.graphics.setColor(0.7, 0.9, 1)
  love.graphics.printf("EVOLUCAO", 0, 20, VW, "center")

  -- preview
  if player then
    local px, py = VW - 110, 60
    love.graphics.setColor(0.10, 0.14, 0.20, 0.9)
    love.graphics.rectangle("fill", px - 50, py - 50, 100, 100, 8, 8)
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.rectangle("line", px - 50, py - 50, 100, 100, 8, 8)
    -- desenha uma cópia fake do player no preview
local fake = {
  x = px, y = py,
  birth = player.birth,
  parts = player.parts,
  mutacoes = player.mutacoes,
  iframes = 0,
  tPulso = player.tPulso or 0,
  size = 22,
  ultimaDirX = 1, ultimaDirY = 0,
}
desenharPlayer(fake, 0, 0)
    setFonte("pequena")
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Preview", px - 50, py + 54, 100, "center")
  end

  local bw, bh = 200, 40
  local y0 = 80
  local cx = VW/2
  local up = MENU_EVO.aba == "upgrades"
  desenharBotao(cx - bw - 8, y0, bw, bh, "UPGRADES",
    MENU_EVO.hover == "abaUp" or up, up and {0.25,0.45,0.65} or nil)
  desenharBotao(cx + 8, y0, bw, bh, "MUTACOES",
    MENU_EVO.hover == "abaMut" or not up, (not up) and {0.35,0.25,0.55} or nil)

  setFonte("normal")
  love.graphics.setColor(0.7, 0.9, 0.7)
  love.graphics.printf("DNA: " .. (SAVE.moedaDNA or 0),
    cx - 240, y0 + bh + 6, 240, "center")
  love.graphics.setColor(0.85, 0.7, 1)
  love.graphics.printf("DNA Raro: " .. (player and player.dnaRaro or 0),
    cx, y0 + bh + 6, 240, "center")

  local cols = 2
  local cw, ch = 320, 72
  local gapx, gapy = 16, 10
  local totalW = cols*cw + gapx
  local gx0 = VW/2 - totalW/2
  local gy0 = y0 + bh + 36

  local lista = up and PARTS or MUTATIONS
  local total = totalPaginas2(#lista, MENU_EVO.itensPorPagina)
  MENU_EVO.pagina = math.max(1, math.min(MENU_EVO.pagina, total))
  local start = (MENU_EVO.pagina - 1) * MENU_EVO.itensPorPagina

  for i = 1, MENU_EVO.itensPorPagina do
    local idx = start + i
    local item = lista[idx]
    if item then
      local col = (i-1) % cols
      local row = math.floor((i-1) / cols)
      local x = gx0 + col*(cw+gapx)
      local y = gy0 + row*(ch+gapy)

      local lv, custo, maxed
      if up then
        lv = player.parts[item.id] or 0
        custo = item.cost * (lv + 1)
        maxed = lv >= item.maxLv
      else
        lv = player.mutacoes[item.id] and 1 or 0
        custo = item.cost
        maxed = lv >= 1
      end

      local temDna = (up and (SAVE.moedaDNA or 0) >= custo)
                     or (not up and (player.dnaRaro or 0) >= custo)
      local podeComprar = not maxed and temDna

      local hover = MENU_EVO.hover == "item_" .. idx
      if maxed then love.graphics.setColor(0.15, 0.22, 0.15)
      elseif podeComprar and hover then love.graphics.setColor(0.30, 0.42, 0.35)
      elseif podeComprar then love.graphics.setColor(0.20, 0.28, 0.24)
      else love.graphics.setColor(0.18, 0.18, 0.22) end
      love.graphics.rectangle("fill", x, y, cw, ch, 6, 6)
      love.graphics.setColor(1, 1, 1, 0.12)
      love.graphics.rectangle("line", x, y, cw, ch, 6, 6)

      setFonte("normal")
      love.graphics.setColor(1, 1, 1)
      love.graphics.print(item.name, x + 12, y + 6)

      setFonte("pequena")
      love.graphics.setColor(0.75, 0.85, 0.95)
      if up then
        love.graphics.print(custo .. " DNA  (" .. lv .. "/" .. item.maxLv .. ")",
          x + 12, y + 28)
      else
        love.graphics.print(custo .. " DNA Raro  (" .. lv .. "/1)",
          x + 12, y + 28)
      end
      love.graphics.print(item.desc, x + 12, y + 48)

      if maxed then
        love.graphics.setColor(0.5, 1, 0.5)
        love.graphics.printf("MAX", x, y + 28, cw - 12, "right")
      end
    end
  end

  desenharPaginacao2(MENU_EVO.pagina, total, "evo_")
  desenharBotao(VW - 120, 20, 90, 34, "FECHAR",
    MENU_EVO.hover == "fechar", {0.5, 0.25, 0.25})
end

-- ── EFEITOS DE NÍVEL UP ─────────────────────────────────
function desenharNivelUp()
  local dt = love.timer.getDelta()

  -- 1) FLASH dourado
  if NIVEL_UP.flash > 0 then
    NIVEL_UP.flash = math.max(0, NIVEL_UP.flash - dt * 2.5)
    love.graphics.setColor(1, 0.85, 0.3, NIVEL_UP.flash * 0.35)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
  end

  -- 2) TEXTO "NÍVEL X!"
  if NIVEL_UP.texto then
    NIVEL_UP.texto.t = NIVEL_UP.texto.t + dt
    local t = NIVEL_UP.texto
    local pct = t.t / t.dur

    local alpha = 1.0
    if pct > 0.6 then alpha = 1 - (pct - 0.6) / 0.4 end
    if pct < 0.15 then alpha = pct / 0.15 end

    local escala = 1.0 + math.sin(math.min(pct, 0.5) * math.pi) * 0.3
    local yBase = VH * 0.4 - pct * 80

    love.graphics.push()
    love.graphics.translate(VW/2, yBase)
    love.graphics.scale(escala, escala)

    love.graphics.setColor(0, 0, 0, alpha * 0.6)
    setFonte("titulo")
    love.graphics.printf("NIVEL " .. t.nivel .. "!", -300, -30, 600, "center")

    love.graphics.setColor(1, 0.9, 0.4, alpha)
    love.graphics.printf("NIVEL " .. t.nivel .. "!", -300, -32, 600, "center")

    love.graphics.pop()

    if t.t >= t.dur then NIVEL_UP.texto = nil end
  end

  love.graphics.setColor(1, 1, 1)
end

-- ── MINIMAP ─────────────────────────────────────────────
function desenharMinimap()
  if not MINIMAP.ativo or not FASES.atual or not player then return end

  -- posiciona no canto inferior esquerdo (pra não competir com botões)
  local mx = 20
  local my = VH - MINIMAP.h - 20
  MINIMAP.x, MINIMAP.y = mx, my

  local f = FASES.atual
  local escala = MINIMAP.w / f.w

  -- fundo
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", mx - 2, my - 2, MINIMAP.w + 4, MINIMAP.h + 4, 6, 6)
  love.graphics.setColor(0.15, 0.22, 0.30, 0.8)
  love.graphics.rectangle("fill", mx, my, MINIMAP.w, MINIMAP.h, 4, 4)

  -- borda
  love.graphics.setColor(1, 1, 1, 0.25)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", mx, my, MINIMAP.w, MINIMAP.h, 4, 4)

  -- clipe pra não desenhar fora do minimap
  love.graphics.setScissor(mx, my, MINIMAP.w, MINIMAP.h)

  -- helper: converte coordenada do mundo pro minimap
  local function toMap(wx, wy)
    return mx + wx * escala, my + wy * escala
  end

  -- BAÚS (dourado)
  for _, b in ipairs(BAUIS) do
    if not b.aberto then
      local px, py = toMap(b.x, b.y)
      love.graphics.setColor(1, 0.85, 0.3)
      love.graphics.rectangle("fill", px - 2, py - 2, 4, 4)
    end
  end

  -- NPCs (só os agressivos aparecem — pra não poluir)
  for _, npc in ipairs(NPCS) do
    if npc.alive and npc.estado == ESTADO.AGRESSIVO then
      local px, py = toMap(npc.x, npc.y)
      love.graphics.setColor(1, 0.4, 0.3, 0.8)
      love.graphics.circle("fill", px, py, 2)
    end
  end

  -- BOSSES (estrelas vermelhas)
  for _, boss in ipairs(BOSSES_ATIVOS) do
    if boss.alive then
      local px, py = toMap(boss.x, boss.y)
      love.graphics.setColor(1, 0.2, 0.2)
      love.graphics.polygon("fill",
        px, py - 5,
        px + 5, py,
        px, py + 5,
        px - 5, py)
      -- anel pulsante
      love.graphics.setColor(1, 0.2, 0.2, 0.4)
      love.graphics.circle("line", px, py, 6 + math.sin(love.timer.getTime() * 5) * 2)
    end
  end

  -- ÁREA VISÍVEL (retângulo branco translúcido)
  love.graphics.setColor(1, 1, 1, 0.25)
  love.graphics.rectangle("line",
    mx + CAM.x * escala,
    my + CAM.y * escala,
    VW * escala,
    VH * escala)

  -- PLAYER (ponto branco piscando)
  local px, py = toMap(player.x, player.y)
  local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 6)
  love.graphics.setColor(1, 1, 1, pulse)
  love.graphics.circle("fill", px, py, 3.5)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.circle("line", px, py, 6)

  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1)
  love.graphics.setLineWidth(1)
end

-- ── INDICADOR DE BOSS OFF-SCREEN ────────────────────────
function desenharIndicadorBoss()
  if not player or not FASES.atual then return end

  local cfg = BOSS_ARROW
  local margem = cfg.margem

  -- Percorre bosses ativos
  for _, boss in ipairs(BOSSES_ATIVOS) do
    if boss.alive then
      -- posição do boss em coordenadas de tela
      local sx = boss.x - CAM.x
      local sy = boss.y - CAM.y

      -- verifica se está FORA da tela
      local foraX = sx < 0 or sx > VW
      local foraY = sy < 0 or sy > VH

      if foraX or foraY then
        -- posição do player (referência pra calcular direção)
        local px = player.x - CAM.x
        local py = player.y - CAM.y

        -- vetor do player até o boss
        local dx = sx - px
        local dy = sy - py
        local ang = math.atan2(dy, dx)

        -- projeta o ponto na borda da tela (com margem)
        local ex, ey = px, py
        -- avança até bater na borda
        local passoMax = 2000
        for _ = 1, 30 do
          ex = ex + math.cos(ang) * passoMax / 30
          ey = ey + math.sin(ang) * passoMax / 30
          if ex < margem or ex > VW - margem or
             ey < margem or ey > VH - margem then
            break
          end
        end

        -- clampa exatamente na margem
        ex = clamp(ex, margem, VW - margem)
        ey = clamp(ey, margem, VH - margem)

        -- cor: predador pisca mais rápido
        local cor = cfg.cor
        if boss.isPredador then cor = cfg.corPredador end

        local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 5)

        -- desenha seta apontando na direção do boss
        love.graphics.push()
        love.graphics.translate(ex, ey)
        love.graphics.rotate(ang)

        -- sombra
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.polygon("fill",
          cfg.tamanho * pulse, 0,
          -cfg.tamanho * 0.7, -cfg.tamanho * 0.7,
          -cfg.tamanho * 0.4, 0,
          -cfg.tamanho * 0.7, cfg.tamanho * 0.7)

        -- seta colorida
        love.graphics.setColor(cor[1], cor[2], cor[3], pulse)
        love.graphics.polygon("fill",
          cfg.tamanho * pulse * 0.9, 0,
          -cfg.tamanho * 0.6, -cfg.tamanho * 0.6,
          -cfg.tamanho * 0.35, 0,
          -cfg.tamanho * 0.6, cfg.tamanho * 0.6)

        -- brilho
        love.graphics.setColor(cor[1], cor[2], cor[3], pulse * 0.4)
        love.graphics.circle("fill", 0, 0, cfg.tamanho * 0.5 * pulse)

        love.graphics.pop()
      end
    end
  end

  love.graphics.setColor(1, 1, 1)
end

-- ── DESENHO DO AVISO DE BOSS ────────────────────────────
function desenharAvisoBoss()
  if not BOSS_WARN.ativo then return end

  local t = BOSS_WARN.t
  local pct = t / BOSS_WARN.dur

  -- 1) Borda piscando em vermelho
  local pulso = 0.5 + 0.5 * math.sin(t * 10)
  local alpha = 0.4 + pulso * 0.4

  -- faixas ao redor da tela
  local borda = 40
  love.graphics.setColor(BOSS_WARN.cor[1], BOSS_WARN.cor[2], BOSS_WARN.cor[3], alpha)
  love.graphics.rectangle("fill", 0, 0, VW, borda)
  love.graphics.rectangle("fill", 0, VH - borda, VW, borda)
  love.graphics.rectangle("fill", 0, 0, borda, VH)
  love.graphics.rectangle("fill", VW - borda, 0, borda, VH)

  -- 2) Overlay escuro leve
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", 0, 0, VW, VH)

  -- 3) Texto "!! ALERTA !!"
  local fade = 1
  if pct > 0.85 then fade = 1 - (pct - 0.85) / 0.15 end   -- fade final

  love.graphics.setColor(0, 0, 0, fade * 0.7)
  setFonte("titulo")
  love.graphics.printf("!! ALERTA !!", 0, VH/2 - 80, VW, "center")

  love.graphics.setColor(1, 0.2, 0.2, fade)
  love.graphics.printf("!! ALERTA !!", 0, VH/2 - 82, VW, "center")

  -- 4) Subtítulo com o nome
  love.graphics.setColor(1, 1, 1, fade)
  setFonte("media")
  love.graphics.printf(BOSS_WARN.nome .. " se aproxima...", 0, VH/2 + 10, VW, "center")

  -- 5) Barrinha de countdown embaixo
  local cw = 260
  local cx = VW/2 - cw/2
  local cy = VH/2 + 60
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", cx, cy, cw, 6, 3, 3)
  love.graphics.setColor(1, 0.3, 0.3, fade)
  love.graphics.rectangle("fill", cx, cy, cw * pct, 6, 3, 3)

  love.graphics.setColor(1, 1, 1)
end

-- ── DESENHO DA TRANSIÇÃO DE FASE ────────────────────────
function drawTransicao()
  local pct = TRANSICAO.t / TRANSICAO.dur

  -- 1) fundo escuro gradiente
  for i = 0, 20 do
    local t = i / 20
    local cor = 0.02 + t * 0.05
    love.graphics.setColor(cor, cor * 1.2, cor * 1.8)
    love.graphics.rectangle("fill", 0, i * VH/20, VW, VH/20 + 1)
  end

  -- 2) fade de entrada (0 - 0.3)
  local alpha = 1
  if pct < 0.15 then alpha = pct / 0.15 end
  -- 3) fade de saída (0.85 - 1.0)
  if pct > 0.85 then alpha = 1 - (pct - 0.85) / 0.15 end

  -- 4) nome da fase (grande)
  setFonte("titulo")
  love.graphics.setColor(0, 0, 0, alpha * 0.7)
  love.graphics.printf(TRANSICAO.nomeFase, 0, VH/2 - 70, VW, "center")
  love.graphics.setColor(0.5, 0.9, 1, alpha)
  love.graphics.printf(TRANSICAO.nomeFase, 0, VH/2 - 72, VW, "center")

  -- 5) subtítulo (nome da fase)
  setFonte("titulo")
  love.graphics.setColor(0.8, 0.95, 1, alpha)
  love.graphics.printf(TRANSICAO.subFase, 0, VH/2 - 10, VW, "center")

  -- 6) linha decorativa
  local lw = 400
  local lx = VW/2 - lw/2
  love.graphics.setColor(0.5, 0.9, 1, alpha * 0.6)
  love.graphics.setLineWidth(2)
  love.graphics.line(lx, VH/2 + 40, lx + lw, VH/2 + 40)
  love.graphics.setLineWidth(1)

  -- 7) dica de pular
  love.graphics.setColor(1, 1, 1, alpha * 0.5)
  setFonte("pequena")
  love.graphics.printf("Toque para continuar", 0, VH - 50, VW, "center")

  love.graphics.setColor(1, 1, 1)
end

function drawJogo()
  if not FASES.atual then return end
  local f = FASES.atual
  local offX, offY = camOffsetX(), camOffsetY()

  -- fundo base
  love.graphics.setColor(f.corFundo[1], f.corFundo[2], f.corFundo[3])
  love.graphics.rectangle("fill", 0, 0, VW, VH)

  -- grid (só o que está na tela)
  love.graphics.setColor(f.corGrid[1], f.corGrid[2], f.corGrid[3], 0.5)
  love.graphics.setLineWidth(1)
  local gx0 = math.floor(CAM.x / 60) * 60
  local gy0 = math.floor(CAM.y / 60) * 60
  local gx1 = CAM.x + VW + 60
  local gy1 = CAM.y + VH + 60
  for x = gx0, gx1, 60 do
    love.graphics.line(x + offX, 0, x + offX, VH)
  end
  for y = gy0, gy1, 60 do
    love.graphics.line(0, y + offY, VW, y + offY)
  end

  -- vinheta/clarão da água (leve)
  if f.key == "aquatic" then
    love.graphics.setColor(0.1, 0.25, 0.4, 0.10)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
  end

  -- comida
  for _, fd in ipairs(FOODS) do
    local fx, fy = fd.x + offX, fd.y + offY
    if fx > -30 and fx < VW+30 and fy > -30 and fy < VH+30 then
      fd.pulso = fd.pulso + 0.02
      local pulso = 1 + math.sin(fd.pulso) * 0.15
      if fd.tipo == "comum" then
        love.graphics.setColor(0.5, 0.95, 0.6, 0.9)
        love.graphics.circle("fill", fx, fy, 6 * pulso)
        love.graphics.setColor(0.8, 1, 0.8, 0.35)
        love.graphics.circle("fill", fx, fy, 10 * pulso)
      else
        love.graphics.setColor(1, 0.85, 0.3, 0.95)
        love.graphics.circle("fill", fx, fy, 8 * pulso)
        love.graphics.setColor(1, 0.95, 0.6, 0.30)
        love.graphics.circle("fill", fx, fy, 14 * pulso)
      end
    end
  end

  -- baús
  for _, b in ipairs(BAUIS) do
    if not b.aberto then
      local bx, by = b.x + offX, b.y + offY
      b.t = b.t + 0.016
      love.graphics.setColor(b.cor[1], b.cor[2], b.cor[3])
      love.graphics.rectangle("fill", bx - 12, by - 12, 24, 24, 4, 4)
      love.graphics.setColor(0, 0, 0, 0.4)
      love.graphics.rectangle("line", bx - 12, by - 12, 24, 24, 4, 4)
      -- brilho pulsante
      local pulse = 0.5 + 0.5 * math.sin(b.t * 3)
      love.graphics.setColor(b.cor[1], b.cor[2], b.cor[3], pulse * 0.35)
      love.graphics.circle("fill", bx, by, 20)
    end
  end

  -- drops
  for _, d in ipairs(DROPS) do
    local dx, dy = d.x + offX, d.y + offY
    if d.tipo == "xp" then
      love.graphics.setColor(0.6, 1, 0.7)
      love.graphics.circle("fill", dx, dy, 4)
    else
      love.graphics.setColor(0.75, 0.6, 1)
      love.graphics.polygon("fill",
        dx, dy - 6, dx + 5, dy, dx, dy + 6, dx - 5, dy)
    end
  end

  -- NPCs
  for _, npc in ipairs(NPCS) do
    if npc.alive then desenharCelula(npc, offX, offY, false) end
  end

  -- bosses
  for _, boss in ipairs(BOSSES_ATIVOS) do
    if boss.alive then desenharCelula(boss, offX, offY, true) end
  end

  -- balas
  for _, b in ipairs(BALAS) do
    love.graphics.setColor(b.cor[1], b.cor[2], b.cor[3], 0.9)
    love.graphics.circle("fill", b.x + offX, b.y + offY, b.size)
    love.graphics.setColor(b.cor[1], b.cor[2], b.cor[3], 0.25)
    love.graphics.circle("fill", b.x + offX, b.y + offY, b.size * 2)
  end

  -- player
if player and player.alive then
  desenharPlayer(player, offX, offY)
end

  -- partículas e texto flutuante
  drawParticulas()

  -- textos flutuantes precisam ser transladados pelo offset
  love.graphics.push()
  love.graphics.translate(offX, offY)
  drawTextoFlut()
  love.graphics.pop()

  -- efeitos de tela dos eventos
  desenharEfeitosEvento()

  -- HUD
  desenharHUD()
  drawMissoes()
  desenharBotoesHUD()
  drawToasts()
  desenharJoystickTouch()
  desenharBotaoHabilidade()
  desenharMinimap()
  desenharIndicadorBoss()
  desenharAvisoBoss()
  desenharNivelUp()
  if MENU_EVO.ativo then drawMenuEVO() end
end

-- ── 11.3 DESENHO DE UMA CÉLULA ───────────────────────────

-- ── DESENHO DO PLAYER (evolução visual por build) ────────
function desenharPlayer(c, offX, offY)
  local x, y = c.x + offX, c.y + offY
  local cor = c.birth.color
  local size = c.size
  c.tPulso = (c.tPulso or 0) + 0.016
  local pulso = 1 + math.sin(c.tPulso * 3) * 0.04
  size = size * pulso

  -- níveis das parts
  local lvMembrana = (c.parts and c.parts["membrana"]) or 0
  local lvFlagelo  = (c.parts and c.parts["flagelo"])  or 0
  local lvEspinho  = (c.parts and c.parts["espinho"])  or 0
  local lvCilio    = (c.parts and c.parts["cilio"])    or 0

  -- membrana aumenta o corpo
  local sizeTotal = size + lvMembrana * 2

  -- direção pra flagelo/espinhos
  local dirX, dirY = c.ultimaDirX or 1, c.ultimaDirY or 0
  local angDir = math.atan2(dirY, dirX)

  -- aura
  love.graphics.setColor(cor[1], cor[2], cor[3], 0.18)
  love.graphics.circle("fill", x, y, sizeTotal * 1.6)

  -- FLAGELO (cauda atrás)
  if lvFlagelo > 0 then
    local tamCauda = 18 + lvFlagelo * 6
    love.graphics.setColor(cor[1]*0.9, cor[2]*0.9, cor[3]*0.9, 0.85)
    love.graphics.setLineWidth(3 + lvFlagelo)
    local passos = 4
    local prevX = x - math.cos(angDir) * sizeTotal
    local prevY = y - math.sin(angDir) * sizeTotal
    for i = 1, passos do
      local t = i / passos
      local wig = math.sin(c.tPulso * 6 + i * 0.7) * (2 + lvFlagelo)
      local px = prevX - math.cos(angDir) * (tamCauda / passos)
                 + math.cos(angDir + math.pi/2) * wig
      local py = prevY - math.sin(angDir) * (tamCauda / passos)
                 + math.sin(angDir + math.pi/2) * wig
      love.graphics.line(prevX, prevY, px, py)
      prevX, prevY = px, py
    end
    love.graphics.setLineWidth(1)
  end

  -- CÍLIOS (ao redor, girando devagar)
  if lvCilio > 0 then
    love.graphics.setColor(cor[1]*0.7, cor[2]*0.8, cor[3]*0.7, 0.75)
    love.graphics.setLineWidth(2)
    local qtdCilios = 6 + lvCilio * 2
    for i = 1, qtdCilios do
      local a = (i / qtdCilios) * math.pi * 2 + c.tPulso * 1.5
      local cx1 = x + math.cos(a) * sizeTotal
      local cy1 = y + math.sin(a) * sizeTotal
      local len = 4 + lvCilio * 1.2
      local cx2 = x + math.cos(a) * (sizeTotal + len)
      local cy2 = y + math.sin(a) * (sizeTotal + len)
      love.graphics.line(cx1, cy1, cx2, cy2)
    end
    love.graphics.setLineWidth(1)
  end

  -- CORPO (cor muda conforme nascimento)
  local corBody = {cor[1], cor[2], cor[3]}
  if c.birth.id == "cristalina" then
    corBody = {math.min(cor[1]*1.15, 1), math.min(cor[2]*1.1, 1), math.min(cor[3]*1.15, 1)}
  elseif c.birth.id == "predatoria" then
    corBody = {math.min(cor[1]*1.2, 1), cor[2]*0.6, cor[3]*0.6}
  elseif c.birth.id == "fulgor" or c.birth.id == "eletrica" then
    corBody = {1, 1, cor[3]*0.7}
  end
  love.graphics.setColor(corBody[1], corBody[2], corBody[3])
  love.graphics.circle("fill", x, y, sizeTotal)

  -- ESPINHOS (pontas)
  if lvEspinho > 0 then
    local cE = cor[1]*1.2
    if cE > 1 then cE = 1 end
    love.graphics.setColor(cE, cor[2]*0.8, cor[3]*0.8)
    local qtdEspinhos = 4 + lvEspinho * 2
    for i = 1, qtdEspinhos do
      local a = (i / qtdEspinhos) * math.pi * 2
      local bx1 = x + math.cos(a) * sizeTotal
      local by1 = y + math.sin(a) * sizeTotal
      local bx2 = x + math.cos(a) * (sizeTotal + 6 + lvEspinho * 1.5)
      local by2 = y + math.sin(a) * (sizeTotal + 6 + lvEspinho * 1.5)
      local perpX = math.cos(a + math.pi/2) * (2 + lvEspinho * 0.5)
      local perpY = math.sin(a + math.pi/2) * (2 + lvEspinho * 0.5)
      love.graphics.polygon("fill",
        bx1 + perpX, by1 + perpY,
        bx1 - perpX, by1 - perpY,
        bx2, by2)
    end
  end

  -- PLACAS CRISTALINAS
  if c.birth.id == "cristalina" then
    love.graphics.setColor(1, 1, 1, 0.55)
    local qtdPlacas = 5
    for i = 1, qtdPlacas do
      local a = (i / qtdPlacas) * math.pi * 2 + 0.3
      local px = x + math.cos(a) * (sizeTotal * 0.7)
      local py = y + math.sin(a) * (sizeTotal * 0.7)
      love.graphics.polygon("fill",
        px, py - 4,
        px + 4, py,
        px, py + 4,
        px - 4, py)
    end
  end

  -- BORDA (pisca se iframes)
  if c.iframes and c.iframes > 0 then
    love.graphics.setColor(1, 1, 1, 0.4 + 0.4 * math.sin(c.iframes * 40))
  else
    love.graphics.setColor(1, 1, 1, 0.25)
  end
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x, y, sizeTotal)

  -- MEMBRANA (anel externo)
  if lvMembrana > 0 then
    love.graphics.setColor(cor[1]*0.9, cor[2]*0.9, cor[3]*0.9, 0.65)
    love.graphics.setLineWidth(2 + lvMembrana * 0.5)
    love.graphics.circle("line", x, y, sizeTotal + 3)
    love.graphics.setLineWidth(1)
  end

  -- FOTOSSÍNTESE (brilho verde no núcleo)
  if c.mutacoes and c.mutacoes["fotossintese"] then
    local pulsoF = 0.7 + 0.3 * math.sin(c.tPulso * 4)
    love.graphics.setColor(0.3, 1, 0.4, pulsoF * 0.35)
    love.graphics.circle("fill", x, y, sizeTotal * 0.75)
    love.graphics.setColor(0.4, 1, 0.5, pulsoF)
    love.graphics.circle("fill", x, y, sizeTotal * 0.4)
    love.graphics.setColor(0.9, 1, 0.9, 0.9)
    love.graphics.circle("fill", x, y, sizeTotal * 0.22)
  else
    -- núcleo padrão
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.circle("fill", x, y, sizeTotal * 0.35)
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setLineWidth(1)
end

function desenharCelula(c, offX, offY, isBoss, isPlayer)
  local x, y = c.x + offX, c.y + offY
  local cor = c.cor or (c.birth and c.birth.color) or {0.5, 0.9, 0.6}
  local size = c.size
  c.tPulso = (c.tPulso or 0) + 0.016
  local pulso = 1 + math.sin(c.tPulso * 3) * 0.04
  size = size * pulso

  -- sombra/aura
  love.graphics.setColor(cor[1], cor[2], cor[3], 0.18)
  love.graphics.circle("fill", x, y, size * 1.6)

  -- corpo
  love.graphics.setColor(cor[1], cor[2], cor[3])
  love.graphics.circle("fill", x, y, size)

  -- borda (se iframes piscando)
  if c.iframes and c.iframes > 0 then
    love.graphics.setColor(1, 1, 1, 0.4 + 0.4 * math.sin(c.iframes * 40))
  else
    love.graphics.setColor(1, 1, 1, 0.15)
  end
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x, y, size)

  -- núcleo
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.circle("fill", x, y, size * 0.35)

  -- flag de boss
  if isBoss then
    love.graphics.setColor(1, 0.4, 0.4, 0.7)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, size + 5)
    -- barra de HP
    local w = 80
    local hpPct = c.hp / c.hpMax
    local bx = x - w/2
    local by = y - size - 18
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", bx, by, w, 8, 3, 3)
    love.graphics.setColor(0.9, 0.3, 0.3)
    love.graphics.rectangle("fill", bx + 1, by + 1, (w-2) * hpPct, 6, 2, 2)
    love.graphics.setColor(1, 1, 1)
    setFonte("pequena")
    love.graphics.printf(c.bossDef and c.bossDef.name or "BOSS",
      bx, by - 16, w, "center")
  end

  -- marker de status (agressivo/cauteloso/etc.)
  if not isPlayer and c.traits then
    local offsetY = 0
    for _, t in ipairs(c.traits) do
      local corT = ({
        agressivo={1,0.5,0.4}, cauteloso={0.5,0.7,1},
        gregario={0.6,1,0.6},  solitario={0.7,0.6,1},
        tanque={0.9,0.7,0.3},  explosivo={1,0.6,0.3},
        curandeiro={0.4,1,0.7},
      })[t.id] or {1,1,1}
      love.graphics.setColor(corT[1], corT[2], corT[3], 0.9)
      love.graphics.circle("fill", x - size - 6, y - 8 + offsetY, 3)
      offsetY = offsetY + 7
    end
  end

  -- marca de análise
  if c.marcado and c.marcadoT and c.marcadoT > 0 then
    love.graphics.setColor(0.4, 0.8, 1, 0.7)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", x, y, size + 8)
  end

  if not isPlayer and c.estado and ESTADO_COR[c.estado] then
  local corE = ESTADO_COR[c.estado]
  if c.estado ~= ESTADO.PASSIVO then
    local ix = x + size + 6
    local iy = y - size - 4
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.circle("fill", ix, iy, 5)
    love.graphics.setColor(corE[1], corE[2], corE[3], 1)
    love.graphics.circle("fill", ix, iy, 3.5)
  end
end
if not isPlayer and player and c.size > player.size * 1.30 then
  love.graphics.setColor(1, 0.3, 0.3, 0.35)
  love.graphics.setLineWidth(1.5)
  love.graphics.circle("line", x, y, size + 4)
  love.graphics.setLineWidth(1)
end
  
  -- aviso de slash do predador (leque vermelho)
if isBoss and c.slashTelegraph then
  local tg = c.slashTelegraph
  local alpha = 0.25 + 0.25 * math.sin(love.timer.getTime() * 20)
  love.graphics.setColor(1, 0.2, 0.2, alpha)
  local x1 = x + math.cos(tg.ang - 0.6) * (c.size + 4)
  local y1 = y + math.sin(tg.ang - 0.6) * (c.size + 4)
  local x2 = x + math.cos(tg.ang - 0.6) * tg.range
  local y2 = y + math.sin(tg.ang - 0.6) * tg.range
  local x3 = x + math.cos(tg.ang + 0.6) * tg.range
  local y3 = y + math.sin(tg.ang + 0.6) * tg.range
  local x4 = x + math.cos(tg.ang + 0.6) * (c.size + 4)
  local y4 = y + math.sin(tg.ang + 0.6) * (c.size + 4)
  love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4)
  love.graphics.setColor(1, 0.3, 0.3, 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.polygon("line", x1, y1, x2, y2, x3, y3, x4, y4)
  love.graphics.setLineWidth(1)
end
  
  -- ═══ TELEGRAPH DE BOSS (V6) ═══
if isBoss and c.telegraph then
  local tg = c.telegraph
  local enrage = c.bossFase == 3
  local cor = enrage and TELEGRAPH.corEnrage or TELEGRAPH.cor

  -- pulso: fase 3 pulsa mais rápido
  local freq = enrage and 35 or 20
  local alpha = 0.3 + 0.3 * math.sin(love.timer.getTime() * freq)

  -- espessura: fase 3 fica mais fino
  local width = enrage and 2 or 4

  -- usa o ângulo FALSO se for feint, real se não for
  local angShow = tg.angFalso or tg.ang or 0

  if tg.tipo == "spike" then
    -- linhas divergentes
    love.graphics.setColor(cor[1], cor[2], cor[3], alpha)
    love.graphics.setLineWidth(width)
    for i = -2, 2 do
      local a = angShow + i * 0.18
      love.graphics.line(
        x + math.cos(a) * size, y + math.sin(a) * size,
        x + math.cos(a) * (size + 200),
        y + math.sin(a) * (size + 200))
    end
    love.graphics.setLineWidth(1)

  elseif tg.tipo == "burst_dash" or tg.tipo == "charge_summon" then
    -- trilha larga
    love.graphics.setColor(cor[1], cor[2], cor[3], alpha * 0.55)
    local w = size * 1.2
    local dist = 400
    local px  = x + math.cos(angShow + math.pi/2) * w
    local py  = y + math.sin(angShow + math.pi/2) * w
    local px2 = x + math.cos(angShow - math.pi/2) * w
    local py2 = y + math.sin(angShow - math.pi/2) * w
    love.graphics.polygon("fill",
      px, py,
      px + math.cos(angShow) * dist, py + math.sin(angShow) * dist,
      px2 + math.cos(angShow) * dist, py2 + math.sin(angShow) * dist,
      px2, py2)
    love.graphics.setColor(cor[1], cor[2], cor[3], alpha)
    love.graphics.setLineWidth(width)
    love.graphics.polygon("line",
      px, py,
      px + math.cos(angShow) * dist, py + math.sin(angShow) * dist,
      px2 + math.cos(angShow) * dist, py2 + math.sin(angShow) * dist,
      px2, py2)
    love.graphics.setLineWidth(1)

  elseif tg.tipo == "tentacles" then
    love.graphics.setColor(cor[1], cor[2], cor[3], alpha * 0.5)
    love.graphics.circle("fill", x, y, tg.raio or 140)
    love.graphics.setColor(cor[1], cor[2], cor[3], alpha)
    love.graphics.setLineWidth(width)
    love.graphics.circle("line", x, y, tg.raio or 140)
    love.graphics.setLineWidth(1)
  end
end
  
  love.graphics.setColor(1, 1, 1)
  love.graphics.setLineWidth(1)
end

-- ── 11.4 EFEITOS VISUAIS DOS EVENTOS ─────────────────────

function desenharEfeitosEvento()
  if temEvento("eclipse") then
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
  end
  if temEvento("nevoa") then
    love.graphics.setColor(0.7, 0.8, 0.9, 0.22)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
  end
  if temEvento("chuvadna") then
    local t = love.timer.getTime()
    for i = 1, 30 do
      local x = ((i * 97 + t * 120) % VW)
      local y = ((i * 53 + t * 220) % VH)
      love.graphics.setColor(0.75, 0.6, 1, 0.5)
      love.graphics.circle("fill", x, y, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- ── 11.5 HUD ────────────────────────────────────────────

function desenharHUD()
  if not player then return end

  -- barra de HP (canto sup. esquerdo)
  local x, y = 20, 20
  local w, h = 220, 20
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  local hpPct = player.hp / player.hpMax
  love.graphics.setColor(0.8, 0.2, 0.25)
  love.graphics.rectangle("fill", x + 2, y + 2, (w-4) * hpPct, h-4, 4, 4)
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.rectangle("line", x, y, w, h, 6, 6)

  setFonte("pequena")
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(string.format("HP %d / %d",
    math.ceil(player.hp), math.ceil(player.hpMax)),
    x + 8, y + 3, w - 16, "left")

  -- barra de XP (canto sup. esquerdo, abaixo do HP)
  y = y + h + 4
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", x, y, w, 12, 4, 4)
  local xpPct = player.xp / player.xpNext
  love.graphics.setColor(0.4, 0.8, 1.0)
  love.graphics.rectangle("fill", x + 2, y + 2, (w-4) * xpPct, 8, 3, 3)
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.rectangle("line", x, y, w, 12, 4, 4)

  -- Nível + DNA
  setFonte("normal")
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Nv " .. player.level, x, y + 22)
  love.graphics.setColor(0.85, 0.7, 1)
  love.graphics.print("DNA " .. (player.dnaRaro or 0), x + 90, y + 22)

  -- Kill streak
  if player.streak and player.streak > 0 then
    local txt = "STREAK x" .. player.streak
    setFonte("media")
    local cor = {1, 0.9, 0.4}
    if player.streak >= 20 then cor = {1, 0.5, 0.4} end
    if player.streak >= 10 then cor = {1, 0.7, 0.3} end
    love.graphics.setColor(cor[1], cor[2], cor[3], 0.9)
    love.graphics.printf(txt, 0, 120, VW, "center")
    if player.buffStreak then
      setFonte("pequena")
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.printf(string.format("%s +%.0f%%  %.1fs",
        player.buffStreak.stat:upper(),
        (player.buffStreak.mult - 1) * 100,
        player.buffStreak.t),
        0, 148, VW, "center")
    end
  end

  -- Nome do boss ativo + barra de HP grande
  if #BOSSES_ATIVOS > 0 then
    local b = BOSSES_ATIVOS[1]
    if b.bossDef then
      setFonte("media")
      love.graphics.setColor(1, 0.85, 0.85)
      love.graphics.printf(b.bossDef.name, 0, 24, VW, "center")
      local bw, bh = 460, 12
      local bx, by = VW/2 - bw/2, 52
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", bx, by, bw, bh, 4, 4)
      local pct = b.hp / b.hpMax
      love.graphics.setColor(0.85, 0.25, 0.3)
      love.graphics.rectangle("fill", bx + 1, by + 1, (bw-2)*pct, bh-2, 3, 3)
      -- marcas de fase
      love.graphics.setColor(1, 1, 1, 0.6)
      for _, th in ipairs(BAL.boss.phaseThresholds) do
        local px = bx + bw * (1 - th)
        love.graphics.line(px, by, px, by + bh)
      end
    end
  end

  -- Cronômetro + nome da fase
  if FASES.atual then
    setFonte("pequena")
    love.graphics.setColor(1, 1, 1, 0.7)
    local min = math.floor(FASES.atual.tempoDecorrido / 60)
    local sec = math.floor(FASES.atual.tempoDecorrido % 60)
    love.graphics.printf(FASES.atual.nome .. "  " ..
      string.format("%d:%02d", min, sec),
      VW - 200, 20, 180, "right")
  end

  -- Evento ativo
  local ev = EVENTOS_ATIVOS[1]
  if ev then
    setFonte("pequena")
    love.graphics.setColor(1, 0.9, 0.5, 0.9)
    love.graphics.printf("EVENTO: " .. ev.def.name, VW - 200, 44, 180, "right")
  end

  -- botão de pausa (topo direito)
  local bp = INPUT.botaoPausa
  love.graphics.setColor(1, 1, 1, 0.12)
  love.graphics.circle("fill", bp.x, bp.y, bp.r)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.circle("line", bp.x, bp.y, bp.r)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", bp.x - 6, bp.y - 8, 4, 16)
  love.graphics.rectangle("fill", bp.x + 2, bp.y - 8, 4, 16)

  love.graphics.setColor(1, 1, 1)
  love.graphics.setLineWidth(1)
end

-- ── 11.6 PAUSA ───────────────────────────────────────────

PAUSA = { aba = "principal" }

function pausaBotoes()
  local w, h = 260, 42
  local x = VW/2 - w/2
  local y0 = 220
  local gap = 12
  return {
    { id="voltar",   x=x, y=y0 + (h+gap)*0, w=w, h=h, txt="CONTINUAR" },
    { id="bestiario",x=x, y=y0 + (h+gap)*1, w=w, h=h, txt="BESTIARIO" },
    { id="stats",    x=x, y=y0 + (h+gap)*2, w=w, h=h, txt="ESTATISTICAS" },
    { id="opcoes",   x=x, y=y0 + (h+gap)*3, w=w, h=h, txt="OPCOES" },
    { id="salvar_sair", x=x, y=y0 + (h+gap)*4, w=w, h=h,
    txt="SALVAR E SAIR", cor={0.30,0.45,0.30} },
    
    }
end

function drawPausa()
  -- escurece o fundo
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, VW, VH)

  setFonte("grande")
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("PAUSA", 0, 80, VW, "center")

  if PAUSA.aba == "principal" then
    for _, b in ipairs(pausaBotoes()) do
      desenharBotao(b.x, b.y, b.w, b.h, b.txt, MENU.hover == b.id, b.cor)
    end
  else
    -- reaproveita menus internos
    if PAUSA.aba == "bestiario" then
      MENU.tela = "bestiario"
      desenharMenuBestiario()
    elseif PAUSA.aba == "stats" then
      MENU.tela = "stats"
      desenharMenuStats()
    elseif PAUSA.aba == "opcoes" then
      MENU.tela = "opcoes"
      desenharMenuOpcoes()
    end
    -- botão voltar pra pausa principal (canto)
    desenharBotao(VW - 140, VH - 58, 110, 36, "VOLTAR", MENU.hover == "p_voltar")
  end
  drawToasts()
end

function pausaClick(mx, my)
  if PAUSA.aba == "principal" then
    for _, b in ipairs(pausaBotoes()) do
      if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then
        if b.id == "voltar" then
          gameState = "jogando"
        elseif b.id == "salvar_sair" then
  saveWrite()
  table.insert(TOASTS, {
    txt = "Jogo salvo!", t=0, dur=2, color={0.5, 1, 0.6},
  })
  gameState = "menu"
  MENU.tela = "principal"
        else
          PAUSA.aba = b.id
          MENU.pagina = 1
        end
        return
      end
    end
  else
    -- navegação dos menus internos reaproveitados
    if PAUSA.aba == "bestiario" then
      if pontoEmRetangulo(mx, my, VW - 140, VH - 58, 110, 36) then
        PAUSA.aba = "principal"; return
      end
      clickMenuBestiario(mx, my)
    elseif PAUSA.aba == "stats" then
      if pontoEmRetangulo(mx, my, VW/2 - 60, VH - 56, 120, 38) then
        PAUSA.aba = "principal"; return
      end
      clickMenuStats(mx, my)
    elseif PAUSA.aba == "opcoes" then
      if pontoEmRetangulo(mx, my, VW - 140, VH - 58, 110, 36) then
        PAUSA.aba = "principal"; return
      end
      clickMenuOpcoes(mx, my)
    end
  end
end

-- hover da pausa + menus internos
function pausaMouseMove(mx, my)
  MENU.hover = nil
  if PAUSA.aba == "principal" then
    for _, b in ipairs(pausaBotoes()) do
      if pontoEmRetangulo(mx, my, b.x, b.y, b.w, b.h) then MENU.hover = b.id; return end
    end
  else
    if pontoEmRetangulo(mx, my, VW - 140, VH - 58, 110, 36) then
      MENU.hover = "p_voltar"; return
    end
    menuMouseMove(mx, my)
  end
end

-- ── 11.7 GAME OVER ───────────────────────────────────────

gameOverTimer = 0

function drawGameOver()
  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.rectangle("fill", 0, 0, VW, VH)

  local alpha = math.min(1, gameOverTimer / 1.2)
  love.graphics.setColor(1, 0.4, 0.4, alpha)
  setFonte("titulo")
  love.graphics.printf("VOCE MORREU", 0, 100, VW, "center")

  love.graphics.setColor(1, 1, 1, alpha)
  setFonte("media")
  love.graphics.printf("Nivel " .. (player and player.level or 1),
    0, 180, VW, "center")
  love.graphics.printf("Kills: " .. SAVE.stats.kills, 0, 215, VW, "center")
  love.graphics.printf("Bosses: " .. SAVE.stats.bossesKilled, 0, 245, VW, "center")

  desenharBotao(VW/2 - 220, 340, 200, 50, "TENTAR DE NOVO",
    MENU.hover == "go_retry", {0.25, 0.45, 0.30})
  desenharBotao(VW/2 + 20, 340, 200, 50, "MENU",
    MENU.hover == "go_menu", {0.35, 0.30, 0.40})
end

function gameOverClick(mx, my)
  if pontoEmRetangulo(mx, my, VW/2 - 220, 340, 200, 50) then
    startGame(MENU.birthSel or "natural")
    return
  end
  if pontoEmRetangulo(mx, my, VW/2 + 20, 340, 200, 50) then
    gameState = "menu"
    MENU.tela = "principal"
    return
  end
end

-- ── 11.8 CUTSCENE FINAL (Célula → Terrestre) ─────────────

CUTSCENE = {
  t        = 0,
  textos   = CUTSCENE_TERRESTRE.textos,
  dur      = CUTSCENE_TERRESTRE.dur_total,
  pulou    = false,
}

function cutsceneInit()
  CUTSCENE.t = 0
  CUTSCENE.pulou = false
  SAVE.runAtiva = nil
  unlockAchievement("vitoria")
  Music:setTema("menu")
end

function cutsceneUpdate(dt)
  CUTSCENE.t = CUTSCENE.t + dt
  if CUTSCENE.t >= CUTSCENE.dur or CUTSCENE.pulou then
    -- volta pro menu
    gameState = "menu"
    MENU.tela = "principal"
    saveWrite()
  end
end

function drawCutscene()
  local t = CUTSCENE.t
  local pct = math.min(1, t / CUTSCENE.dur)

  -- gradiente água → terra
  local ca = CUTSCENE_TERRESTRE.cor_agua
  local ct = CUTSCENE_TERRESTRE.cor_terra
  local r = lerp(ca[1], ct[1], pct)
  local g = lerp(ca[2], ct[2], pct)
  local b = lerp(ca[3], ct[3], pct)
  love.graphics.setColor(r, g, b)
  love.graphics.rectangle("fill", 0, 0, VW, VH)

  -- "sol" subindo
  local solY = VH - pct * 320
  love.graphics.setColor(1, 0.9, 0.5, 0.3 + pct * 0.4)
  love.graphics.circle("fill", VW/2, solY, 80)

  -- célula subindo (sai da água)
  local cellX = VW/2
  local cellY = VH * 0.65 - pct * VH * 0.35
  local cor = player and player.birth.color or {0.5, 0.9, 0.6}
  love.graphics.setColor(cor[1], cor[2], cor[3])
  love.graphics.circle("fill", cellX, cellY, 26)
  love.graphics.setColor(1, 1, 1, 0.4)
  love.graphics.circle("fill", cellX, cellY, 10)

  -- textos por tempo
  for _, txt in ipairs(CUTSCENE.textos) do
    if t >= txt.t and t < txt.t + 2.2 then
      local a = 1
      if t > txt.t + 1.6 then a = 1 - (t - txt.t - 1.6) / 0.6 end
      love.graphics.setColor(1, 1, 1, math.max(0, a))
      setFonte("media")
      love.graphics.printf(txt.txt, 0, VH - 130, VW, "center")
    end
  end

  -- dica de pular
  love.graphics.setColor(1, 1, 1, 0.4)
  setFonte("pequena")
  love.graphics.printf("Toque ou pressione ESPACO para pular", 0, VH - 30, VW, "center")
  love.graphics.setColor(1, 1, 1)
end

function cutsceneClick(mx, my)
  CUTSCENE.pulou = true
end

-- ── 11.9 LOOP DO LÖVE ────────────────────────────────────

function love.load()
 ajustarResolucaoVirtual()
 reposicionarBotoesHUD()
 
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.math.setRandomSeed(os.time())
  setFonte("normal")

  -- carrega save
  saveLoad()

  -- inicializa listas globais
  NPCS          = NPCS or {}
  BOSSES_ATIVOS = BOSSES_ATIVOS or {}
  BALAS         = BALAS or {}
  BAUIS         = BAUIS or {}
  DROPS         = DROPS or {}
  FOODS         = FOODS or {}
  EVENTOS_ATIVOS= EVENTOS_ATIVOS or {}
  PARTICULAS    = PARTICULAS or {}
  TEXTO_FLUT    = TEXTO_FLUT or {}
  TOASTS        = TOASTS or {}

  -- música
  Music:init()
  Music:setTema("menu")

  -- estado inicial
  gameState = "menu"
  MENU.tela = "principal"
  MENU.birthSel = "natural"

  autosaveTimer = 0
  
  menuBgInit()
end

function love.update(dt)
  dt = math.min(dt, DT_MAX)

  if gameState == "menu" then
    menuUpdate(dt)
  elseif gameState == "jogando" then
    atualizarInputDir()
    updateJogo(dt)
  elseif gameState == "pausa" then
    updateToasts(dt)
  elseif gameState == "gameover" then
    gameOverTimer = gameOverTimer + dt
    updateToasts(dt)
  elseif gameState == "cutscene" then
    cutsceneUpdate(dt)
  elseif gameState == "transicao" then
  updateTransicao(dt)  
  end
end

function love.draw()
  -- se estiver em pé, mostra a tela de girar
  if isPortrait() then
    desenharRotacaoNecessaria()
    return
  end

  pushVirtual()

  if gameState == "menu" then
    menuDraw()
  elseif gameState == "jogando" then
    drawJogo()
  elseif gameState == "pausa" then
    drawJogo()
    drawPausa()
  elseif gameState == "gameover" then
    drawJogo()
    drawGameOver()
  elseif gameState == "cutscene" then
    drawCutscene()
  elseif gameState == "transicao" then
  drawTransicao()  
  end

  popVirtual()
end

function love.mousemoved(mx, my)
  local vx, vy = screenToVirtual(mx, my)
  if gameState == "menu" then
    menuMouseMove(vx, vy)
  elseif gameState == "jogando" then
    INPUT.mouseMundo.x = vx - camOffsetX()
    INPUT.mouseMundo.y = vy - camOffsetY()
  elseif gameState == "pausa" then
    pausaMouseMove(vx, vy)
  elseif gameState == "gameover" then
    MENU.hover = nil
    if pontoEmRetangulo(vx, vy, VW/2 - 220, 340, 200, 50) then MENU.hover = "go_retry" end
    if pontoEmRetangulo(vx, vy, VW/2 + 20,  340, 200, 50) then MENU.hover = "go_menu"  end
  end
end

function love.resize(w, h)
    ajustarResolucaoVirtual()
    if menuBgInit then menuBgInit() end

pcall(function()
    love.window.setFullscreen(true, "desktop")
  end)
    
end

function love.quit()
  saveWrite()
end

