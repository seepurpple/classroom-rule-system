export const SPECIES = [
  { id: "seedfox", name: "새싹이", speciesName: "새싹이 계열", forms: ["새싹이", "잎새랑", "수림호"], type: "잎", color: "#4f8d52", description: "작은 씨앗에 담긴 커다란 가능성. 다정한 숲의 친구.", skills: ["씨앗 찌르기", "덩굴 방패", "숲의 맥박"], effects: ["잎 타입 공격", "한 턴 동안 방어 강화", "잎 타입 강공격"] },
  { id: "bubblepenguin", name: "방울핀", speciesName: "방울핀 계열", forms: ["방울핀", "물결핀", "피오레"], type: "물", color: "#4199ba", description: "물방울처럼 맑고 호기심 많은 친구. 차곡차곡 자라는 힘.", skills: ["물방울포", "샘물 막", "조류 파동"], effects: ["물 타입 공격", "받는 피해 경감", "물 타입 강공격"] },
  { id: "embersalamander", name: "불꼬리", speciesName: "불꼬리 계열", forms: ["불꼬리", "홍염랑", "부랑"], type: "불", color: "#d77b50", description: "따뜻한 불씨를 품은 씩씩한 친구. 열정만큼 쑥쑥 성장해요.", skills: ["불씨 꼬리", "온기 장막", "해불 폭발"], effects: ["불 타입 공격", "방어 강화", "불 타입 강공격"] },
  { id: "kitesquirrel", name: "솔비", speciesName: "솔비 계열", forms: ["솔비", "풍다람", "솔바람"], type: "바람", color: "#669c92", description: "산들바람을 타고 새로운 하루로. 가볍고 날렵한 모험가.", skills: ["산들 베기", "순풍 질주", "구름 낙하"], effects: ["바람 타입 공격", "다음 턴 선공", "바람 타입 강공격"] },
  { id: "pebblemole", name: "조약콩", speciesName: "조약콩 계열", forms: ["조약콩", "바위굴", "맥"], type: "흙", color: "#a78c68", description: "묵묵히 땅을 다지는 든든한 친구. 함께라면 걱정 없어요.", skills: ["자갈 던지기", "흙벽", "산등 충격"], effects: ["흙 타입 공격", "받는 피해 경감", "흙 타입 강공격"] },
  { id: "glowmoth", name: "반디솜", speciesName: "반디솜 계열", forms: ["반디솜", "빛나래", "휘여명"], type: "빛", color: "#bd9c42", description: "은은한 빛으로 곁을 밝혀요. 작은 날갯짓 속 특별한 힘.", skills: ["새벽 가루", "등불 보호", "황금 광선"], effects: ["빛 타입 공격", "방어 강화", "빛 타입 강공격"] },
  { id: "mossmushroom", name: "포슬이", speciesName: "포슬이 계열", forms: ["포슬이", "이끼둥", "고목령"], type: "잎", color: "#4f8d52", description: "폭신한 버섯 모자 아래 다정한 마음. 천천히 숲을 지키는 친구로 자라요.", skills: ["포자 톡톡", "이끼 망토", "고목의 포효"], effects: ["잎 타입 공격", "한 턴 동안 방어 강화", "잎 타입 강공격"] },
  { id: "tidalray", name: "납작이", speciesName: "납작이 계열", forms: ["납작이", "너울랑", "해울"], type: "물", color: "#4199ba", description: "너울을 타고 둥실 헤엄치는 친구. 넓은 지느러미로 바다를 품어요.", skills: ["물결 찰싹", "너울 장막", "해류 날개"], effects: ["물 타입 공격", "받는 피해 경감", "물 타입 강공격"] },
  { id: "kilncrab", name: "딱불이", speciesName: "딱불이 계열", forms: ["딱불이", "숯집게", "용암각"], type: "불", color: "#d77b50", description: "작은 집게에 따뜻한 불씨를 꼭 쥐었어요. 단단한 등껍질 속 용감한 마음.", skills: ["불똥 집게", "숯불 갑옷", "용암 집게"], effects: ["불 타입 공격", "방어 강화", "불 타입 강공격"] },
  { id: "reedstork", name: "삐죽이", speciesName: "삐죽이 계열", forms: ["삐죽이", "휘파람", "창공루"], type: "바람", color: "#669c92", description: "커다란 부리와 사뿐한 발걸음. 날개를 펼치면 하늘도 든든한 놀이터예요.", skills: ["부리 돌풍", "깃털 활공", "창공 가르기"], effects: ["바람 타입 공격", "다음 턴 선공", "바람 타입 강공격"] },
  { id: "claygolem", name: "흙몽이", speciesName: "흙몽이 계열", forms: ["흙몽이", "옹기둥", "태산옹"], type: "흙", color: "#a78c68", description: "동그란 흙 몸에 새겨진 순한 미소. 차곡차곡 쌓인 힘으로 친구를 지켜요.", skills: ["흙손 콩", "옹기 방벽", "태산 주먹"], effects: ["흙 타입 공격", "받는 피해 경감", "흙 타입 강공격"] },
  { id: "prismtortoise", name: "반짝이", speciesName: "반짝이 계열", forms: ["반짝이", "수정갑", "휘광룡"], type: "빛", color: "#bd9c42", description: "반짝이는 수정집을 등에 멘 친구. 느려도 씩씩하게 빛나는 길을 걸어요.", skills: ["빛방울", "수정 방패", "휘광 파동"], effects: ["빛 타입 공격", "방어 강화", "빛 타입 강공격"] },
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
