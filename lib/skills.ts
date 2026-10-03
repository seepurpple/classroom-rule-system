import type { StatKey } from "./types";

export const PET_TYPES = ["풀", "물", "불", "비행", "땅", "빛"] as const;
export type PetType = typeof PET_TYPES[number];
export type RankStat = Exclude<StatKey, "hp">;
export type Skill = {
  name: string; type: PetType; category: "공격" | "특수공격" | "변화기";
  powers: number[]; accuracy: number[]; description: string;
  selfRanks?: Partial<Record<RankStat, number>>; targetRanks?: Partial<Record<RankStat, number>>;
  rankChance?: number; criticalChance?: number; drain?: number; heal?: number;
  ignoreAbsoluteDefense?: boolean; ignoreType?: boolean; missRecoil?: number;
  noConsecutive?: boolean; recoilPower?: number; recharge?: boolean;
  priority?: number; guard?: boolean; reflect?: boolean; clearBoosts?: boolean;
  healWithoutGuard?: number; dot?: { turns: number; damage: number };
};

export const SPECIES_SKILLS: Record<string, Skill[]> = {
  seedfox: [
    {"name": "씨뱉기", "type": "풀", "category": "공격", "powers": [15, 30, 50], "accuracy": [100, 90, 75], "description": "최대 3회 연속 공격. 빗나가면 중단."},
    {"name": "껍질 숨기", "type": "풀", "category": "변화기", "powers": [], "accuracy": [100], "description": "방어·특수방어 1랭크 상승.", "selfRanks": {"defense": 1, "specialDefense": 1}},
    {"name": "숲의 맥박", "type": "풀", "category": "특수공격", "powers": [70], "accuracy": [100], "description": "실제 가한 피해의 30% 회복.", "drain": 0.3},
  ],
  bubblepenguin: [
    {"name": "물총", "type": "물", "category": "공격", "powers": [35], "accuracy": [100], "description": "치명타 확률 60%.", "criticalChance": 0.6},
    {"name": "다이브인", "type": "비행", "category": "공격", "powers": [60], "accuracy": [80], "description": "추가 효과 없음."},
    {"name": "해류순환", "type": "물", "category": "공격", "powers": [90, 45], "accuracy": [100, 50], "description": "최대 2회 연속 공격. 빗나가면 중단."},
  ],
  embersalamander: [
    {"name": "점화", "type": "불", "category": "특수공격", "powers": [40], "accuracy": [100], "description": "상대의 절대방어 무시. 일반 특수방어는 적용.", "ignoreAbsoluteDefense": true},
    {"name": "화염 채찍", "type": "불", "category": "공격", "powers": [60], "accuracy": [100], "description": "추가 효과 없음."},
    {"name": "염무", "type": "불", "category": "공격", "powers": [90], "accuracy": [90], "description": "타입 상성 1배 고정. 자속 보너스는 적용.", "ignoreType": true},
  ],
  kitesquirrel: [
    {"name": "산들 베기", "type": "비행", "category": "공격", "powers": [40], "accuracy": [100], "description": "25% 확률로 스피드 1랭크 상승.", "selfRanks": {"speed": 1}, "rankChance": 0.25},
    {"name": "언페어윈드", "type": "비행", "category": "변화기", "powers": [], "accuracy": [90], "description": "상대 방어 1랭크 하락.", "targetRanks": {"defense": -1}},
    {"name": "고공낙하", "type": "비행", "category": "공격", "powers": [150], "accuracy": [55], "description": "빗나가면 자신에게 고정 피해 20.", "missRecoil": 20},
  ],
  pebblemole: [
    {"name": "돌 던지기", "type": "땅", "category": "공격", "powers": [50], "accuracy": [90], "description": "추가 효과 없음."},
    {"name": "주상절리", "type": "땅", "category": "변화기", "powers": [], "accuracy": [100], "description": "방어 2랭크 상승. 연속 사용 실패.", "selfRanks": {"defense": 2}, "noConsecutive": true},
    {"name": "지진", "type": "땅", "category": "공격", "powers": [150], "accuracy": [100], "description": "자신도 위력 50의 공격을 받음. 연속 사용 실패.", "recoilPower": 50, "noConsecutive": true},
  ],
  glowmoth: [
    {"name": "인편 날리기", "type": "비행", "category": "특수공격", "powers": [30], "accuracy": [95], "description": "30% 확률로 상대 스피드 1랭크 하락.", "targetRanks": {"speed": -1}, "rankChance": 0.3},
    {"name": "반딧불이", "type": "빛", "category": "특수공격", "powers": [60], "accuracy": [100], "description": "추가 효과 없음."},
    {"name": "스피드스타", "type": "빛", "category": "특수공격", "powers": [90], "accuracy": [90], "description": "추가 효과 없음."},
  ],
  mossmushroom: [
    {"name": "홀씨", "type": "풀", "category": "특수공격", "powers": [40], "accuracy": [95], "description": "실제 가한 피해의 20% 회복.", "drain": 0.2},
    {"name": "지의", "type": "땅", "category": "변화기", "powers": [], "accuracy": [100], "description": "특수방어 2랭크 상승.", "selfRanks": {"specialDefense": 2}},
    {"name": "생명의 샘", "type": "땅", "category": "공격", "powers": [150], "accuracy": [100], "description": "사용 후 다음 턴 행동 불가.", "recharge": true},
  ],
  tidalray: [
    {"name": "워터웨이브", "type": "물", "category": "공격", "powers": [45], "accuracy": [100], "description": "추가 효과 없음."},
    {"name": "물너울", "type": "물", "category": "변화기", "powers": [], "accuracy": [100], "description": "선공. 이번 턴 절대방어 확률 60%. 성공하면 상대 스피드 2랭크 하락.", "priority": 1, "guard": true},
    {"name": "낙조", "type": "빛", "category": "특수공격", "powers": [75], "accuracy": [100], "description": "명중한 턴부터 3턴간 턴 종료 시 고정 피해 10.", "dot": {"turns": 3, "damage": 10}},
  ],
  kilncrab: [
    {"name": "불집기", "type": "불", "category": "공격", "powers": [45], "accuracy": [100], "description": "추가 효과 없음."},
    {"name": "번개탄", "type": "땅", "category": "변화기", "powers": [], "accuracy": [100], "description": "스피드 2랭크 하락. 방어·특수방어 2랭크 상승.", "selfRanks": {"speed": -2, "defense": 2, "specialDefense": 2}},
    {"name": "분화", "type": "불", "category": "공격", "powers": [110], "accuracy": [70], "description": "추가 효과 없음."},
  ],
  reedstork: [
    {"name": "쪼기", "type": "비행", "category": "공격", "powers": [35], "accuracy": [100], "description": "치명타 확률 60%.", "criticalChance": 0.6},
    {"name": "활공", "type": "비행", "category": "변화기", "powers": [], "accuracy": [100], "description": "체력 10 회복. 20% 확률로 스피드 1랭크 상승.", "heal": 10, "selfRanks": {"speed": 1}, "rankChance": 0.2},
    {"name": "천계의 빛", "type": "빛", "category": "특수공격", "powers": [80, 80, 80], "accuracy": [100, 65, 30], "description": "최대 3회 연속 공격. 빗나가면 중단."},
  ],
  claygolem: [
    {"name": "가마 부수기", "type": "땅", "category": "공격", "powers": [45], "accuracy": [100], "description": "추가 효과 없음."},
    {"name": "재어넣기", "type": "불", "category": "공격", "powers": [70], "accuracy": [100], "description": "상대의 양수 랭크를 모두 0으로. 하락 랭크는 유지.", "clearBoosts": true},
    {"name": "옹골참", "type": "땅", "category": "공격", "powers": [40], "accuracy": [100], "description": "방어·특수방어 1랭크 상승.", "selfRanks": {"defense": 1, "specialDefense": 1}},
  ],
  prismtortoise: [
    {"name": "빛방울", "type": "빛", "category": "특수공격", "powers": [45], "accuracy": [100], "description": "추가 효과 없음."},
    {"name": "만화경", "type": "빛", "category": "변화기", "powers": [], "accuracy": [100], "description": "선공. 이번 턴 받는 공격 피해를 막고 그대로 반사. 연속 사용 실패.", "priority": 1, "reflect": true, "noConsecutive": true},
    {"name": "빛나는 땅", "type": "땅", "category": "공격", "powers": [110], "accuracy": [100], "description": "상대 절대방어 미발동 시 체력 10 회복. 연속 사용 실패.", "healWithoutGuard": 10, "noConsecutive": true},
  ],
};
