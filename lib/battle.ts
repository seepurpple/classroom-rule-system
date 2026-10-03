import { learnedSkills, petTypes } from "./catalog";
import { petStats } from "./stats";
import { PET_TYPES, SPECIES_SKILLS, type PetType, type RankStat, type Skill } from "./skills";
import type { Pet, Stats } from "./types";

// Rows attack, columns defend: grass, water, fire, flying, ground, light.
export const TYPE_CHART: Record<PetType, readonly number[]> = {
  풀: [0.5, 2, 0.5, 0.5, 2, 1],
  물: [0.5, 0.5, 2, 1, 2, 1],
  불: [2, 0.5, 0.5, 1, 1, 2],
  비행: [2, 1, 1, 1, 1, 0.5],
  땅: [0.5, 1, 2, 0.5, 1, 2],
  빛: [1, 2, 0.5, 2, 0.5, 0.5],
};
export const RANK_STATS: RankStat[] = ["attack", "specialAttack", "defense", "specialDefense", "speed"];
export const rankMultiplier = (rank: number) => [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4.5][Math.max(-4, Math.min(4, rank)) + 4];
export const typeMultiplier = (attack: PetType, defense: readonly PetType[]) => defense.reduce((value, type) => value * TYPE_CHART[attack][PET_TYPES.indexOf(type)], 1);
const round = (value: number) => Math.round(value * 10000) / 10000;
type Random = () => number;
export type Fighter = {
  id: string; types: readonly PetType[]; stats: Stats; hp: number; maxHp: number;
  ranks: Record<RankStat, number>; skills: Skill[]; previousSkill?: string;
  recharge: boolean; guard: boolean; reflect: boolean; dot?: { turns: number; damage: number };
};
export function createFighter(pet: Pet): Fighter {
  const stats = petStats(pet), learned = learnedSkills(pet);
  return { id: pet.id, types: petTypes(pet.speciesId, pet.stage), stats, hp: stats.hp * 3, maxHp: stats.hp * 3,
    ranks: { attack: 0, specialAttack: 0, defense: 0, specialDefense: 0, speed: 0 },
    skills: (SPECIES_SKILLS[pet.speciesId] ?? []).filter(skill => learned.includes(skill.name)),
    recharge: false, guard: false, reflect: false };
}
export function changeRanks(fighter: Fighter, changes: Partial<Record<RankStat, number>>) {
  for (const key of RANK_STATS) fighter.ranks[key] = Math.max(-4, Math.min(4, fighter.ranks[key] + (changes[key] ?? 0)));
}
export function calculateDamage(attacker: Fighter, defender: Fighter, skill: Skill, power: number, random: Random = Math.random) {
  if (skill.category === "변화기") return { damage: 0, critical: false, absoluteDefense: false, attack: 0, defense: 0 };
  const attackKey = skill.category === "공격" ? "attack" : "specialAttack";
  const defenseKey = skill.category === "공격" ? "defense" : "specialDefense";
  const critical = random() < (skill.criticalChance ?? 0.3);
  const variance = critical ? 1.2 : 0.8 + random() * 0.4;
  const absoluteDefense = !skill.ignoreAbsoluteDefense && random() < (defender.guard ? 0.6 : 0.15);
  const attack = attacker.stats[attackKey] * rankMultiplier(attacker.ranks[attackKey]) * power / 100
    * (skill.ignoreType ? 1 : typeMultiplier(skill.type, defender.types))
    * (attacker.types.includes(skill.type) ? 1.5 : 1) * variance * (critical ? 2 : 1);
  const defense = defender.stats[defenseKey] * rankMultiplier(defender.ranks[defenseKey]) * (absoluteDefense ? 2 : 1);
  return { damage: round(Math.max(0, attack - defense)), critical, absoluteDefense, attack: round(attack), defense: round(defense) };
}
function hurt(fighter: Fighter, damage: number) {
  const actual = Math.min(fighter.hp, damage);
  fighter.hp = round(fighter.hp - actual);
  return actual;
}
function heal(fighter: Fighter, amount: number) {
  if (fighter.hp > 0) fighter.hp = round(Math.min(fighter.maxHp, fighter.hp + amount));
}
export type BattleEvent = { actor: string; skill?: string; kind: "hit" | "miss" | "failed" | "recharge" | "status" | "dot" | "recoil" | "switch"; target?: string; damage?: number; critical?: boolean; absoluteDefense?: boolean; reflected?: boolean };
function executeSkill(actor: Fighter, target: Fighter, skill: Skill, random: Random, events: BattleEvent[]) {
  const event = { actor: actor.id, skill: skill.name };
  if (actor.recharge) {
    actor.recharge = false;
    actor.previousSkill = undefined;
    events.push({ ...event, kind: "recharge" });
    return;
  }
  const consecutive = actor.previousSkill === skill.name;
  actor.previousSkill = skill.name;
  if (skill.noConsecutive && consecutive) {
    events.push({ ...event, kind: "failed" });
    return;
  }
  let connected = false, totalDamage = 0, guarded = false;
  for (let hit = 0; hit < Math.max(1, skill.powers.length); hit++) {
    if (actor.hp <= 0 || target.hp <= 0) break;
    if (random() * 100 >= skill.accuracy[hit]) {
      events.push({ ...event, kind: "miss" });
      if (skill.missRecoil) events.push({ ...event, kind: "recoil", target: actor.id, damage: hurt(actor, skill.missRecoil) });
      break;
    }
    connected = true;
    if (skill.category === "변화기") { events.push({ ...event, kind: "status" }); break; }
    const result = calculateDamage(actor, target, skill, skill.powers[hit], random);
    guarded ||= result.absoluteDefense;
    const damage = hurt(target.reflect ? actor : target, result.damage);
    if (!target.reflect) totalDamage += damage;
    events.push({ ...event, kind: "hit", target: target.reflect ? actor.id : target.id, damage, critical: result.critical, absoluteDefense: result.absoluteDefense, reflected: target.reflect });
    if (target.guard && result.absoluteDefense) changeRanks(actor, { speed: -2 });
  }
  if (!connected) return;
  if (skill.drain) heal(actor, totalDamage * skill.drain);
  if (skill.heal) heal(actor, skill.heal);
  if (skill.healWithoutGuard && !guarded) heal(actor, skill.healWithoutGuard);
  if ((skill.selfRanks || skill.targetRanks) && (skill.rankChance === undefined || random() < skill.rankChance)) {
    if (skill.selfRanks) changeRanks(actor, skill.selfRanks);
    if (skill.targetRanks) changeRanks(target, skill.targetRanks);
  }
  if (skill.clearBoosts) for (const key of RANK_STATS) target.ranks[key] = Math.min(0, target.ranks[key]);
  if (skill.guard) actor.guard = true;
  if (skill.reflect) actor.reflect = true;
  if (skill.dot && target.hp > 0) target.dot = { ...skill.dot };
  if (skill.recharge) actor.recharge = true;
  if (skill.recoilPower && actor.hp > 0) {
    const recoil = calculateDamage(actor, actor, skill, skill.recoilPower, random);
    events.push({ ...event, kind: "recoil", target: actor.id, damage: hurt(actor, recoil.damage) });
  }
}
export type TurnChoice = string | { switchTo: Fighter };

