import { getSpecies } from "./catalog";
import type { Pet, Stats, StatKey } from "./types";

export const STAT_KEYS: StatKey[] = ["hp", "attack", "specialAttack", "defense", "specialDefense", "speed"];
export const STAT_LABELS: Record<StatKey, string> = { hp: "체력", attack: "공격", specialAttack: "특수공격", defense: "방어", specialDefense: "특수방어", speed: "스피드" };
export const emptyStats = (): Stats => ({ hp: 0, attack: 0, specialAttack: 0, defense: 0, specialDefense: 0, speed: 0 });
export const statTotal = (stats: Stats) => STAT_KEYS.reduce((sum, key) => sum + stats[key], 0);

// Derived from level: old pets receive their points and repeated evolution cannot mint extras.
export function earnedStatPoints(level: number) {
  if (!Number.isInteger(level) || level < 1 || level > 30) throw new Error("잘못된 펫 레벨입니다.");
  return (level - 1) * 3 + (level >= 10 ? 7 : 0);
}
export const statLimit = (level: number) => Math.floor(earnedStatPoints(level) * 2 / 5);
export function validAllocation(value: unknown, level: number): value is Stats {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const stats = value as Stats;
  return Object.keys(stats).length === STAT_KEYS.length && STAT_KEYS.every(key =>
    Object.hasOwn(stats, key) && Number.isSafeInteger(stats[key]) && stats[key] >= 0 && stats[key] <= statLimit(level)
  ) && statTotal(stats) <= earnedStatPoints(level);
}
export function petStats(pet: Pet): Stats {
  const base = getSpecies(pet.speciesId)?.baseStats;
  if (!base) throw new Error("등록되지 않은 펫 종입니다.");
  const allocation = pet.statAllocation ?? emptyStats();
  return Object.fromEntries(STAT_KEYS.map(key => [key, base[key] + allocation[key]])) as Stats;
}
