import { SPECIES_SKILLS, type PetType } from "./skills";
import type { Pet } from "./types";

export const SPECIES = [
  { id: "seedfox", baseStats: { hp: 22, attack: 20, specialAttack: 23, defense: 20, specialDefense: 20, speed: 15 }, name: "새싹이", speciesName: "새싹이 계열", forms: ["새싹이", "잎새랑", "수호림"], type: "풀", types: [["풀"], ["풀"], ["풀", "땅"]], color: "#4f8d52", description: "작은 씨앗에 담긴 커다란 가능성. 다정한 숲의 친구.", legacySkills: ["씨앗 찌르기", "덩굴 방패", "숲의 맥박"], skills: SPECIES_SKILLS.seedfox.map(s => s.name), effects: SPECIES_SKILLS.seedfox.map(s => s.description) },
  { id: "bubblepenguin", baseStats: { hp: 24, attack: 14, specialAttack: 26, defense: 18, specialDefense: 24, speed: 14 }, name: "방울핀", speciesName: "방울핀 계열", forms: ["방울핀", "물결핀", "피오레"], type: "물", types: [["물"], ["물", "비행"], ["물", "비행"]], color: "#4199ba", description: "물방울처럼 맑고 호기심 많은 친구. 차곡차곡 자라는 힘.", legacySkills: ["물방울포", "샘물 막", "조류 파동"], skills: SPECIES_SKILLS.bubblepenguin.map(s => s.name), effects: SPECIES_SKILLS.bubblepenguin.map(s => s.description) },
  { id: "embersalamander", baseStats: { hp: 20, attack: 27, specialAttack: 16, defense: 17, specialDefense: 15, speed: 25 }, name: "불꼬리", speciesName: "불꼬리 계열", forms: ["불꼬리", "홍염랑", "부랑"], type: "불", types: [["불"], ["불"], ["불"]], color: "#d77b50", description: "따뜻한 불씨를 품은 씩씩한 친구. 열정만큼 쑥쑥 성장해요.", legacySkills: ["불씨 꼬리", "온기 장막", "해불 폭발"], skills: SPECIES_SKILLS.embersalamander.map(s => s.name), effects: SPECIES_SKILLS.embersalamander.map(s => s.description) },
  { id: "kitesquirrel", baseStats: { hp: 16, attack: 19, specialAttack: 20, defense: 16, specialDefense: 20, speed: 29 }, name: "솔비", speciesName: "솔비 계열", forms: ["솔비", "풍다람", "솔바람"], type: "비행", types: [["비행"], ["비행"], ["비행"]], color: "#669c92", description: "산들바람을 타고 새로운 하루로. 가볍고 날렵한 모험가.", legacySkills: ["산들 베기", "순풍 질주", "구름 낙하"], skills: SPECIES_SKILLS.kitesquirrel.map(s => s.name), effects: SPECIES_SKILLS.kitesquirrel.map(s => s.description) },
  { id: "pebblemole", baseStats: { hp: 28, attack: 24, specialAttack: 12, defense: 28, specialDefense: 18, speed: 10 }, name: "조약콩", speciesName: "조약콩 계열", forms: ["조약콩", "바위굴", "맥"], type: "땅", types: [["땅"], ["땅"], ["땅"]], color: "#a78c68", description: "묵묵히 땅을 다지는 든든한 친구. 함께라면 걱정 없어요.", legacySkills: ["자갈 던지기", "흙벽", "산등 충격"], skills: SPECIES_SKILLS.pebblemole.map(s => s.name), effects: SPECIES_SKILLS.pebblemole.map(s => s.description) },
  { id: "glowmoth", baseStats: { hp: 16, attack: 12, specialAttack: 29, defense: 14, specialDefense: 25, speed: 24 }, name: "반디솜", speciesName: "반디솜 계열", forms: ["반디솜", "빛나래", "휘여명"], type: "빛", types: [["빛", "비행"], ["빛", "비행"], ["빛", "비행"]], color: "#bd9c42", description: "은은한 빛으로 곁을 밝혀요. 작은 날갯짓 속 특별한 힘.", legacySkills: ["새벽 가루", "등불 보호", "황금 광선"], skills: SPECIES_SKILLS.glowmoth.map(s => s.name), effects: SPECIES_SKILLS.glowmoth.map(s => s.description) },
  { id: "mossmushroom", baseStats: { hp: 26, attack: 14, specialAttack: 22, defense: 22, specialDefense: 26, speed: 10 }, name: "포슬이", speciesName: "포슬이 계열", forms: ["포슬이", "이끼둥", "고목령"], type: "풀", types: [["풀", "땅"], ["풀", "땅"], ["풀", "땅"]], color: "#4f8d52", description: "폭신한 버섯 모자 아래 다정한 마음. 천천히 숲을 지키는 친구로 자라요.", legacySkills: ["포자 톡톡", "이끼 망토", "고목의 포효"], skills: SPECIES_SKILLS.mossmushroom.map(s => s.name), effects: SPECIES_SKILLS.mossmushroom.map(s => s.description) },
  { id: "tidalray", baseStats: { hp: 22, attack: 12, specialAttack: 25, defense: 16, specialDefense: 21, speed: 24 }, name: "납작이", speciesName: "납작이 계열", forms: ["납작이", "너울랑", "해울"], type: "물", types: [["물"], ["물"], ["물", "빛"]], color: "#4199ba", description: "너울을 타고 둥실 헤엄치는 친구. 넓은 지느러미로 바다를 품어요.", legacySkills: ["물결 찰싹", "너울 장막", "해류 날개"], skills: SPECIES_SKILLS.tidalray.map(s => s.name), effects: SPECIES_SKILLS.tidalray.map(s => s.description) },
  { id: "kilncrab", baseStats: { hp: 20, attack: 29, specialAttack: 11, defense: 27, specialDefense: 13, speed: 20 }, name: "딱불이", speciesName: "딱불이 계열", forms: ["딱불이", "숯집게", "용암각"], type: "불", types: [["불"], ["불"], ["불", "땅"]], color: "#d77b50", description: "작은 집게에 따뜻한 불씨를 꼭 쥐었어요. 단단한 등껍질 속 용감한 마음.", legacySkills: ["불똥 집게", "숯불 갑옷", "용암 집게"], skills: SPECIES_SKILLS.kilncrab.map(s => s.name), effects: SPECIES_SKILLS.kilncrab.map(s => s.description) },
  { id: "reedstork", baseStats: { hp: 18, attack: 24, specialAttack: 18, defense: 18, specialDefense: 16, speed: 26 }, name: "삐죽이", speciesName: "삐죽이 계열", forms: ["삐죽이", "휘바람", "창공루"], type: "비행", types: [["비행"], ["비행"], ["비행", "빛"]], color: "#669c92", description: "커다란 부리와 사뿐한 발걸음. 날개를 펼치면 하늘도 든든한 놀이터예요.", legacySkills: ["부리 돌풍", "깃털 활공", "창공 가르기"], skills: SPECIES_SKILLS.reedstork.map(s => s.name), effects: SPECIES_SKILLS.reedstork.map(s => s.description) },
  { id: "claygolem", baseStats: { hp: 28, attack: 26, specialAttack: 12, defense: 25, specialDefense: 19, speed: 10 }, name: "흙몽이", speciesName: "흙몽이 계열", forms: ["흙몽이", "옹기둥", "태산옹"], type: "땅", types: [["땅"], ["땅", "불"], ["땅", "불"]], color: "#a78c68", description: "동그란 흙 몸에 새겨진 순한 미소. 차곡차곡 쌓인 힘으로 친구를 지켜요.", legacySkills: ["흙손 콩", "옹기 방벽", "태산 주먹"], skills: SPECIES_SKILLS.claygolem.map(s => s.name), effects: SPECIES_SKILLS.claygolem.map(s => s.description) },
  { id: "prismtortoise", baseStats: { hp: 26, attack: 10, specialAttack: 24, defense: 24, specialDefense: 28, speed: 8 }, name: "반짝이", speciesName: "반짝이 계열", forms: ["반짝이", "수정갑", "휘광룡"], type: "빛", types: [["빛"], ["빛"], ["빛", "땅"]], color: "#bd9c42", description: "반짝이는 수정집을 등에 멘 친구. 느려도 씩씩하게 빛나는 길을 걸어요.", legacySkills: ["빛방울", "수정 방패", "휘광 파동"], skills: SPECIES_SKILLS.prismtortoise.map(s => s.name), effects: SPECIES_SKILLS.prismtortoise.map(s => s.description) },
] as const;
export type Item = { sku: string; name: string; kind: "food" | "ticket" | "potion" | "skill"; description: string; image: string; xp?: number; speciesId?: string; stage?: number };
export const ITEMS: Item[] = [
  { sku: "food-s", name: "별빛 한입", kind: "food", description: "경험치 +30", xp: 30, image: "/assets/items/food-s.webp" },
  { sku: "food-m", name: "숲속 도시락", kind: "food", description: "경험치 +90", xp: 90, image: "/assets/items/food-m.webp" },
  { sku: "food-l", name: "무지개 만찬", kind: "food", description: "경험치 +240", xp: 240, image: "/assets/items/food-l.webp" },
  { sku: "pet-choice-ticket", name: "새 친구 초대권", kind: "ticket", description: "새로운 친구 한 마리 만나기", image: "/assets/items/pet-choice-ticket.webp" },
];
export const getSpecies = (id: string) => SPECIES.find(s => s.id === id);
export const evolutionName = (speciesId: string, stage: number) => getSpecies(speciesId)?.forms[stage - 1] ?? "펫";
// Teacher-added shop items arrive with the server state; built-in items stay in ITEMS.
export type ShopProduct = { sku: string; name: string; description: string; kind: string; xp?: number | null; image?: string | null; archived?: boolean };
const extraItems = new Map<string, Item>(), productImages = new Map<string, string>(), archivedSkus = new Set<string>();
export function registerProducts(products: ShopProduct[] | undefined) {
  for (const p of products ?? []) {
    if (p.image) productImages.set(p.sku, p.image);
    if (p.archived) archivedSkus.add(p.sku); else archivedSkus.delete(p.sku);
    if (p.kind === "food" && p.xp && !ITEMS.some(i => i.sku === p.sku)) extraItems.set(p.sku, { sku: p.sku, name: p.name, kind: "food", description: p.description, xp: p.xp, image: p.image ?? "" });
  }
}
export const allItems = () => [...ITEMS, ...extraItems.values()];
export const getItem = (sku: string) => ITEMS.find(i => i.sku === sku) ?? extraItems.get(sku);
export const imageFor = (sku: string) => productImages.get(sku) ?? ITEMS.find(i => i.sku === sku)?.image;
export const isArchived = (sku: string) => archivedSkus.has(sku);
export const stageForLevel = (level: number) => level >= 20 ? 3 : level >= 10 ? 2 : 1;
export const nextLevelXp = (level: number) => level >= 30 ? 0 : 40 + (level - 1) * 10;
export function addExperience(level: number, xp: number, amount: number) {
  if (![level, xp, amount].every(Number.isInteger) || level < 1 || level > 30 || xp < 0 || amount < 0) throw new Error("잘못된 경험치 값입니다.");
  xp += amount;
  while (level < 30 && xp >= nextLevelXp(level)) { xp -= nextLevelXp(level); level++; }
  return { level, xp: level === 30 ? 0 : xp, stage: stageForLevel(level) };
}

export function petTypes(speciesId: string, stage: number): readonly PetType[] {
  return getSpecies(speciesId)?.types[Math.max(0, Math.min(2, stage - 1))] ?? [];
}
// Resolve old saved names without a destructive database migration.
export function learnedSkills(pet: Pet): string[] {
  const species = getSpecies(pet.speciesId);
  if (!species) return [];
  return [...new Set([...pet.skills.map(name => {
    const index = (species.legacySkills as readonly string[]).indexOf(name);
    return index < 0 ? name : species.skills[index];
  }), ...species.skills.slice(0, stageForLevel(pet.level))])];
}
