import { addExperience, evolutionName, getItem, getSpecies, stageForLevel } from "./catalog";
import type { LogEntry, Student } from "./types";
import { emptyStats, validAllocation, statLimit, statTotal } from "./stats";

export class FarmError extends Error {
  constructor(message: string, public status = 400) { super(message); }
}
export type StoredUser = Student & { claimedStarter: boolean };
export type FarmDocument = { className: string; users: StoredUser[] };
export type Payload = Record<string, unknown> & { action: string; requestId: string };

export function requiredText(value: unknown, label: string, max = 200, min = 1): string {
  if (typeof value !== "string" || value.trim().length < min || value.trim().length > max || Array.from(value).some(c => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127)) {
    throw new FarmError(`${label} 값을 확인해 주세요.`);
  }
  return value.trim();
}
export function integer(value: unknown, label: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < min || value > max) throw new FarmError(`${label}: ${min}~${max} 사이 정수를 입력해 주세요.`);
  return value;
}
function student(doc: FarmDocument, id: unknown): StoredUser {
  const result = doc.users.find(u => u.id === id && u.role === "student");
  if (!result) throw new FarmError("학생을 찾을 수 없습니다.", 404);
  return result;
}
function petFor(owner: StoredUser, id: unknown) {
  const pet = owner.pets.find(p => p.id === id);
  if (!pet) throw new FarmError("내 펫을 찾을 수 없습니다.", 404);
  return pet;
}
function grantFor(owner: StoredUser, id: unknown) {
  const grant = owner.inventory.find(g => g.id === id);
  if (!grant) throw new FarmError("지급된 아이템을 찾을 수 없습니다.", 404);
  return grant;
}
function take(owner: StoredUser, id: unknown, quantity: number) {
  const grant = grantFor(owner, id);
  if (grant.revoked || grant.remaining < quantity) throw new FarmError("사용 가능한 아이템 수량이 부족합니다.", 409);
  grant.remaining -= quantity;
  return grant;
}
function learnNaturalSkills(pet: ReturnType<typeof petFor>) {
  const species = getSpecies(pet.speciesId)!;
  for (const skill of species.skills.slice(0, pet.stage)) {
    if (!pet.skills.includes(skill)) pet.skills.push(skill);
  }
}