// Pure turn resolution. No permanent pet stats or farm state are mutated.
export function resolveTurn(fighters: readonly [Fighter, Fighter], choices: readonly [TurnChoice, TurnChoice], random: Random = Math.random) {
  const next = structuredClone(fighters) as [Fighter, Fighter];
  if (next.some(f => f.hp <= 0)) throw new Error("이미 종료된 전투입니다.");
  const skills = next.map((fighter, i) => {
    const choice = choices[i];
    if (typeof choice !== "string") return null;
    const skill = fighter.skills.find(s => s.name === choice);
    if (!skill) throw new Error("배우지 않은 기술입니다.");
    return skill;
  });
  for (const fighter of next) { fighter.guard = false; fighter.reflect = false; }
  const priority = next.map((fighter, i) => !skills[i] ? 2 : fighter.recharge ? 0 : skills[i]!.priority ?? 0);
  const speed = next.map(fighter => fighter.stats.speed * rankMultiplier(fighter.ranks.speed));
  const difference = priority[0] - priority[1] || speed[0] - speed[1];
  const first = difference === 0 ? (random() < 0.5 ? 0 : 1) : difference > 0 ? 0 : 1;
  const events: BattleEvent[] = [];
  for (const i of [first, 1 - first]) {
    if (next.some(f => f.hp <= 0)) break;
    const choice = choices[i];
    if (typeof choice !== "string") {
      if (choice.switchTo.hp <= 0 || choice.switchTo.id === next[i].id) throw new Error("교체할 펫을 확인해 주세요.");
      next[i] = structuredClone(choice.switchTo);
      events.push({ actor: next[i].id, kind: "switch" });
    } else executeSkill(next[i], next[1 - i], skills[i]!, random, events);
  }
  // End-of-turn damage is simultaneous, and stops once direct damage ends battle.
  if (next.every(f => f.hp > 0)) for (const fighter of next) {
    if (fighter.dot) {
      events.push({ actor: fighter.id, target: fighter.id, kind: "dot", damage: hurt(fighter, fighter.dot.damage) });
      if (--fighter.dot.turns === 0) delete fighter.dot;
    }
  }
  for (const fighter of next) { fighter.guard = false; fighter.reflect = false; }
  const winner = next.every(f => f.hp <= 0) ? "draw" : next[0].hp <= 0 ? next[1].id : next[1].hp <= 0 ? next[0].id : null;
  return { fighters: next, events, winner };
}