// Mutates a private copy; the server commits this document and its audit entry atomically.
export function applyAction(doc: FarmDocument, actorId: string, body: Payload): { message: string; log: LogEntry } {
  const actor = doc.users.find(u => u.id === actorId);
  if (!actor) throw new FarmError("다시 로그인해 주세요.", 401);
  const teacherActions = ["grant", "adjustLevel"];
  const studentActions = ["choosePet", "useItem", "representative", "release", "allocateStats"];
  if ((teacherActions.includes(body.action) && actor.role !== "teacher") || (studentActions.includes(body.action) && actor.role !== "student")) throw new FarmError("이 작업을 할 권한이 없습니다.", 403);
  let message = "";
  let studentId: string | null = actor.role === "student" ? actor.id : null;
  if (body.action === "grant") {
    const target = student(doc, body.studentId);
    const item = getItem(requiredText(body.sku, "아이템", 80));
    if (!item) throw new FarmError("등록되지 않은 아이템입니다.");
    const quantity = integer(body.quantity, "수량", 1, 999);
    const reference = requiredText(body.reference, "구매 번호", 100);
    const note = body.note === "" || body.note === undefined ? "" : requiredText(body.note, "메모", 300);
    if (doc.users.some(u => u.inventory.some(g => g.reference === reference))) throw new FarmError("이미 지급한 구매 번호입니다. 구매 내역을 확인해 주세요.", 409);
    target.inventory.push({ id: crypto.randomUUID(), sku: item.sku, quantity, remaining: quantity, reference, note, createdAt: new Date().toISOString(), revoked: false });
    studentId = target.id;
    message = `${target.name}에게 ${item.name} ${quantity}개 지급 · 구매 ${reference}${note ? ` · ${note}` : ""}`;
  } else if (body.action === "choosePet") {
    const species = getSpecies(requiredText(body.speciesId, "펫 종", 50));
    if (!species) throw new FarmError("등록되지 않은 펫 종입니다.");
    if (actor.pets.length >= 3) throw new FarmError("펫은 최대 3마리까지 키울 수 있습니다.", 409);
    if (actor.pets.some(p => p.speciesId === species.id)) throw new FarmError("이미 키우고 있는 종입니다. 다른 종을 선택해 주세요.", 409);
    const first = !actor.claimedStarter;
    if (!first) {
      const ticket = grantFor(actor, body.grantId);
      if (ticket.sku !== "pet-choice-ticket") throw new FarmError("펫 선택권이 필요합니다.");
      take(actor, ticket.id, 1);
    }
    actor.claimedStarter = true;
    actor.pets.push({ id: crypto.randomUUID(), speciesId: species.id, level: 1, xp: 0, stage: 1, skills: [species.skills[0]], createdAt: new Date().toISOString(), representative: actor.pets.length === 0 });
    message = `${actor.name} · ${evolutionName(species.id, 1)} ${first ? "첫 펫 선택" : "선택권 사용으로 획득"}`;
  } else if (body.action === "useItem") {
    const pet = petFor(actor, body.petId);
    const grant = grantFor(actor, body.grantId);
    const item = getItem(grant.sku);
    if (!item) throw new FarmError("더 이상 판매하지 않는 아이템입니다.", 409);
    const quantity = integer(body.quantity, "사용 수량", 1, 999);
    if (item.kind === "food") {
      if (pet.level >= 30) throw new FarmError("최대 레벨 펫에게는 음식을 사용할 수 없습니다.", 409);
      let level = pet.level, xp = pet.xp, stage = pet.stage;
      for (let i = 0; i < quantity; i++) {
        if (level >= 30) throw new FarmError("최대 레벨 이후 남을 음식이 있습니다. 사용 수량을 줄여 주세요.", 409);
        ({ level, xp, stage } = addExperience(level, xp, item.xp!));
      }
      take(actor, grant.id, quantity);
      Object.assign(pet, { level, xp, stage });
      learnNaturalSkills(pet);
      message = `${actor.name} · ${evolutionName(pet.speciesId, stage)}에게 ${item.name} ${quantity}개 사용 · Lv.${level}`;
    } else if (item.kind === "skill") {
      if (quantity !== 1) throw new FarmError("기술 카드는 한 번에 1개만 사용합니다.");
      if (pet.speciesId !== item.speciesId || pet.stage < item.stage! || pet.level < (item.stage === 2 ? 10 : 20)) throw new FarmError("펫 종 또는 기술 습득 레벨 조건을 충족하지 못했습니다.", 409);
      if (pet.skills.includes(item.name)) throw new FarmError("이미 배운 기술입니다.", 409);
      take(actor, grant.id, 1);
      pet.skills.push(item.name);
      message = `${actor.name} · ${evolutionName(pet.speciesId, pet.stage)}에게 ${item.name} 기술 습득`;
    } else {
      throw new FarmError(item.kind === "potion" ? "체력 물약은 결투 업데이트 후 사용할 수 있습니다." : "펫 선택권은 새 펫 선택 화면에서 사용해 주세요.", 409);
    }
  } else if (body.action === "allocateStats") {
    const pet = petFor(actor, body.petId);
    if (!validAllocation(body.allocation, pet.level)) throw new FarmError(`남은 포인트와 스탯별 한도(+${statLimit(pet.level)})를 확인해 주세요. 0 이상의 정수만 사용할 수 있습니다.`);
    pet.statAllocation = { ...body.allocation };
    message = `${actor.name} · ${evolutionName(pet.speciesId, pet.stage)} 스탯 ${statTotal(pet.statAllocation)}포인트 배분 저장`;
  } else if (body.action === "representative") {
    const chosen = petFor(actor, body.petId);
    actor.pets.forEach(p => { p.representative = p.id === chosen.id; });
    message = `${actor.name} · 대표 펫을 ${evolutionName(chosen.speciesId, chosen.stage)}(으)로 변경`;
  } else if (body.action === "release") {
    const pet = petFor(actor, body.petId);
    actor.pets.splice(actor.pets.indexOf(pet), 1);
    if (pet.representative && actor.pets[0]) actor.pets[0].representative = true;
    message = `${actor.name} · ${evolutionName(pet.speciesId, pet.stage)} Lv.${pet.level}을(를) 놓아줌`;
  } else if (body.action === "adjustLevel") {
    const target = student(doc, body.studentId);
    const pet = petFor(target, body.petId);
    const level = integer(body.level, "레벨", 1, 30);
    const note = requiredText(body.note, "조정 사유", 300);
    const before = pet.level;
    pet.level = level;
    pet.xp = 0;
    pet.stage = stageForLevel(level);
    const resetStats = pet.statAllocation && !validAllocation(pet.statAllocation, level);
    if (resetStats) pet.statAllocation = emptyStats();
    learnNaturalSkills(pet);
    studentId = target.id;
    message = `${target.name} · ${evolutionName(pet.speciesId, pet.stage)} Lv.${before} → Lv.${level} 조정 (경험치 0)${resetStats ? " · 스탯 한도 초과로 배분 초기화" : ""} · ${note}`;
  } else {
    throw new FarmError("지원하지 않는 작업입니다.");
  }
  return { message, log: { id: crypto.randomUUID(), studentId, actorName: actor.name, message, createdAt: new Date().toISOString() } };
}
